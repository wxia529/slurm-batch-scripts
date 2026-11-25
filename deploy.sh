#!/usr/bin/env bash

# Deploy one cluster into an install directory and then make that directory
# read-only. A successful run records .slurm-batchs-managed and
# .slurm-batchs-baseline. The baseline is the only path excluded from content
# checks: its own digest cannot be stored inside itself. That exception is the
# single filename .slurm-batchs-baseline at the install root. Same-account
# edits to the baseline are not detected.

set -euo pipefail

BASELINE_NAME=".slurm-batchs-baseline"
MANIFEST_NAME=".slurm-batchs-managed"
BASELINE_VERSION="slurm-batchs-baseline-v1"
METADATA_EXCEPTION_LINE="metadata-exception=${BASELINE_NAME}"

STAGING_DIR=""
BACKUP_DIR=""
MODE_LOG=""
CREATED_FILES=""
CREATED_DIRS=""
PROTECTION_DIRTY=false
TARGET_DIR=""
CLUSTER=""
ADOPT_LEGACY=false
ACCEPT_EXISTING=false

usage() {
    cat <<'EOF'
Usage:
  deploy.sh <cluster>
  deploy.sh --accept-existing <cluster>
  deploy.sh --adopt-legacy <cluster>
  deploy.sh --adopt-legacy --accept-existing <cluster>
  deploy.sh -h | --help

Cluster:
  mindu
  neimeng-2
  tianjin

Target:
  ~/soft/slurm-batchs
  Override with SLURM_BATCHS_TARGET.

A successful deploy records a managed-path manifest and a content baseline,
then sets directories and executable scripts to mode 555 and other files to
mode 444. The next deploy compares the install tree with that baseline before
changing permissions or files. Added, modified, or missing paths stop the
deploy. --accept-existing is the confirmation step for an existing install
that has no baseline yet. It does not delete unlisted files.
EOF
}

die() {
    echo "Error: $*" >&2
    exit 1
}

failpoint() {
    if [[ "${SLURM_BATCHS_INJECT_FAILURE:-}" == "$1" ]]; then
        echo "Error: Injected deployment failure at $1." >&2
        exit 1
    fi
}

