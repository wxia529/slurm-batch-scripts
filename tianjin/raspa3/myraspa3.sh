#!/usr/bin/env bash

set -u

usage() {
    cat <<'EOF'
Usage: myraspa3.sh

Partition: p1
Nodes: 1
CPUs per task: 48
Input: simulation.json in the current directory
Options: -h, --help    Show this help and exit without submitting a job.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if (( $# > 0 )); then
    echo "Error: Too many arguments." >&2
    usage
    exit 1
fi

TASK_DIR=$(pwd -P)
INPUT_NAME="simulation.json"
INPUT_FILE="${TASK_DIR}/${INPUT_NAME}"
if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: Required RASPA3 input file does not exist: ${INPUT_FILE}" >&2
    exit 1
fi

NODES=1
CORES_PER_NODE=48
PARTITION="p1"
JOB_NAME=$(basename -- "$TASK_DIR")
OUTPUT_FILE="raspa3.out"
ERROR_FILE="raspa3.err"
RASPA_ENV="/data/home/liqh/soft/raspa3/env.sh"

if [[ -e "${TASK_DIR}/${OUTPUT_FILE}" ]]; then
    echo "警告：输出文件已存在，本次作业将覆盖该文件：${TASK_DIR}/${OUTPUT_FILE}" >&2
fi

printf -v TASK_DIR_Q '%q' "$TASK_DIR"
printf -v OUTPUT_FILE_Q '%q' "$OUTPUT_FILE"
printf -v ERROR_FILE_Q '%q' "$ERROR_FILE"

TMP_SCRIPT="${PWD}/myraspa3-tmp"

cat > "$TMP_SCRIPT" <<EOF
#!/usr/bin/env bash
#SBATCH --job-name=${JOB_NAME}
#SBATCH --nodes=${NODES}
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=${CORES_PER_NODE}
#SBATCH --partition=${PARTITION}

echo "Starting RASPA3 job \$SLURM_JOB_ID at \$(date)"
echo "SLURM_SUBMIT_DIR: \$SLURM_SUBMIT_DIR"
echo "Running on node(s): \$SLURM_NODELIST"
echo "Requested CPUs per task: \$SLURM_CPUS_PER_TASK"
ulimit -s unlimited

export PATH=/data/home/liqh/.local/bin:/data/home/liqh/bin:/usr/share/Modules/bin:/usr/lpp/mmfs/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin
export LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/lib:/usr/lib64:/usr/lib:/lib64:/lib
if ! source ${RASPA_ENV}; then
    echo "Error: Failed to load the RASPA3 environment: ${RASPA_ENV}" >&2
    exit 1
fi

if ! command -v raspa3 >/dev/null 2>&1; then
    echo "Error: raspa3 is unavailable after loading ${RASPA_ENV}." >&2
    exit 1
fi
if [[ ! -d "\${RASPA_DIR:-}" ]]; then
    echo "Error: RASPA_DIR is unavailable after loading ${RASPA_ENV}." >&2
    exit 1
fi

cd ${TASK_DIR_Q} || exit 1
raspa3 > ${OUTPUT_FILE_Q} 2> ${ERROR_FILE_Q}
STATUS=\$?
echo "RASPA3 job \$SLURM_JOB_ID finished with status \$STATUS at \$(date)"
exit \$STATUS
EOF

chmod 700 "$TMP_SCRIPT"
if ! bash -n "$TMP_SCRIPT"; then
    echo "Error: Generated Slurm script has a syntax error." >&2
    exit 1
fi

echo "Directory  : $TASK_DIR"
echo "Input      : $INPUT_FILE"
echo "RASPA3 out : $TASK_DIR/$OUTPUT_FILE"
echo "RASPA3 err : $TASK_DIR/$ERROR_FILE"
echo "Partition  : $PARTITION"
echo "Nodes      : $NODES"
echo "CPUs       : $CORES_PER_NODE"

if ! command -v sbatch >/dev/null 2>&1 || ! command -v flock >/dev/null 2>&1; then
    echo "Error: sbatch and flock are required." >&2
    exit 1
fi
if ! SBATCH_OUTPUT=$(sbatch --parsable "$TMP_SCRIPT"); then
    echo "Error: RASPA3 job submission failed." >&2
    exit 1
fi

JOB_ID=${SBATCH_OUTPUT%%;*}
[[ -n "$JOB_ID" ]] || { echo "Error: Slurm returned no Job ID." >&2; exit 1; }
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
BATCH_LOG="${TASK_DIR}/Batch.log"
RECORD="${TIMESTAMP} | RASPA3 | job_id=${JOB_ID} | job=${JOB_NAME} | partition=${PARTITION} | nodes=${NODES} | cores=${CORES_PER_NODE} | directory=${TASK_DIR} | input=${INPUT_NAME} | output=${OUTPUT_FILE}"
if ! (flock -x 9; printf '%s\n' "$RECORD" >&9) 9>> "$BATCH_LOG"; then
    echo "警告：作业已提交，但写入 Batch.log 失败。Job ID: ${JOB_ID}" >&2
fi
echo "Submitted batch job ${JOB_ID}"
