#!/usr/bin/env bash

# Non-root regression coverage for read-only installs and content baselines.
# Root can bypass mode bits, so a passing run as root would not prove that
# the install tree rejects writes.

set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
    echo "Refusing to run as root because permission bits would not be enforced." >&2
    exit 1
fi

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
DEPLOY="${ROOT}/deploy.sh"
WORKDIR=$(mktemp -d)
chmod 700 "$WORKDIR"
declare -a CLEAN_DIRS=("$WORKDIR")

cleanup() {
    local status=$?
    local dir
    for dir in "${CLEAN_DIRS[@]}"; do
        [[ -n "$dir" && -d "$dir" && ! -L "$dir" ]] || continue
        find -P "$dir" -type l -exec rm -f -- {} + 2>/dev/null || true
        chmod -R u+w -- "$dir" 2>/dev/null || true
        rm -rf -- "$dir"
    done
    exit "$status"
}
trap cleanup EXIT

pass() {
    printf 'PASS %s\n' "$1"
}

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

track() {
    CLEAN_DIRS+=("$1")
}

run_deploy() {
    local target=$1
    shift
    DEPLOY_STATUS=0
    DEPLOY_OUTPUT=""
    set +e
    DEPLOY_OUTPUT=$(SLURM_BATCHS_TARGET="$target" "$DEPLOY" "$@" 2>&1)
    DEPLOY_STATUS=$?
    set -e
}

assert_readonly_tree() {
    local root=$1
    local path mode
    [[ -d "$root" && ! -L "$root" ]] || fail "missing install tree $root"
    [[ "$(stat -c '%a' -- "$root")" == "555" ]] || fail "root mode of $root"
    [[ ! -w "$root" ]] || fail "root is writable: $root"
    while IFS= read -r -d '' path; do
        if [[ -L "$path" ]]; then
            fail "unexpected symlink in install tree: $path"
        elif [[ -d "$path" ]]; then
            [[ "$(stat -c '%a' -- "$path")" == "555" ]] || fail "directory mode $path"
            [[ ! -w "$path" ]] || fail "directory writable $path"
        elif [[ -f "$path" ]]; then
            mode=$(stat -c '%a' -- "$path")
            if [[ "${path##*/}" == *.sh ]]; then
                [[ "$mode" == "555" && -x "$path" && ! -w "$path" ]] || fail "script mode $path ($mode)"
            else
                [[ "$mode" == "444" && ! -x "$path" && ! -w "$path" ]] || fail "file mode $path ($mode)"
            fi
        else
            fail "unsupported install path: $path"
        fi
    done < <(find -P "$root" -mindepth 1 -print0)
}

mode_list() {
    local root=$1
    local path
    (
        cd -- "$root"
        find -P . ! -type l -print0 | sort -z | while IFS= read -r -d '' path; do
            printf '%s %s\n' "$(stat -c '%a' -- "$path")" "$path"
        done
    )
}

name_list() {
    local root=$1
    (
        cd -- "$root"
        find -P . -print0 | sort -z | while IFS= read -r -d '' path; do
            printf '%s\n' "$path"
        done
    )
}

snapshot_tree() {
    local src=$1 dest=$2
    mkdir -p -- "$dest"
    cp -a -- "$src"/. "$dest"/
}

deploy_fresh() {
    local cluster=$1
    local target
    target=$(mktemp -d "${WORKDIR}/install.XXXXXX")
    SLURM_BATCHS_TARGET="$target" "$DEPLOY" "$cluster" >/dev/null
    printf '%s\n' "$target"
}

permission_probe=$(mktemp "${WORKDIR}/probe.XXXXXX")
chmod 444 -- "$permission_probe"
if (echo probe >> "$permission_probe") 2>/dev/null; then
    fail "mode 444 is writable; permission tests would be false positives"
fi

temp_before=$(find /tmp -maxdepth 1 \( -name 'slurm-batchs-stage.*' -o -name 'slurm-batchs-backup.*' \) -printf '%f\n' | LC_ALL=C sort)

# Static review: submission scripts must keep job files outside the install tree.
while IFS= read -r line; do
    [[ "$line" == *'${PWD}'* ]] || fail "temporary script is not under PWD: $line"
done < <(grep -R -n --include='*.sh' -E '^TMP_SCRIPT=' mindu neimeng-2 tianjin)
while IFS= read -r line; do
    [[ "$line" == *'INPUT_DIR'* || "$line" == *'TASK_DIR'* ]] || fail "Batch.log is not in the job directory: $line"
