#!/usr/bin/env bash

set -u

usage() {
    echo "Usage: myg16.sh <input.gjf>"
}

if (( $# != 1 )); then
    echo "Error: Exactly one Gaussian input file is required." >&2
    usage
    exit 1
fi

if [[ ! -f "$1" ]]; then
    echo "Error: Input file does not exist: $1" >&2
    exit 1
fi

INPUT_FILE=$(readlink -f -- "$1")
INPUT_DIR=$(dirname -- "$INPUT_FILE")
INPUT_NAME=$(basename -- "$INPUT_FILE")
JOB_NAME=${INPUT_NAME%.*}
LOG_FILE="${JOB_NAME}.log"
PARTITION="amd_256"
CORES=64

if [[ -e "${INPUT_DIR}/${LOG_FILE}" ]]; then
    echo "警告：日志文件已存在，本次作业将覆盖该文件：${INPUT_DIR}/${LOG_FILE}" >&2
fi

printf -v INPUT_DIR_Q '%q' "$INPUT_DIR"
printf -v INPUT_NAME_Q '%q' "$INPUT_NAME"
printf -v LOG_FILE_Q '%q' "$LOG_FILE"

TMP_SCRIPT="${PWD}/myg16-tmp"

cat > "$TMP_SCRIPT" <<EOF
#!/usr/bin/env bash

echo "Starting Gaussian job \$SLURM_JOB_ID at \$(date)"
echo "SLURM_SUBMIT_DIR: \$SLURM_SUBMIT_DIR"
echo "Running on node(s): \$SLURM_NODELIST"
echo "Requested CPU cores: \$SLURM_CPUS_PER_TASK"

ulimit -s unlimited

export PATH=/opt/slurm/slurm/sbin:/opt/slurm/slurm/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/opt/ibutils/bin
export LD_LIBRARY_PATH=/opt/slurm/slurm/lib:/lib64:/usr/lib64:/usr/local/lib64

export g16root=/public3/home/sc71468/soft/Gaussian/A03
set +u
if ! source /public3/home/sc71468/soft/Gaussian/A03/g16/bsd/g16.profile; then
    echo "Error: Failed to load the Gaussian environment." >&2
    exit 1
fi

export GAUSS_SCRDIR="/public3/home/sc71468/soft/tmp/\${SLURM_JOB_ID}"
export PGI_FASTMATH_CPU=sandybridge
if ! mkdir -p "\${GAUSS_SCRDIR}"; then
    echo "Error: Cannot create GAUSS_SCRDIR: \${GAUSS_SCRDIR}" >&2
    exit 1
fi

GAUSSIAN_PID=""

cleanup() {
    rm -rf -- "\${GAUSS_SCRDIR}"
}

terminate() {
    SIGNAL="\$1"
    STATUS="\$2"
    trap - EXIT TERM INT HUP
    if [[ -n "\${GAUSSIAN_PID}" ]] && kill -0 "\${GAUSSIAN_PID}" 2>/dev/null; then
        kill -s "\${SIGNAL}" "\${GAUSSIAN_PID}" 2>/dev/null || true
        wait "\${GAUSSIAN_PID}" 2>/dev/null || true
    fi
    cleanup
    exit "\${STATUS}"
}

trap cleanup EXIT
trap 'terminate TERM 143' TERM
trap 'terminate INT 130' INT
trap 'terminate HUP 129' HUP

cd ${INPUT_DIR_Q} || exit 1

g16 < ${INPUT_NAME_Q} > ${LOG_FILE_Q} &
GAUSSIAN_PID=\$!
wait "\${GAUSSIAN_PID}"
STATUS=\$?
GAUSSIAN_PID=""

echo "Gaussian job \$SLURM_JOB_ID finished with status \$STATUS at \$(date)"
exit \$STATUS
EOF

chmod 700 "$TMP_SCRIPT"
if ! bash -n "$TMP_SCRIPT"; then
    echo "Error: Generated Slurm script has a syntax error." >&2
    exit 1
fi

echo "Input    : $INPUT_FILE"
echo "Gaussian : $INPUT_DIR/$LOG_FILE"
echo "Queue    : $PARTITION"
echo "Cores    : $CORES"

if ! command -v sbatch >/dev/null 2>&1 || ! command -v flock >/dev/null 2>&1; then
    echo "Error: sbatch and flock are required." >&2
    exit 1
fi

if ! SBATCH_OUTPUT=$(sbatch --parsable --job-name="$JOB_NAME" --nodes=1 --ntasks=1 --cpus-per-task="$CORES" --partition="$PARTITION" "$TMP_SCRIPT"); then
    echo "Error: Gaussian job submission failed." >&2
    exit 1
fi

JOB_ID=${SBATCH_OUTPUT%%;*}
[[ -n "$JOB_ID" ]] || { echo "Error: Slurm returned no Job ID." >&2; exit 1; }
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
BATCH_LOG="${INPUT_DIR}/Batch.log"
RECORD="${TIMESTAMP} | Gaussian | job_id=${JOB_ID} | job=${JOB_NAME} | partition=${PARTITION} | nodes=1 | cores=${CORES} | directory=${INPUT_DIR} | input=${INPUT_NAME} | output=${LOG_FILE}"
if ! (flock -x 9; printf '%s\n' "$RECORD" >&9) 9>> "$BATCH_LOG"; then
    echo "警告：作业已提交，但写入 Batch.log 失败。Job ID: ${JOB_ID}" >&2
fi
echo "Submitted batch job ${JOB_ID}"
