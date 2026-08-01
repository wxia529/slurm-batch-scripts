#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  deploy.sh <cluster>
  deploy.sh --adopt-legacy <cluster>

Cluster:
  mindu
  para-amd
  para-e5

Target:
  ~/soft/slurm-batchs

The deployment only updates files managed by this project. It never deletes or
modifies calculation files, Batch.log, shell configuration, or unrelated files.
EOF
}

ADOPT_LEGACY=false
if (( $# == 1 )); then
    CLUSTER=$1
elif (( $# == 2 )) && [[ $1 == --adopt-legacy ]]; then
    ADOPT_LEGACY=true
    CLUSTER=$2
else
    echo "Error: A cluster name and, optionally, --adopt-legacy are required." >&2
    usage
    exit 1
fi

case "$CLUSTER" in
    mindu|para-amd|para-e5) ;;
    *)
        echo "Error: Unknown cluster: $CLUSTER" >&2
        usage
        exit 1
        ;;
esac

DEPLOY_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
SOURCE_DIR="${DEPLOY_SCRIPT_DIR}/${CLUSTER}"
TARGET_DIR="${SLURM_BATCHS_TARGET:-${HOME}/soft/slurm-batchs}"
MANIFEST_FILE="${TARGET_DIR}/.slurm-batchs-managed"

MANAGED_FILES=(README.md env.sh)
declare -A MANAGED_DIRECTORIES=()

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: Cluster source directory does not exist: $SOURCE_DIR" >&2
    exit 1
fi

shopt -s nullglob
for SOFTWARE_SOURCE_DIR in "${SOURCE_DIR}"/*; do
    [[ -d "$SOFTWARE_SOURCE_DIR" && ! -L "$SOFTWARE_SOURCE_DIR" ]] || continue
    SOFTWARE_NAME=${SOFTWARE_SOURCE_DIR##*/}
    SOFTWARE_SCRIPTS=("${SOFTWARE_SOURCE_DIR}"/*.sh)
    if (( ${#SOFTWARE_SCRIPTS[@]} == 0 )); then
        echo "Error: Software directory contains no shell scripts: $SOFTWARE_SOURCE_DIR" >&2
        exit 1
    fi

    MANAGED_DIRECTORIES["$SOFTWARE_NAME"]=1
    MANAGED_FILES+=("${SOFTWARE_NAME}/README.md")
    for SOFTWARE_SCRIPT in "${SOFTWARE_SCRIPTS[@]}"; do
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
    resolve_source "$RELATIVE_PATH"
    if [[ ! -f "$SOURCE" ]]; then
        echo "Error: Managed source file does not exist: $SOURCE" >&2
        exit 1
    fi
done

if [[ -L "$TARGET_DIR" ]]; then
    echo "Error: Refusing to deploy through a symbolic-link target: $TARGET_DIR" >&2
    exit 1
fi

mkdir -p -- "$TARGET_DIR"

for SOFTWARE_DIR in "${!MANAGED_DIRECTORIES[@]}"; do
    DESTINATION_DIR="${TARGET_DIR}/${SOFTWARE_DIR}"
    if [[ -L "$DESTINATION_DIR" ]]; then
        echo "Error: Refusing to deploy through a symbolic-link directory: $DESTINATION_DIR" >&2
        exit 1
    fi
done

declare -A PREVIOUSLY_MANAGED=()
DEPLOYED_CLUSTER=""
if [[ -L "$MANIFEST_FILE" ]]; then
    echo "Error: Deployment manifest must not be a symbolic link: $MANIFEST_FILE" >&2
    exit 1
elif [[ -f "$MANIFEST_FILE" ]]; then
    while IFS= read -r RELATIVE_PATH; do
        [[ -n "$RELATIVE_PATH" ]] || continue
        case "$RELATIVE_PATH" in
            cluster=*)
                MANIFEST_CLUSTER=${RELATIVE_PATH#cluster=}
                if [[ -n "$DEPLOYED_CLUSTER" && "$DEPLOYED_CLUSTER" != "$MANIFEST_CLUSTER" ]]; then
                    echo "Error: Deployment manifest contains conflicting cluster records." >&2
                    exit 1
                fi
                DEPLOYED_CLUSTER=$MANIFEST_CLUSTER
                ;;
            *)
                PREVIOUSLY_MANAGED["$RELATIVE_PATH"]=1
                ;;
        esac
    done < "$MANIFEST_FILE"
elif [[ -e "$MANIFEST_FILE" ]]; then
    echo "Error: Deployment manifest is not a regular file: $MANIFEST_FILE" >&2
    exit 1
fi

# A legacy manifest cannot identify its cluster reliably because software sets
# evolve independently. Require an explicit operator decision instead of
# inferring the cluster from a particular software path.
if [[ -f "$MANIFEST_FILE" && -z "$DEPLOYED_CLUSTER" ]]; then
    if [[ "$ADOPT_LEGACY" != true ]]; then
        echo "Error: Legacy deployment manifest does not record a cluster." >&2
        echo "Re-run with --adopt-legacy after confirming this target belongs to '$CLUSTER'." >&2
        exit 1
    fi
    DEPLOYED_CLUSTER=$CLUSTER
fi

case "$DEPLOYED_CLUSTER" in
    ""|mindu|para-amd|para-e5) ;;
    *)
        echo "Error: Unknown cluster recorded in deployment manifest: $DEPLOYED_CLUSTER" >&2
        exit 1
        ;;
esac

if [[ -n "$DEPLOYED_CLUSTER" && "$DEPLOYED_CLUSTER" != "$CLUSTER" ]]; then
    echo "Error: Target is already deployed for cluster '$DEPLOYED_CLUSTER'; refusing to switch to '$CLUSTER'." >&2
    exit 1
fi

# Refuse to overwrite an existing destination unless a previous deployment
# explicitly recorded that path as managed by this project.
for RELATIVE_PATH in "${MANAGED_FILES[@]}"; do
    DESTINATION="${TARGET_DIR}/${RELATIVE_PATH}"
    if [[ -e "$DESTINATION" || -L "$DESTINATION" ]]; then
        if [[ -L "$DESTINATION" || ! -f "$DESTINATION" ]]; then
            echo "Error: Refusing to overwrite a non-regular destination: $DESTINATION" >&2
            exit 1
        fi
        if [[ -z "${PREVIOUSLY_MANAGED[$RELATIVE_PATH]:-}" ]]; then
            echo "Error: Refusing to overwrite an unmanaged user file: $DESTINATION" >&2
            exit 1
        fi
    fi
done

STAGING_DIR=$(mktemp -d "${TARGET_DIR}/.slurm-batchs-stage.XXXXXX")
cleanup_staging() {
    rm -rf -- "$STAGING_DIR"
}
trap cleanup_staging EXIT

# Prepare every managed file before changing the deployed copies.
for RELATIVE_PATH in "${MANAGED_FILES[@]}"; do
    resolve_source "$RELATIVE_PATH"
    STAGED_FILE="${STAGING_DIR}/${RELATIVE_PATH}"
    mkdir -p -- "$(dirname -- "$STAGED_FILE")"

    case "$RELATIVE_PATH" in
        *.sh) FILE_MODE=0755 ;;
        *)    FILE_MODE=0644 ;;
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
chmod 0644 "$NEXT_MANIFEST"

# Record ownership before installation. If installation is interrupted, the
# next deployment can safely resume instead of treating partial files as user files.
mv -f -- "$NEXT_MANIFEST" "$MANIFEST_FILE"

for RELATIVE_PATH in "${MANAGED_FILES[@]}"; do
    STAGED_FILE="${STAGING_DIR}/${RELATIVE_PATH}"
    DESTINATION="${TARGET_DIR}/${RELATIVE_PATH}"
    mkdir -p -- "$(dirname -- "$DESTINATION")"

    case "$RELATIVE_PATH" in
        *.sh) FILE_MODE=0755 ;;
        *)    FILE_MODE=0644 ;;
    esac

    install -m "$FILE_MODE" -- "$STAGED_FILE" "$DESTINATION"
    echo "Deployed: $DESTINATION"
done

cleanup_staging
trap - EXIT

echo "Deployment complete: $CLUSTER -> $TARGET_DIR"