done < <(grep -R -n --include='*.sh' -E '^BATCH_LOG=' mindu neimeng-2 tianjin)
pass "runtime writes stay outside the install tree"

# Empty-target installs for every cluster, including a second read-only deploy.
for cluster in mindu neimeng-2 tianjin; do
    target=$(deploy_fresh "$cluster")
    assert_readonly_tree "$target"
    grep -Fxq "cluster=${cluster}" "$target/.slurm-batchs-managed"
    grep -Fxq "metadata-exception=.slurm-batchs-baseline" "$target/.slurm-batchs-baseline"
    if awk -F '\t' 'NR>3 && $4==".slurm-batchs-baseline"' "$target/.slurm-batchs-baseline" | grep -q .; then
        fail "baseline includes its own content record"
    fi
    SLURM_BATCHS_TARGET="$target" "$DEPLOY" "$cluster" >/dev/null
    assert_readonly_tree "$target"
    if (echo drift >> "$target/README.md") 2>/dev/null; then
        fail "second deploy left README writable"
    fi
    pass "fresh and repeat deploy for ${cluster}"
done

# Paths with spaces and a relative target.
space_parent="${WORKDIR}/space dir"
mkdir -p -- "$space_parent"
(
    cd -- "$space_parent"
    SLURM_BATCHS_TARGET="./install here" "$DEPLOY" mindu >/dev/null
)
space_target="${space_parent}/install here"
assert_readonly_tree "$space_target"
SLURM_BATCHS_TARGET="$space_target" "$DEPLOY" mindu >/dev/null
assert_readonly_tree "$space_target"
pass "paths with spaces"

# Help and invalid arguments do not create a target.
help_target="${WORKDIR}/help-does-not-create"
run_deploy "$help_target" -h
[[ "$DEPLOY_STATUS" -eq 0 ]] || fail "help failed"
[[ ! -e "$help_target" ]] || fail "help created a target"
run_deploy "$help_target"
[[ "$DEPLOY_STATUS" -ne 0 ]] || fail "missing cluster was accepted"
[[ ! -e "$help_target" ]] || fail "invalid invocation created a target"
run_deploy "$help_target" nosuch
[[ "$DEPLOY_STATUS" -ne 0 ]] || fail "unknown cluster was accepted"
pass "argument checks"

# Protected targets are rejected before any chmod.
home_mode=$(stat -c '%a' -- "$HOME")
home_baseline_before=0
[[ -e "${HOME}/.slurm-batchs-baseline" ]] && home_baseline_before=1
run_deploy "$HOME" mindu
[[ "$DEPLOY_STATUS" -ne 0 ]] || fail "home target was accepted"
[[ "$DEPLOY_OUTPUT" == *"Refusing"* ]] || fail "home target error did not refuse: $DEPLOY_OUTPUT"
[[ "$(stat -c '%a' -- "$HOME")" == "$home_mode" ]] || fail "home permissions changed"
if [[ "$home_baseline_before" -eq 0 && -e "${HOME}/.slurm-batchs-baseline" ]]; then
    fail "deploy created a baseline in the home directory"
fi
run_deploy / mindu
[[ "$DEPLOY_STATUS" -ne 0 && "$DEPLOY_OUTPUT" == *"Refusing"* ]] || fail "root target was accepted: $DEPLOY_OUTPUT"
run_deploy /tmp mindu
[[ "$DEPLOY_STATUS" -ne 0 && "$DEPLOY_OUTPUT" == *"Refusing"* ]] || fail "/tmp target was accepted: $DEPLOY_OUTPUT"
[[ ! -e /tmp/.slurm-batchs-managed ]] || fail "deploy wrote metadata into /tmp"
run_deploy "$ROOT" mindu
[[ "$DEPLOY_STATUS" -ne 0 && "$DEPLOY_OUTPUT" == *"Refusing"* ]] || fail "source repository target was accepted"
[[ -w "$DEPLOY" ]] || fail "deploy.sh permissions changed while refusing the source tree"
pass "protected targets"