cleanup() {
    local status=$?
    if [[ "$PROTECTION_DIRTY" == true ]]; then
        restore_protection || echo "Warning: failed to restore install-tree protection." >&2
    fi
    if [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" ]]; then
        rm -rf -- "$STAGING_DIR"
    fi
    if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
        rm -rf -- "$BACKUP_DIR"
    fi
    exit "$status"
}

trap cleanup EXIT

validate_rel_path() {
    local rel=$1
    local part
    local -a parts=()
    if [[ -z "$rel" || "$rel" == /* || "$rel" == *".."* ]]; then
        die "Unsafe relative path in deployment metadata: ${rel}"
    fi
    if [[ "$rel" == *$'\n'* || "$rel" == *$'\t'* ]]; then
        die "Unsafe relative path in deployment metadata: ${rel}"
    fi
    IFS=/ read -ra parts <<< "$rel"
    for part in "${parts[@]}"; do
        if [[ -z "$part" || "$part" == "." || "$part" == ".." ]]; then
            die "Unsafe relative path in deployment metadata: ${rel}"
        fi
    done
}

display_path() {
    local rel=$1
    rel=${rel//$'\n'/\\n}
    printf '%s\n' "$rel"
}

normalize_mode() {
    local mode=$1
    if [[ ! "$mode" =~ ^[0-7]+$ ]]; then
        echo "Error: Invalid permission value: ${mode}" >&2
        return 1
    fi
    printf '%o\n' "$((8#$mode))"
}

file_sha256() {
    local path=$1
    if [[ -L "$path" || ! -f "$path" ]]; then
        echo "Error: Refusing to hash a non-regular file: ${path}" >&2
        return 1
    fi
    sha256sum -- "$path" | awk 'NR==1 { print $1 }'
}

mode_for() {
    local kind=$1
    local rel=$2
    if [[ "$kind" == "d" ]]; then
        printf '555\n'
    elif [[ "$rel" == *.sh ]]; then
        printf '555\n'
    else
        printf '444\n'
    fi
}

is_dangerous_target() {
    local path=$1
    case "$path" in
        /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/proc|/root|/run|/sbin|/sys|/tmp|/usr|/var)
            return 0
            ;;
    esac
    if [[ -n "${HOME:-}" && "$path" == "$HOME" ]]; then
        return 0
    fi
    return 1
}

canonicalize_target() {
    local path=$1
    local existing rest base

    if [[ "$path" != /* ]]; then
        path="${PWD}/${path}"
    fi
    while [[ "$path" != "/" && "$path" == */ ]]; do
        path=${path%/}
    done

    if [[ -L "$path" ]]; then
        die "Refusing to deploy through a symbolic-link target: ${path}"
    fi

    existing=$path
    rest=""
    while [[ ! -d "$existing" || -L "$existing" ]]; do
        if [[ -L "$existing" ]]; then
            die "Refusing to deploy through a symbolic-link path: ${existing}"
        fi
        if [[ -e "$existing" ]]; then
            die "Deployment target is not a directory: ${existing}"
        fi
        if [[ "$existing" == "/" ]]; then
            break
        fi
        if [[ -n "$rest" ]]; then
            rest="${existing##*/}/${rest}"
        else
            rest=${existing##*/}
        fi
        existing=${existing%/*}
        if [[ -z "$existing" ]]; then
            existing="/"
        fi
    done

    if [[ ! -d "$existing" || -L "$existing" ]]; then
        die "Deployment target parent is missing: ${path}"
    fi
    base=$(cd -- "$existing" && pwd -P)
    if [[ -n "$rest" ]]; then
        if [[ "$base" == "/" ]]; then
            printf '/%s\n' "$rest"
        else
            printf '%s/%s\n' "$base" "$rest"
        fi
    else
        printf '%s\n' "$base"
    fi
}

declare -A PREVIOUSLY_MANAGED=()
declare -A ACCOUNTED=()
declare -A EXPECTED_TYPE=()
declare -A EXPECTED_MODE=()
declare -A EXPECTED_HASH=()
declare -A SEEN_PATH=()
declare -A MODE_RECORDED=()

reset_expected() {
    EXPECTED_TYPE=()
    EXPECTED_MODE=()
    EXPECTED_HASH=()
    SEEN_PATH=()
}

account_path() {
    local rel=$1
    ACCOUNTED["$rel"]=1
    while [[ "$rel" == */* ]]; do
        rel=${rel%/*}
        ACCOUNTED["$rel"]=1
    done
}

load_manifest() {
    local line rel
    DEPLOYED_CLUSTER=""
    PREVIOUSLY_MANAGED=()
    if [[ -L "$MANIFEST_FILE" ]]; then
        die "Deployment manifest must not be a symbolic link: ${MANIFEST_FILE}"
    fi
    if [[ -f "$MANIFEST_FILE" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -n "$line" ]] || continue
            case "$line" in
                cluster=*)
                    if [[ -n "$DEPLOYED_CLUSTER" && "$DEPLOYED_CLUSTER" != "${line#cluster=}" ]]; then
                        die "Deployment manifest contains conflicting cluster records."
                    fi
                    DEPLOYED_CLUSTER=${line#cluster=}
                    ;;
                *)
                    validate_rel_path "$line"
                    if [[ "$line" == "$MANIFEST_NAME" || "$line" == "$BASELINE_NAME" ]]; then
                        die "Deployment manifest must not list metadata path: ${line}"
                    fi
                    PREVIOUSLY_MANAGED["$line"]=1
                    ;;
            esac
        done < "$MANIFEST_FILE"
    elif [[ -e "$MANIFEST_FILE" ]]; then
        die "Deployment manifest is not a regular file: ${MANIFEST_FILE}"
    fi
}

load_baseline() {
    local line type mode hash rel normalized
    reset_expected
    BASELINE_CLUSTER=""
    if [[ ! -e "$BASELINE_FILE" && ! -L "$BASELINE_FILE" ]]; then
        return 1
    fi
    if [[ -L "$BASELINE_FILE" || ! -f "$BASELINE_FILE" ]]; then
        die "Content baseline must be a regular file: ${BASELINE_FILE}"
    fi
    {
        IFS= read -r line || true
        [[ "$line" == "$BASELINE_VERSION" ]] || die "Unsupported content baseline format: ${BASELINE_FILE}"
        IFS= read -r line || true
        [[ "$line" == cluster=* ]] || die "Content baseline is missing its cluster record: ${BASELINE_FILE}"
        BASELINE_CLUSTER=${line#cluster=}
        IFS= read -r line || true
        [[ "$line" == "$METADATA_EXCEPTION_LINE" ]] || die "Content baseline metadata exception is not recognized: ${BASELINE_FILE}"
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -n "$line" ]] || die "Content baseline contains an empty record: ${BASELINE_FILE}"
            IFS=$'\t' read -r type mode hash rel <<< "$line"
            [[ -n "${rel:-}" ]] || die "Content baseline record is incomplete: ${BASELINE_FILE}"
            if [[ "$rel" == "$BASELINE_NAME" ]]; then
                die "Content baseline must not include its own path."
            fi
            if [[ "$rel" != "." ]]; then
                validate_rel_path "$rel"
            fi
            case "$type" in
                d|f) ;;
                *) die "Content baseline has an unknown entry type for ${rel}." ;;
            esac
            normalized=$(normalize_mode "$mode") || die "Content baseline has invalid permissions for ${rel}."
            if [[ "$type" == "d" && "$hash" != "-" ]]; then
                die "Content baseline directory record is invalid for ${rel}."
            fi
            if [[ "$type" == "f" && ! "$hash" =~ ^[0-9a-f]{64}$ ]]; then
                die "Content baseline file digest is invalid for ${rel}."
            fi
            if [[ -n "${EXPECTED_TYPE[$rel]:-}" ]]; then
                die "Content baseline lists ${rel} more than once."
            fi
            EXPECTED_TYPE["$rel"]=$type
            EXPECTED_MODE["$rel"]=$normalized
            EXPECTED_HASH["$rel"]=$hash
        done
    } < "$BASELINE_FILE"
    [[ "${EXPECTED_TYPE["."]:-}" == "d" ]] || die "Content baseline does not record the install directory."
    for rel in "${!EXPECTED_TYPE[@]}"; do
        [[ "$rel" == "." ]] && continue
        local parent=${rel%/*}
        if [[ "$rel" != */* ]]; then
            parent="."
        fi
        [[ "${EXPECTED_TYPE[$parent]:-}" == "d" ]] || die "Content baseline is missing the parent of ${rel}."
    done
    return 0
}

