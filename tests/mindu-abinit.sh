#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
SCRIPT="${ROOT}/mindu/abinit/myabinit.sh"
WORKDIR=$(mktemp -d)

cleanup() {
    local status=$?
    rm -rf -- "$WORKDIR"
    exit "$status"
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

expect_failure() {
    if "$@" >"${WORKDIR}/failure.out" 2>&1; then
        fail "command unexpectedly succeeded: $*"
    fi
}

CALC_DIR="${WORKDIR}/calc dir"
SUCCESS_BIN="${WORKDIR}/success-bin"
FAIL_BIN="${WORKDIR}/fail-bin"
mkdir -p -- "$CALC_DIR" "$SUCCESS_BIN" "$FAIL_BIN"
printf 'acell 3*10.26\n' > "${CALC_DIR}/silicon.abi"
printf 'acell 3*10.26\n' > "${CALC_DIR}/bad name.abi"

cat > "${SUCCESS_BIN}/sbatch" <<'EOF'
#!/usr/bin/env bash
printf '%s;mock-cluster\n' "${MOCK_JOB_ID:-424242}"
EOF
chmod 755 -- "${SUCCESS_BIN}/sbatch"

cat > "${FAIL_BIN}/sbatch" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod 755 -- "${FAIL_BIN}/sbatch"

"$SCRIPT" --help >"${WORKDIR}/help.out"
[[ ! -e "${WORKDIR}/myabinit-tmp" ]] || fail "help created a temporary script"
expect_failure "$SCRIPT"
expect_failure "$SCRIPT" "${CALC_DIR}/missing.abi"
expect_failure "$SCRIPT" "${CALC_DIR}/bad name.abi"
expect_failure "$SCRIPT" "${CALC_DIR}/silicon.abi" unknown
expect_failure "$SCRIPT" "${CALC_DIR}/silicon.abi" small 0
expect_failure "$SCRIPT" "${CALC_DIR}/silicon.abi" small 1 extra

(
    cd -- "$WORKDIR"
    PATH="${SUCCESS_BIN}:${PATH}" "$SCRIPT" "${CALC_DIR}/silicon.abi" h 2
) >"${WORKDIR}/success.out"

TMP_SCRIPT="${WORKDIR}/myabinit-tmp"
[[ -x "$TMP_SCRIPT" ]] || fail "generated Slurm script is missing or not executable"
grep -Fqx '#SBATCH --nodes=2' "$TMP_SCRIPT" || fail "node count is missing"
grep -Fqx '#SBATCH --ntasks=64' "$TMP_SCRIPT" || fail "MPI process count is missing"
grep -Fqx '#SBATCH --ntasks-per-node=32' "$TMP_SCRIPT" || fail "per-node process count is missing"
grep -Fqx '#SBATCH --partition=highio' "$TMP_SCRIPT" || fail "queue abbreviation was not expanded"
grep -Fq 'source /home/liqh/soft/ABINIT/env-10.8.3-oneapi2022-avx512.sh' "$TMP_SCRIPT" || fail "ABINIT environment is missing"
grep -Fq 'mpirun -n 64 abinit silicon.abi > silicon.log 2> abinit.err' "$TMP_SCRIPT" || fail "ABINIT launch command is incorrect"
grep -Fq 'job_id=424242' "${CALC_DIR}/Batch.log" || fail "Batch.log is missing the parsed Job ID"
grep -Fq 'partition=highio | nodes=2 | processes=64' "${CALC_DIR}/Batch.log" || fail "Batch.log resources are incorrect"

LINES_BEFORE=$(wc -l < "${CALC_DIR}/Batch.log")
if (
    cd -- "$WORKDIR"
    PATH="${FAIL_BIN}:${PATH}" "$SCRIPT" "${CALC_DIR}/silicon.abi"
) >"${WORKDIR}/submit-failure.out" 2>&1; then
    fail "failed sbatch command unexpectedly succeeded"
fi
[[ "$(wc -l < "${CALC_DIR}/Batch.log")" -eq "$LINES_BEFORE" ]] || fail "failed submission changed Batch.log"

: > "${CALC_DIR}/Batch.log"
for index in $(seq 1 16); do
    submit_dir="${WORKDIR}/submit-${index}"
    mkdir -- "$submit_dir"
    (
        cd -- "$submit_dir"
        MOCK_JOB_ID=$((500000 + index)) PATH="${SUCCESS_BIN}:${PATH}" \
            "$SCRIPT" "${CALC_DIR}/silicon.abi" >/dev/null
    ) &
done
wait

[[ "$(wc -l < "${CALC_DIR}/Batch.log")" -eq 16 ]] || fail "concurrent Batch.log append lost records"
if grep -Ev '^[0-9-]+ [0-9:]+ \| ABINIT \| job_id=5000[0-9]{2} \| job=silicon \| partition=small \| nodes=1 \| processes=32 \| directory=.* \| input=silicon\.abi \| output=silicon\.log$' "${CALC_DIR}/Batch.log" | grep -q .; then
    fail "concurrent Batch.log append produced a partial record"
fi

echo "PASS mindu ABINIT submission script"