# Non-empty unrecognized directory.
foreign="${WORKDIR}/foreign"
mkdir -p -- "$foreign"
printf 'keep\n' > "$foreign/notes.txt"
foreign_mode=$(stat -c '%a' -- "$foreign/notes.txt")
run_deploy "$foreign" mindu
[[ "$DEPLOY_STATUS" -ne 0 ]] || fail "non-empty unrecognized directory was accepted"
[[ "$(cat "$foreign/notes.txt")" == "keep" ]] || fail "user file changed"
[[ ! -e "$foreign/.slurm-batchs-managed" && ! -e "$foreign/.slurm-batchs-baseline" ]] || fail "metadata written into unrecognized directory"
[[ "$(stat -c '%a' -- "$foreign/notes.txt")" == "$foreign_mode" ]] || fail "user file mode changed"
run_deploy "$foreign" --accept-existing mindu
[[ "$DEPLOY_STATUS" -ne 0 ]] || fail "--accept-existing adopted a directory without a manifest"
[[ "$(cat "$foreign/notes.txt")" == "keep" ]] || fail "accept-existing changed a user file"
pass "unrecognized directory stays untouched"

# Existing manifest without a baseline requires confirmation and rejects extras.
legacy=$(deploy_fresh mindu)
chmod u+w -- "$legacy" "$legacy/.slurm-batchs-managed" "$legacy/.slurm-batchs-baseline"
rm -f -- "$legacy/.slurm-batchs-baseline"
grep -v '^cluster=' "$legacy/.slurm-batchs-managed" > "$legacy/manifest.tmp"
mv -f -- "$legacy/manifest.tmp" "$legacy/.slurm-batchs-managed"
chmod 644 -- "$legacy/.slurm-batchs-managed"
find -P "$legacy" -type d -exec chmod 755 {} +
find -P "$legacy" -type f -exec chmod 644 {} +
sample_hash=$(sha256sum -- "$legacy/env.sh" | awk '{print $1}')
run_deploy "$legacy" mindu
[[ "$DEPLOY_STATUS" -ne 0 ]] || fail "legacy tree was updated without confirmation"
[[ "$DEPLOY_OUTPUT" == *"--adopt-legacy"* && "$DEPLOY_OUTPUT" == *"--accept-existing"* ]] || fail "legacy confirmation hint missing: $DEPLOY_OUTPUT"
[[ ! -e "$legacy/.slurm-batchs-baseline" ]] || fail "baseline created without confirmation"
[[ "$(sha256sum -- "$legacy/env.sh" | awk '{print $1}')" == "$sample_hash" ]] || fail "legacy refusal rewrote env.sh"
[[ "$(stat -c '%a' -- "$legacy/env.sh")" == "644" ]] || fail "legacy refusal changed file mode"

printf 'note\n' > "$legacy/USER_NOTE.txt"
mkdir -p -- "$legacy/.hidden"
printf 'secret\n' > "$legacy/.hidden/cache"
run_deploy "$legacy" --adopt-legacy --accept-existing mindu
[[ "$DEPLOY_STATUS" -ne 0 ]] || fail "accept-existing absorbed extra files"
[[ "$DEPLOY_OUTPUT" == *"USER_NOTE.txt"* && "$DEPLOY_OUTPUT" == *".hidden/cache"* ]] || fail "extra paths were not listed: $DEPLOY_OUTPUT"
[[ "$(cat "$legacy/USER_NOTE.txt")" == "note" && "$(cat "$legacy/.hidden/cache")" == "secret" ]] || fail "extra content changed"
[[ "$(stat -c '%a' -- "$legacy/env.sh")" == "644" ]] || fail "failed adoption changed modes"
[[ ! -e "$legacy/.slurm-batchs-baseline" ]] || fail "baseline created while extras remained"

rm -f -- "$legacy/USER_NOTE.txt"
rm -rf -- "$legacy/.hidden"
run_deploy "$legacy" --accept-existing mindu
[[ "$DEPLOY_STATUS" -ne 0 ]] || fail "legacy manifest skipped --adopt-legacy"
run_deploy "$legacy" --adopt-legacy --accept-existing mindu
[[ "$DEPLOY_STATUS" -eq 0 ]] || fail "legacy adoption failed: $DEPLOY_OUTPUT"
assert_readonly_tree "$legacy"
grep -Fxq "cluster=mindu" "$legacy/.slurm-batchs-managed"
pass "existing install migration"

# Drift stops before any chmod and leaves the tree unchanged.
drift=$(deploy_fresh mindu)
snapshot_tree "$drift" "${WORKDIR}/drift-snap"
mode_list "$drift" > "${WORKDIR}/drift-modes"