disk_kind() {
    local path=$1
    if [[ -L "$path" ]]; then
        printf 'link\n'
    elif [[ -d "$path" ]]; then
        printf 'd\n'
    elif [[ -f "$path" ]]; then
        printf 'f\n'
    else
        printf 'other\n'
    fi
}

collect_drift() {
    local path rel kind expected mode actual_mode hash
    DRIFT_ADDED=()
    DRIFT_MISSING=()
    DRIFT_MODIFIED=()
    DRIFT_PERMISSION=()
    DRIFT_UNEXPECTED=()
    SEEN_PATH=()
    SEEN_PATH["."]=1

    kind=$(disk_kind "$TARGET_DIR")
    if [[ "$kind" != "d" ]]; then
        DRIFT_UNEXPECTED+=(".")
    else
        actual_mode=$(normalize_mode "$(stat -c '%a' -- "$TARGET_DIR")")
        if [[ "${EXPECTED_MODE["."]:-}" != "$actual_mode" ]]; then
            DRIFT_PERMISSION+=(". recorded=${EXPECTED_MODE["."]:-} found=${actual_mode}")
        fi
    fi

    while IFS= read -r -d '' path; do
        rel=${path#"$TARGET_DIR"/}
        if [[ "$rel" == *$'\n'* || "$rel" == *$'\t'* ]]; then
            DRIFT_UNEXPECTED+=("$(display_path "$rel")")
            continue
        fi
        kind=$(disk_kind "$path")
        if [[ "$rel" == "$BASELINE_NAME" ]]; then
            SEEN_PATH["$rel"]=1
            if [[ "$kind" != "f" ]]; then
                DRIFT_UNEXPECTED+=("${rel}")
            else
                actual_mode=$(normalize_mode "$(stat -c '%a' -- "$path")")
                if [[ "$actual_mode" != "444" ]]; then
                    DRIFT_PERMISSION+=("${rel} recorded=444 found=${actual_mode}")
                fi
            fi
            continue
        fi
        if [[ -z "${EXPECTED_TYPE[$rel]:-}" ]]; then
            DRIFT_ADDED+=("$rel")
            continue
        fi
        SEEN_PATH["$rel"]=1
        expected=${EXPECTED_TYPE[$rel]}
        if [[ "$kind" != "$expected" ]]; then
            DRIFT_UNEXPECTED+=("${rel} recorded=${expected} found=${kind}")
            continue
        fi
        actual_mode=$(normalize_mode "$(stat -c '%a' -- "$path")")
        if [[ "$actual_mode" != "${EXPECTED_MODE[$rel]}" ]]; then
            DRIFT_PERMISSION+=("${rel} recorded=${EXPECTED_MODE[$rel]} found=${actual_mode}")
        fi
        if [[ "$expected" == "f" ]]; then
            hash=$(file_sha256 "$path")
            if [[ "$hash" != "${EXPECTED_HASH[$rel]}" ]]; then
                DRIFT_MODIFIED+=("$rel")
            fi
        fi
    done < <(find -P "$TARGET_DIR" -mindepth 1 -print0)

    for rel in "${!EXPECTED_TYPE[@]}"; do
        [[ -n "${SEEN_PATH[$rel]:-}" ]] && continue
        DRIFT_MISSING+=("$rel")
    done
}

drift_count() {
    local count=0
    count=$((count + ${#DRIFT_ADDED[@]} + ${#DRIFT_MISSING[@]} + ${#DRIFT_MODIFIED[@]}))
    count=$((count + ${#DRIFT_PERMISSION[@]} + ${#DRIFT_UNEXPECTED[@]}))
    printf '%s\n' "$count"
}

print_drift_paths() {
    local label=$1
    shift
    local -a items=("$@")
    local item
    if ((${#items[@]} == 0)); then
        return 0
    fi
    echo "$label" >&2
    while IFS= read -r item; do
        printf '  %s\n' "$item" >&2
    done < <(printf '%s\n' "${items[@]}" | LC_ALL=C sort)
}

report_drift() {
    local phase=$1
    echo "Error: Install tree does not match the content baseline: ${TARGET_DIR}" >&2
    print_drift_paths "Added:" "${DRIFT_ADDED[@]+"${DRIFT_ADDED[@]}"}"
    print_drift_paths "Modified:" "${DRIFT_MODIFIED[@]+"${DRIFT_MODIFIED[@]}"}"
    print_drift_paths "Missing:" "${DRIFT_MISSING[@]+"${DRIFT_MISSING[@]}"}"
    print_drift_paths "Permissions:" "${DRIFT_PERMISSION[@]+"${DRIFT_PERMISSION[@]}"}"
    print_drift_paths "Unexpected:" "${DRIFT_UNEXPECTED[@]+"${DRIFT_UNEXPECTED[@]}"}"
    if [[ "$phase" == "initial" ]]; then
        cat >&2 <<'EOF'
The install tree was left unchanged. Move added paths out of the install
directory, put missing paths back, and restore modified bytes or permissions
to the recorded baseline before deploying again.
EOF
    else
        echo "Restoring the previous install tree and permissions." >&2
    fi
    exit 1
}

print_path_group() {
    local label=$1
    shift
    local -a items=("$@")
    local item
    echo "$label" >&2
    if ((${#items[@]} == 0)); then
        echo "  (none)" >&2
        return 0
    fi
    while IFS= read -r item; do
        printf '  %s\n' "$item" >&2
    done < <(printf '%s\n' "${items[@]}" | LC_ALL=C sort)
}

audit_unbaselined_tree() {
    local path rel kind
    local -a managed_paths=()
    local -a extra_paths=()
    local saw_any=false
    ACCOUNTED=()
    ACCOUNTED["."]=1
    if [[ -f "$MANIFEST_FILE" && ! -L "$MANIFEST_FILE" ]]; then
        account_path "$MANIFEST_NAME"
    fi
    for rel in "${!PREVIOUSLY_MANAGED[@]}"; do
        account_path "$rel"
    done

    while IFS= read -r -d '' path; do
        saw_any=true
        rel=${path#"$TARGET_DIR"/}
        kind=$(disk_kind "$path")
        if [[ "$kind" == "link" || "$kind" == "other" ]]; then
            extra_paths+=("$(display_path "$rel") [${kind}]")
            continue
        fi
        if [[ "$rel" == *$'\n'* || "$rel" == *$'\t'* ]]; then
            extra_paths+=("$(display_path "$rel")")
            continue
        fi
        if [[ -z "${ACCOUNTED[$rel]:-}" ]]; then
            extra_paths+=("$rel")
            continue
        fi
        if [[ -n "${PREVIOUSLY_MANAGED[$rel]:-}" || "$rel" == "$MANIFEST_NAME" ]]; then
            if [[ "$kind" != "f" ]]; then
                extra_paths+=("${rel} [${kind}]")
            else
                managed_paths+=("$rel")
            fi
        elif [[ "$kind" != "d" ]]; then
            extra_paths+=("${rel} [${kind}]")
        fi
    done < <(find -P "$TARGET_DIR" -mindepth 1 -print0)

    if [[ "$saw_any" == false ]]; then
        return 0
    fi

    echo "Existing install directory has no content baseline: ${TARGET_DIR}" >&2
    print_path_group "Recorded deployment paths:" "${managed_paths[@]+"${managed_paths[@]}"}"
    print_path_group "Paths outside the recorded deployment:" "${extra_paths[@]+"${extra_paths[@]}"}"

    if [[ ! -f "$MANIFEST_FILE" || -L "$MANIFEST_FILE" ]]; then
        cat >&2 <<'EOF'
This directory has no deployment manifest. Refusing to incorporate existing
files into a new install. Choose an empty target directory.
EOF
        exit 1
    fi

    if ((${#extra_paths[@]} > 0)); then
        cat >&2 <<'EOF'
Refusing to continue while unrecorded paths remain. Move those paths out of
the install directory, then run the confirmation command. Nothing was deleted
or overwritten.
EOF
        exit 1
    fi

    if [[ -z "$DEPLOYED_CLUSTER" && "$ADOPT_LEGACY" != true ]]; then
        echo "Re-run with --adopt-legacy after confirming this target belongs to '${CLUSTER}'." >&2
        if [[ "$ACCEPT_EXISTING" != true ]]; then
            echo "Also pass --accept-existing to record the first content baseline." >&2
        fi
        exit 1
    fi

    if [[ "$ACCEPT_EXISTING" != true ]]; then
        if [[ -z "$DEPLOYED_CLUSTER" ]]; then
            echo "Re-run with --adopt-legacy --accept-existing ${CLUSTER} after reviewing the paths above." >&2
        else
            echo "Re-run with --accept-existing ${CLUSTER} after reviewing the paths above." >&2
        fi
        echo "The confirmation command updates files already recorded by the manifest and then records a baseline." >&2
        exit 1
    fi

    if [[ -z "$DEPLOYED_CLUSTER" ]]; then
        DEPLOYED_CLUSTER=$CLUSTER
    fi
    echo "Accepting existing deployment without a content baseline: ${TARGET_DIR}" >&2
}

within_target() {
    local path=$1
    [[ "$path" == "$TARGET_DIR" || "$path" == "$TARGET_DIR"/* ]]
}

unlock_path() {
    local path=$1
    local mode
    within_target "$path" || die "Refusing to change permissions outside the install tree: ${path}"
    if [[ -L "$path" ]]; then
        die "Refusing to change permissions through a symbolic link: ${path}"
    fi
    if [[ ! -e "$path" ]]; then
        die "Missing install path while preparing permissions: ${path}"
    fi
    if [[ -n "${MODE_RECORDED[$path]:-}" ]]; then
        return 0
    fi
    mode=$(stat -c '%a' -- "$path") || die "Cannot read permissions: ${path}"
    printf '%s %s\n' "$mode" "$path" >> "$MODE_LOG"
    MODE_RECORDED["$path"]=$mode
    PROTECTION_DIRTY=true
    chmod u+w -- "$path" || die "Cannot restore write permission: ${path}"
}

unlock_parents_and_file() {
    local rel=$1
    local dest="${TARGET_DIR}/${rel}"
    local cursor="$TARGET_DIR"
    local remainder=$rel
    local segment
    unlock_path "$TARGET_DIR"
    while [[ "$remainder" == */* ]]; do
        segment=${remainder%%/*}
        remainder=${remainder#*/}
        cursor="${cursor}/${segment}"
        if [[ -d "$cursor" && ! -L "$cursor" ]]; then
            unlock_path "$cursor"
        elif [[ -e "$cursor" || -L "$cursor" ]]; then
            die "Refusing to update through a non-directory: ${cursor}"
        fi
    done
    if [[ -L "$dest" ]]; then
        die "Refusing to update a symbolic link: ${dest}"
    fi
    if [[ -e "$dest" ]]; then
        [[ -f "$dest" ]] || die "Refusing to overwrite a non-regular destination: ${dest}"
        unlock_path "$dest"
    fi
}

backup_tree() {
    local path rel dest
    while IFS= read -r -d '' path; do
        if [[ -L "$path" ]]; then
            die "Refusing to back up a symbolic link: ${path}"
        fi
        if [[ -d "$path" ]]; then
            continue
        fi
        [[ -f "$path" ]] || die "Refusing to back up an unsupported install path: ${path}"
        rel=${path#"$TARGET_DIR"/}
        dest="${BACKUP_DIR}/files/${rel}"
        mkdir -p -- "$(dirname -- "$dest")"
        cp -a -- "$path" "$dest"
    done < <(find -P "$TARGET_DIR" -mindepth 1 -print0)
}

note_created_file() {
    local rel=$1
    local dest="${TARGET_DIR}/${rel}"
    if [[ -e "$dest" || -L "$dest" ]]; then
        return 0
    fi
    printf '%s\n' "$rel" >> "$CREATED_FILES"
}

note_created_dir() {
    local dir=$1
    within_target "$dir" || die "Refusing to track a directory outside the install tree: ${dir}"
    [[ "$dir" != "$TARGET_DIR" ]] || return 0
    printf '%s\n' "$dir" >> "$CREATED_DIRS"
}

ensure_dir() {
    local dir=$1
    local cursor="$TARGET_DIR"
    local rel segment
    within_target "$dir" || die "Refusing to create a directory outside the install tree: ${dir}"
    if [[ "$dir" == "$TARGET_DIR" ]]; then
        return 0
    fi
    rel=${dir#"$TARGET_DIR"/}
    while [[ -n "$rel" ]]; do
        segment=${rel%%/*}
        cursor="${cursor}/${segment}"
        if [[ -L "$cursor" ]]; then
            die "Refusing to create a directory through a symbolic link: ${cursor}"
        fi
        if [[ -d "$cursor" ]]; then
            :
        elif [[ -e "$cursor" ]]; then
            die "Refusing to replace a non-directory: ${cursor}"
        else
            mkdir -- "$cursor"
            note_created_dir "$cursor"
        fi
        if [[ "$rel" == */* ]]; then
            rel=${rel#*/}
        else
            break
        fi
    done
}

restore_protection() {
    local mode path rel dest parent src
    if [[ -d "${BACKUP_DIR}/files" ]]; then
        while IFS= read -r -d '' src; do
            rel=${src#"${BACKUP_DIR}/files/"}
            dest="${TARGET_DIR}/${rel}"
            within_target "$dest" || continue
            parent=$(dirname -- "$dest")
            if [[ -L "$parent" || -L "$dest" ]]; then
                echo "Warning: skipped restore through a symbolic link: ${dest}" >&2
                continue
            fi
            if [[ -d "$parent" ]]; then
                chmod u+w -- "$parent" || echo "Warning: cannot write directory for restore: ${parent}" >&2
            fi
            if [[ -f "$dest" && ! -L "$dest" ]]; then
                chmod u+w -- "$dest" || true
            fi
            cp -a -- "$src" "$dest" || echo "Warning: cannot restore ${dest}" >&2
        done < <(find -P "${BACKUP_DIR}/files" -type f -print0)
    fi

    if [[ -f "$CREATED_FILES" ]]; then
        while IFS= read -r rel || [[ -n "$rel" ]]; do
            [[ -n "$rel" ]] || continue
            dest="${TARGET_DIR}/${rel}"
            within_target "$dest" || continue
            if [[ -L "$dest" ]]; then
                echo "Warning: skipped removal of symbolic link created during deploy: ${dest}" >&2
                continue
            fi
            if [[ -f "$dest" ]]; then
                parent=$(dirname -- "$dest")
                chmod u+w -- "$parent" 2>/dev/null || true
                rm -f -- "$dest" || echo "Warning: cannot remove ${dest}" >&2
            fi
        done < "$CREATED_FILES"
    fi

    if [[ -f "$CREATED_DIRS" ]]; then
        while IFS= read -r path || [[ -n "$path" ]]; do
            [[ -n "$path" ]] || continue
            within_target "$path" || continue
            if [[ -L "$path" ]]; then
                echo "Warning: skipped removal of symbolic link directory: ${path}" >&2
                continue
            fi
            if [[ -d "$path" ]]; then
                rmdir -- "$path" 2>/dev/null || echo "Warning: leaving directory in place: ${path}" >&2
            fi
        done < <(LC_ALL=C sort -r "$CREATED_DIRS")
    fi

    if [[ -f "$MODE_LOG" ]]; then
        while read -r mode path || [[ -n "${path:-}" ]]; do
            [[ -n "${path:-}" ]] || continue
            within_target "$path" || continue
            if [[ -L "$path" || ! -e "$path" ]]; then
                echo "Warning: skipped permission restore for ${path}" >&2
                continue
            fi
            chmod -- "$mode" "$path" || echo "Warning: cannot restore permissions on ${path}" >&2
        done < "$MODE_LOG"
    fi
}

apply_readonly() {
    local path rel
    if [[ -L "$TARGET_DIR" || ! -d "$TARGET_DIR" ]]; then
        die "Install directory disappeared before it could be made read-only."
    fi
    chmod 555 -- "$TARGET_DIR"
    while IFS= read -r -d '' path; do
        if [[ -L "$path" ]]; then
            die "Refusing to change permissions through a symbolic link: ${path}"
        fi
        rel=${path#"$TARGET_DIR"/}
        if [[ -d "$path" ]]; then
            chmod 555 -- "$path"
        elif [[ -f "$path" ]]; then
            if [[ "$rel" == *.sh ]]; then
                chmod 555 -- "$path"
            else
                chmod 444 -- "$path"
            fi
        else
            die "Unsupported path while applying read-only permissions: ${path}"
        fi
    done < <(find -P "$TARGET_DIR" -mindepth 1 -print0)
}

write_baseline() {
    local path rel kind mode hash record_file
    record_file="${STAGING_DIR}/baseline-records"
    : > "$record_file"
    kind=$(disk_kind "$TARGET_DIR")
    [[ "$kind" == "d" ]] || die "Install directory is no longer a directory."
    printf 'd\t%s\t-\t.\n' "$(mode_for d .)" >> "$record_file"
    while IFS= read -r -d '' path; do
        rel=${path#"$TARGET_DIR"/}
        if [[ "$rel" == "$BASELINE_NAME" ]]; then
            continue
        fi
        if [[ -L "$path" ]]; then
            die "Refusing to record a symbolic link in the content baseline: ${path}"
        fi
        if [[ -d "$path" ]]; then
            kind="d"
            hash="-"
        elif [[ -f "$path" ]]; then
            kind="f"
            hash=$(file_sha256 "$path")
        else
            die "Unsupported path while recording the content baseline: ${path}"
        fi
        mode=$(mode_for "$kind" "$rel")
        printf '%s\t%s\t%s\t%s\n' "$kind" "$mode" "$hash" "$rel" >> "$record_file"
    done < <(find -P "$TARGET_DIR" -mindepth 1 -print0)

    {
        printf '%s\n' "$BASELINE_VERSION"
        printf 'cluster=%s\n' "$CLUSTER"
        printf '%s\n' "$METADATA_EXCEPTION_LINE"
        LC_ALL=C sort "$record_file"
    } > "${STAGING_DIR}/baseline"
    note_created_file "$BASELINE_NAME"
    unlock_parents_and_file "$BASELINE_NAME"
    install -m 0444 -- "${STAGING_DIR}/baseline" "$BASELINE_FILE"
}

for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        usage
        exit 0
    fi
done

while (($# > 0)); do
    case "$1" in
        --adopt-legacy)
            ADOPT_LEGACY=true
            ;;
        --accept-existing)
            ACCEPT_EXISTING=true
            ;;
        --)
            shift
            break
            ;;
        -*)
            die "Unknown option: $1"
            ;;
        *)
            if [[ -n "$CLUSTER" ]]; then
                die "Only one cluster can be deployed."
            fi
            CLUSTER=$1
            ;;
    esac
    shift
done

if [[ -z "$CLUSTER" ]]; then
    echo "Error: A cluster name is required." >&2
    usage >&2
    exit 1
fi

case "$CLUSTER" in
    mindu|neimeng-2|tianjin) ;;
    *)
        echo "Error: Unknown cluster: ${CLUSTER}" >&2
        usage >&2
        exit 1
        ;;
esac

DEPLOY_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
SOURCE_DIR="${DEPLOY_SCRIPT_DIR}/${CLUSTER}"
REQUESTED_TARGET="${SLURM_BATCHS_TARGET:-${HOME}/soft/slurm-batchs}"
MANAGED_FILES=(README.md env.sh)
declare -A MANAGED_DIRECTORIES=()

if [[ ! -d "$SOURCE_DIR" || -L "$SOURCE_DIR" ]]; then
    die "Cluster source directory does not exist: ${SOURCE_DIR}"
fi

shopt -s nullglob
for SOFTWARE_SOURCE_DIR in "${SOURCE_DIR}"/*; do
    [[ -d "$SOFTWARE_SOURCE_DIR" && ! -L "$SOFTWARE_SOURCE_DIR" ]] || continue
    SOFTWARE_NAME=${SOFTWARE_SOURCE_DIR##*/}
    SOFTWARE_SCRIPTS=("${SOFTWARE_SOURCE_DIR}"/*.sh)
    if ((${#SOFTWARE_SCRIPTS[@]} == 0)); then
        die "Software directory contains no shell scripts: ${SOFTWARE_SOURCE_DIR}"
    fi
    MANAGED_DIRECTORIES["$SOFTWARE_NAME"]=1
    MANAGED_FILES+=("${SOFTWARE_NAME}/README.md")
    for SOFTWARE_SCRIPT in "${SOFTWARE_SCRIPTS[@]}"; do
        [[ -f "$SOFTWARE_SCRIPT" && ! -L "$SOFTWARE_SCRIPT" ]] || die "Software script is not a regular file: ${SOFTWARE_SCRIPT}"
        MANAGED_FILES+=("${SOFTWARE_NAME}/${SOFTWARE_SCRIPT##*/}")
    done
done
shopt -u nullglob

resolve_source() {
    case "$1" in
        README.md)
            SOURCE="${DEPLOY_SCRIPT_DIR}/docs/clusters/${CLUSTER}/index.md"
            ;;
        env.sh)
            SOURCE="${DEPLOY_SCRIPT_DIR}/env.sh"
            ;;
        */README.md)
            SOFTWARE_NAME=${1%%/*}
            SOURCE="${DEPLOY_SCRIPT_DIR}/docs/clusters/${CLUSTER}/${SOFTWARE_NAME}.md"
            ;;
        *)
            SOURCE="${SOURCE_DIR}/$1"
            ;;
    esac
}

for RELATIVE_PATH in "${MANAGED_FILES[@]}"; do
    validate_rel_path "$RELATIVE_PATH"
    resolve_source "$RELATIVE_PATH"
    if [[ ! -f "$SOURCE" || -L "$SOURCE" ]]; then
        die "Managed source file does not exist: ${SOURCE}"
    fi
done

TARGET_DIR=$(canonicalize_target "$REQUESTED_TARGET")
if is_dangerous_target "$TARGET_DIR"; then
    die "Refusing to deploy to a protected directory: ${TARGET_DIR}"
fi
case "$TARGET_DIR" in
    "$DEPLOY_SCRIPT_DIR"|"$DEPLOY_SCRIPT_DIR"/*)
        die "Refusing to deploy into the source repository: ${TARGET_DIR}"
        ;;
esac

if [[ ! -d "$TARGET_DIR" ]]; then
    mkdir -- "$TARGET_DIR"
fi
if [[ -L "$TARGET_DIR" || ! -d "$TARGET_DIR" ]]; then
    die "Deployment target is not a directory: ${TARGET_DIR}"
fi
TARGET_DIR=$(cd -- "$TARGET_DIR" && pwd -P)

MANIFEST_FILE="${TARGET_DIR}/${MANIFEST_NAME}"
BASELINE_FILE="${TARGET_DIR}/${BASELINE_NAME}"

for SOFTWARE_DIR in "${!MANAGED_DIRECTORIES[@]}"; do
    DESTINATION_DIR="${TARGET_DIR}/${SOFTWARE_DIR}"
    if [[ -L "$DESTINATION_DIR" ]]; then
        die "Refusing to deploy through a symbolic-link directory: ${DESTINATION_DIR}"
    fi
done

load_manifest

if [[ -f "$MANIFEST_FILE" && -z "$DEPLOYED_CLUSTER" && -e "$BASELINE_FILE" ]]; then
    die "Deployment manifest has no cluster record while a content baseline exists. Restore the manifest before deploying."
fi

case "$DEPLOYED_CLUSTER" in
    ""|mindu|neimeng-2|tianjin) ;;
    *)
        die "Unknown cluster recorded in deployment manifest: ${DEPLOYED_CLUSTER}"
        ;;
esac

if [[ -n "$DEPLOYED_CLUSTER" && "$DEPLOYED_CLUSTER" != "$CLUSTER" ]]; then
    die "Target is already deployed for cluster '${DEPLOYED_CLUSTER}'; refusing to switch to '${CLUSTER}'."
fi

if load_baseline; then
    if [[ "$ACCEPT_EXISTING" == true ]]; then
        echo "Ignoring --accept-existing because a content baseline is already present." >&2
    fi
    if [[ "$BASELINE_CLUSTER" != "$CLUSTER" ]]; then
        die "Content baseline records cluster '${BASELINE_CLUSTER}'; refusing to deploy '${CLUSTER}'."
    fi
    if [[ -n "$DEPLOYED_CLUSTER" && "$BASELINE_CLUSTER" != "$DEPLOYED_CLUSTER" ]]; then
        die "Content baseline cluster '${BASELINE_CLUSTER}' does not match manifest cluster '${DEPLOYED_CLUSTER}'."
    fi
    collect_drift
    if [[ "$(drift_count)" != "0" ]]; then
        report_drift initial
    fi
else
    audit_unbaselined_tree
fi

for RELATIVE_PATH in "${MANAGED_FILES[@]}"; do
    DESTINATION="${TARGET_DIR}/${RELATIVE_PATH}"
    if [[ -e "$DESTINATION" || -L "$DESTINATION" ]]; then
        if [[ -L "$DESTINATION" || ! -f "$DESTINATION" ]]; then
            die "Refusing to overwrite a non-regular destination: ${DESTINATION}"
        fi
        if [[ -z "${PREVIOUSLY_MANAGED[$RELATIVE_PATH]:-}" ]]; then
            die "Refusing to overwrite an unmanaged user file: ${DESTINATION}"
        fi
    fi
done

STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/slurm-batchs-stage.XXXXXX")
BACKUP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/slurm-batchs-backup.XXXXXX")
MODE_LOG="${BACKUP_DIR}/modes.txt"
CREATED_FILES="${BACKUP_DIR}/created-files.txt"
CREATED_DIRS="${BACKUP_DIR}/created-dirs.txt"
: > "$MODE_LOG"
: > "$CREATED_FILES"
: > "$CREATED_DIRS"

for RELATIVE_PATH in "${MANAGED_FILES[@]}"; do
    resolve_source "$RELATIVE_PATH"
    STAGED_FILE="${STAGING_DIR}/${RELATIVE_PATH}"
    mkdir -p -- "$(dirname -- "$STAGED_FILE")"
    case "$RELATIVE_PATH" in
        *.sh) FILE_MODE=0755 ;;
        *) FILE_MODE=0644 ;;
    esac
    install -m "$FILE_MODE" -- "$SOURCE" "$STAGED_FILE"
    PREVIOUSLY_MANAGED["$RELATIVE_PATH"]=1
done

NEXT_MANIFEST="${STAGING_DIR}/next-manifest"
{
    printf 'cluster=%s\n' "$CLUSTER"
    for RELATIVE_PATH in "${!PREVIOUSLY_MANAGED[@]}"; do
        printf '%s\n' "$RELATIVE_PATH"
    done | LC_ALL=C sort
} > "$NEXT_MANIFEST"

backup_tree

unlock_path "$TARGET_DIR"
unlock_parents_and_file "$MANIFEST_NAME"
if [[ -f "$BASELINE_FILE" && ! -L "$BASELINE_FILE" ]]; then
    unlock_parents_and_file "$BASELINE_NAME"
fi
for RELATIVE_PATH in "${MANAGED_FILES[@]}"; do
    unlock_parents_and_file "$RELATIVE_PATH"
done
failpoint after-unlock

# The manifest is published before file replacement so a partial install stays
# attributed to this deployment if restoration cannot finish.
note_created_file "$MANIFEST_NAME"
install -m 0644 -- "$NEXT_MANIFEST" "$MANIFEST_FILE"

for RELATIVE_PATH in "${MANAGED_FILES[@]}"; do
    STAGED_FILE="${STAGING_DIR}/${RELATIVE_PATH}"
    DESTINATION="${TARGET_DIR}/${RELATIVE_PATH}"
    ensure_dir "$(dirname -- "$DESTINATION")"
    note_created_file "$RELATIVE_PATH"
    case "$RELATIVE_PATH" in
        *.sh) FILE_MODE=0755 ;;
        *) FILE_MODE=0644 ;;
    esac
    install -m "$FILE_MODE" -- "$STAGED_FILE" "$DESTINATION"
    echo "Deployed: ${DESTINATION}"
done

failpoint before-baseline
write_baseline
apply_readonly

if ! load_baseline; then
    die "Content baseline is missing after installation."
fi
collect_drift
if [[ "$(drift_count)" != "0" ]]; then
    report_drift final
fi
PROTECTION_DIRTY=false

echo "Deployment complete: ${CLUSTER} -> ${TARGET_DIR}"
echo "Install tree is read-only: directories and scripts are mode 555; other files are mode 444."