chmod u+w -- "$drift"
printf 'hidden\n' > "$drift/.hidden"
mkdir -p -- "$drift/nested/sub"
printf 'child\n' > "$drift/nested/sub/file.txt"
chmod 555 -- "$drift"
run_deploy "$drift" mindu
[[ "$DEPLOY_STATUS" -ne 0 ]] || fail "added files did not stop deployment"
[[ "$DEPLOY_OUTPUT" == *".hidden"* && "$DEPLOY_OUTPUT" == *"nested/sub/file.txt"* ]] || fail "added paths missing from report: $DEPLOY_OUTPUT"
[[ "$(cat "$drift/.hidden")" == "hidden" && "$(cat "$drift/nested/sub/file.txt")" == "child" ]] || fail "added content was modified"
diff -rq --exclude '.hidden' --exclude 'nested' "${WORKDIR}/drift-snap" "$drift" >/dev/null || fail "managed content changed while reporting additions"
[[ "$(mode_list "$drift" | grep -v -e ' ./.hidden$' -e ' ./nested' )" == "$(cat "${WORKDIR}/drift-modes")" ]] || fail "modes changed while reporting additions"

chmod u+w -- "$drift" "$drift/nested" "$drift/nested/sub"
rm -rf -- "$drift/.hidden" "$drift/nested"
chmod 555 -- "$drift"
chmod u+w -- "$drift/gaussian/myg16.sh"
printf '\n# local edit\n' >> "$drift/gaussian/myg16.sh"
chmod 555 -- "$drift/gaussian/myg16.sh"
cp -a -- "$drift/gaussian/myg16.sh" "${WORKDIR}/edited-myg16.sh"
run_deploy "$drift" --accept-existing mindu
[[ "$DEPLOY_STATUS" -ne 0 ]] || fail "--accept-existing bypassed a baseline mismatch"
[[ "$DEPLOY_OUTPUT" == *"gaussian/myg16.sh"* ]] || fail "modified path was not listed"
cmp -s "${WORKDIR}/edited-myg16.sh" "$drift/gaussian/myg16.sh" || fail "modified script was overwritten"
[[ "$(stat -c '%a' -- "$drift/gaussian/myg16.sh")" == "555" ]] || fail "modified script mode changed"

chmod u+w -- "$drift/gaussian" "$drift/gaussian/myg16.sh"
# Restore the deployed bytes from the snapshot and continue with other drift cases.
cp -a -- "${WORKDIR}/drift-snap/gaussian/myg16.sh" "$drift/gaussian/myg16.sh"
chmod 555 -- "$drift/gaussian" "$drift/gaussian/myg16.sh"
readme_hash=$(sha256sum -- "$drift/README.md" | awk '{print $1}')
chmod 644 -- "$drift/README.md"
run_deploy "$drift" mindu
[[ "$DEPLOY_STATUS" -ne 0 && "$DEPLOY_OUTPUT" == *"README.md"* && "$DEPLOY_OUTPUT" == *"Permissions:"* ]] || fail "permission drift was not reported: $DEPLOY_OUTPUT"
[[ "$(sha256sum -- "$drift/README.md" | awk '{print $1}')" == "$readme_hash" ]] || fail "permission drift rewrote README"
[[ "$(stat -c '%a' -- "$drift/README.md")" == "644" ]] || fail "permission drift was auto-corrected"
chmod 444 -- "$drift/README.md"

chmod u+w -- "$drift/gaussian"
rm -f -- "$drift/gaussian/myg16.sh"
chmod 555 -- "$drift/gaussian"
run_deploy "$drift" mindu
[[ "$DEPLOY_STATUS" -ne 0 && "$DEPLOY_OUTPUT" == *"Missing:"* && "$DEPLOY_OUTPUT" == *"gaussian/myg16.sh"* ]] || fail "missing file was not reported: $DEPLOY_OUTPUT"
[[ ! -e "$drift/gaussian/myg16.sh" ]] || fail "missing file was recreated"
[[ "$(sha256sum -- "$drift/README.md" | awk '{print $1}')" == "$readme_hash" ]] || fail "missing-file refusal changed README"
chmod u+w -- "$drift/gaussian"
cp -a -- "${WORKDIR}/drift-snap/gaussian/myg16.sh" "$drift/gaussian/myg16.sh"
chmod 555 -- "$drift/gaussian/myg16.sh" "$drift/gaussian"
pass "drift stops without changing recorded content"

# Symbolic links are reported and are not chmod targets.
outside=$(mktemp -d "${WORKDIR}/outside.XXXXXX")
printf 'secret\n' > "$outside/secret"
chmod 600 -- "$outside/secret"
mkdir -p -- "$outside/dir"
printf 'inside\n' > "$outside/dir/file"
chmod 600 -- "$outside/dir/file"
chmod 700 -- "$outside/dir"
link_target=$(deploy_fresh mindu)
chmod u+w -- "$link_target" "$link_target/gaussian"
ln -s -- "$outside/secret" "$link_target/gaussian/linked-secret"
ln -s -- "$outside/dir" "$link_target/linked-dir"
chmod 555 -- "$link_target" "$link_target/gaussian"
run_deploy "$link_target" mindu
[[ "$DEPLOY_STATUS" -ne 0 ]] || fail "symlink did not stop deployment"
[[ "$DEPLOY_OUTPUT" == *"linked-secret"* && "$DEPLOY_OUTPUT" == *"linked-dir"* ]] || fail "symlink paths were not listed: $DEPLOY_OUTPUT"
[[ "$(stat -c '%a' -- "$outside/secret")" == "600" ]] || fail "chmod followed a file symlink"
[[ "$(stat -c '%a' -- "$outside/dir")" == "700" ]] || fail "chmod followed a directory symlink"
[[ "$(stat -c '%a' -- "$outside/dir/file")" == "600" ]] || fail "chmod entered a symlinked directory"
[[ "$(stat -c '%a' -- "$link_target/README.md")" == "444" ]] || fail "symlink refusal changed README mode"
pass "symbolic-link boundary"

real_dir=$(mktemp -d "${WORKDIR}/real.XXXXXX")
printf 'real\n' > "$real_dir/keep.txt"
link_path="${WORKDIR}/link-target"
ln -s -- "$real_dir" "$link_path"
run_deploy "$link_path" mindu
[[ "$DEPLOY_STATUS" -ne 0 && "$DEPLOY_OUTPUT" == *"symbolic-link"* ]] || fail "symlink target was accepted: $DEPLOY_OUTPUT"
[[ "$(cat "$real_dir/keep.txt")" == "real" ]] || fail "symlink target contents changed"
[[ ! -e "$real_dir/.slurm-batchs-managed" ]] || fail "deploy wrote through a symlink target"
pass "symlink deployment target"

# Cluster switch is still refused.
switch_target=$(deploy_fresh mindu)
run_deploy "$switch_target" tianjin
[[ "$DEPLOY_STATUS" -ne 0 && "$DEPLOY_OUTPUT" == *"refusing to switch"* ]] || fail "cluster switch was accepted: $DEPLOY_OUTPUT"
assert_readonly_tree "$switch_target"
grep -Fxq "cluster=mindu" "$switch_target/.slurm-batchs-managed"
pass "cluster switch refusal"

# Failed update restores content and the previous read-only modes.
rollback=$(deploy_fresh mindu)
snapshot_tree "$rollback" "${WORKDIR}/rollback-snap"
mode_list "$rollback" > "${WORKDIR}/rollback-modes"
copy="${WORKDIR}/repo-copy"
mkdir -p -- "$copy"
cp -a -- "$ROOT"/. "$copy"/
printf '\nreadonly-marker\n' >> "$copy/docs/clusters/mindu/index.md"
mkdir -p -- "$copy/mindu/newsoft"
printf '#!/usr/bin/env bash\necho extra\n' > "$copy/mindu/newsoft/hello.sh"
printf '# newsoft\n' > "$copy/docs/clusters/mindu/newsoft.md"
set +e
DEPLOY_OUTPUT=$(SLURM_BATCHS_TARGET="$rollback" SLURM_BATCHS_INJECT_FAILURE=before-baseline "$copy/deploy.sh" mindu 2>&1)
DEPLOY_STATUS=$?
set -e
[[ "$DEPLOY_STATUS" -ne 0 && "$DEPLOY_OUTPUT" == *"before-baseline"* ]] || fail "injected failure did not stop deploy: $DEPLOY_OUTPUT"
diff -rq "${WORKDIR}/rollback-snap" "$rollback" >/dev/null || fail "failed update left content changes"
[[ "$(mode_list "$rollback")" == "$(cat "${WORKDIR}/rollback-modes")" ]] || fail "failed update left permission changes"
[[ ! -e "$rollback/newsoft" ]] || fail "failed update left a new software directory"
[[ ! -w "$rollback/README.md" ]] || fail "failed update left README writable"
SLURM_BATCHS_TARGET="$rollback" "$DEPLOY" mindu >/dev/null
assert_readonly_tree "$rollback"
pass "failed update restores protection"

clean_fail=$(deploy_fresh mindu)
before_hash=$(sha256sum -- "$clean_fail/README.md" | awk '{print $1}')
set +e
DEPLOY_OUTPUT=$(SLURM_BATCHS_TARGET="$clean_fail" SLURM_BATCHS_INJECT_FAILURE=after-unlock "$DEPLOY" mindu 2>&1)
DEPLOY_STATUS=$?
set -e
[[ "$DEPLOY_STATUS" -ne 0 ]] || fail "after-unlock injection continued"
[[ "$(sha256sum -- "$clean_fail/README.md" | awk '{print $1}')" == "$before_hash" ]] || fail "after-unlock injection changed README"
assert_readonly_tree "$clean_fail"
pass "unlock failure restores read-only modes"

first_fail="${WORKDIR}/first-fail"
sibling="${WORKDIR}/sibling-mkdir"
mkdir -- "$sibling"
expected_mode=$(stat -c '%a' -- "$sibling")
set +e
DEPLOY_OUTPUT=$(SLURM_BATCHS_TARGET="$first_fail" SLURM_BATCHS_INJECT_FAILURE=before-baseline "$DEPLOY" mindu 2>&1)
DEPLOY_STATUS=$?
set -e
[[ "$DEPLOY_STATUS" -ne 0 ]] || fail "first-install injection continued"
[[ -d "$first_fail" ]] || fail "first-install target missing"
[[ "$(stat -c '%a' -- "$first_fail")" == "$expected_mode" ]] || fail "first-install directory mode was not restored"
if find -P "$first_fail" -mindepth 1 -print -quit | grep -q .; then
    fail "first-install failure left files behind"
fi
[[ ! -e "$first_fail/.slurm-batchs-baseline" ]] || fail "first-install failure left a baseline"
SLURM_BATCHS_TARGET="$first_fail" "$DEPLOY" mindu >/dev/null
assert_readonly_tree "$first_fail"
pass "first-install failure rolls back"

# Submission commands write job files only in the calculation directory.
runtime=$(deploy_fresh mindu)
job=$(mktemp -d "${WORKDIR}/job.XXXXXX")
printf 'water\n' > "$job/water.gjf"
printf 'water\n' > "$job/water.in"
printf 'acell 3*10.26\n' > "$job/water.abi"
mock=$(mktemp -d "${WORKDIR}/mock.XXXXXX")
cat > "$mock/sbatch" <<'EOF'
#!/bin/sh
echo 424242
EOF
chmod 755 -- "$mock/sbatch"
names_before=$(name_list "$runtime")
(
    cd -- "$job"
    PATH="${mock}:${PATH}" "$runtime/gaussian/myg16.sh" water.gjf
    PATH="${mock}:${PATH}" "$runtime/qe/mypw.sh" water.in
    PATH="${mock}:${PATH}" "$runtime/abinit/myabinit.sh" water.abi
) >"${WORKDIR}/submit.out"
[[ -f "$job/myg16-tmp" && -f "$job/mypw-tmp" && -f "$job/myabinit-tmp" && -f "$job/Batch.log" ]] || fail "job files were not written in the calculation directory"
grep -q 'job_id=424242' "$job/Batch.log" || fail "Batch.log missing job id"
[[ "$(name_list "$runtime")" == "$names_before" ]] || fail "submission wrote into the install tree"
set +e
(cd -- "$runtime" && "$runtime/gaussian/myg16.sh" "$job/water.gjf") >"${WORKDIR}/cwd-install.out" 2>&1
cwd_status=$?
set -e
[[ "$cwd_status" -ne 0 ]] || fail "submission from the install directory succeeded"
[[ "$(name_list "$runtime")" == "$names_before" ]] || fail "install directory gained files when used as cwd"
SLURM_BATCHS_HOME="$runtime" bash -c 'source "$1"; command -v myg16.sh >/dev/null' _ "$runtime/env.sh"
"$runtime/env.sh" -h >/dev/null
pass "runtime submission and env.sh"

temp_after=$(find /tmp -maxdepth 1 \( -name 'slurm-batchs-stage.*' -o -name 'slurm-batchs-backup.*' \) -printf '%f\n' | LC_ALL=C sort)
[[ "$temp_before" == "$temp_after" ]] || fail "deploy left staging or backup directories in /tmp"

pass "all deploy protection checks"
