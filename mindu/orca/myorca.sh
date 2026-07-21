#!/usr/bin/env bash

# Usage:
#   myorca.sh input_file [queue] [nodes]
#
# Queue:
#   s / small       默认
#   c / community
#   h / highio

set -u

usage() {
    cat <<'EOF'
Usage:
  myorca.sh <input_file> [queue] [nodes]

Queue:
  s | small        default
  c | community
  h | highio

Nodes:
  Positive integer; default: 1

Examples:
  myorca.sh test.inp
  myorca.sh test.inp community
  myorca.sh test.inp h 2
EOF
}

if [[ -z "${1:-}" ]]; then
    echo "Error: No ORCA input file provided." >&2
    usage
    exit 1
fi

if (( $# > 3 )); then
    echo "Error: Too many arguments." >&2
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
ERROR_FILE="orca.err"

case "${2:-}" in
    s|small)
        QUEUE="small"
        ;;
    c|community)
        QUEUE="community"
        ;;
    h|highio)
        QUEUE="highio"
        ;;
    "")
        QUEUE="small"
        ;;
    *)
        echo "Error: Unknown queue: $2" >&2
        usage
        exit 1
        ;;
esac

NODES=${3:-1}
if [[ ! "$NODES" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: Nodes must be a positive integer: $NODES" >&2
    exit 1
fi

TASKS_PER_NODE=32
TASKS=$((NODES * TASKS_PER_NODE))
ORCA_HOME="/home/liqh/soft/orca/orca_6_1_1_linux_x86-64_shared_openmpi418_nodmrg"
OPENMPI_ENV="/home/liqh/soft/openmpi/4.1.6-gcc13.4/env.sh"

printf -v INPUT_DIR_Q '%q' "$INPUT_DIR"
printf -v INPUT_NAME_Q '%q' "$INPUT_NAME"
printf -v LOG_FILE_Q '%q' "$LOG_FILE"
printf -v ERROR_FILE_Q '%q' "$ERROR_FILE"

TMP_SCRIPT=$(mktemp "${TMPDIR:-/tmp}/myorca-${USER:-user}-${JOB_NAME}.XXXXXX")
trap 'rm -f "$TMP_SCRIPT"' EXIT

cat > "$TMP_SCRIPT" <<EOF
#!/usr/bin/env bash

echo "Starting ORCA job \$SLURM_JOB_ID at \$(date)"
echo "SLURM_SUBMIT_DIR: \$SLURM_SUBMIT_DIR"
echo "Running on node(s): \$SLURM_NODELIST"
echo "Requested tasks: \$SLURM_NTASKS"

ulimit -s unlimited

# 清空原路径内容并重建固定运行环境
export PATH=/slurm/bin:/slurm/sbin:/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin:${ORCA_HOME}
export LD_LIBRARY_PATH=/slurm/lib:/lib64:/usr/lib64:/usr/local/lib64:${ORCA_HOME}

if ! source ${OPENMPI_ENV}; then
    echo "Error: Failed to load the OpenMPI environment: ${OPENMPI_ENV}" >&2
    exit 1
fi

cd ${INPUT_DIR_Q} || exit 1

${ORCA_HOME}/orca ${INPUT_NAME_Q} > ${LOG_FILE_Q} 2> ${ERROR_FILE_Q}
STATUS=\$?

echo "ORCA job \$SLURM_JOB_ID finished with status \$STATUS at \$(date)"
exit \$STATUS
EOF

chmod 700 "$TMP_SCRIPT"

if ! bash -n "$TMP_SCRIPT"; then
    echo "Error: Generated Slurm script has a syntax error." >&2
    exit 1
fi

echo "Input       : $INPUT_FILE"
echo "ORCA output : $INPUT_DIR/$LOG_FILE"
echo "ORCA error  : $INPUT_DIR/$ERROR_FILE"
echo "Slurm       : slurm-<jobid>.out"
echo "Queue       : $QUEUE"
echo "Nodes       : $NODES"
echo "Tasks       : $TASKS"

if ! command -v sbatch >/dev/null 2>&1; then
    echo "Error: sbatch command not found." >&2
    exit 1
fi

if ! command -v flock >/dev/null 2>&1; then
    echo "Error: flock command not found; cannot safely update Batch.log." >&2
    exit 1
fi

if ! SBATCH_OUTPUT=$(sbatch --parsable \
    --job-name="$JOB_NAME" \
    --nodes="$NODES" \
    --ntasks="$TASKS" \
    --partition="$QUEUE" \
    "$TMP_SCRIPT"); then
    echo "Error: ORCA job submission failed." >&2
    exit 1
fi

JOB_ID=${SBATCH_OUTPUT%%;*}
if [[ -z "$JOB_ID" ]]; then
    echo "Error: Slurm accepted the job but returned no Job ID." >&2
    exit 1
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
BATCH_LOG="${INPUT_DIR}/Batch.log"
RECORD="${TIMESTAMP} | ORCA | job_id=${JOB_ID} | job=${JOB_NAME} | partition=${QUEUE} | nodes=${NODES} | processes=${TASKS} | directory=${INPUT_DIR} | input=${INPUT_NAME} | output=${LOG_FILE}"

if ! (
    flock -x 9
    printf '%s\n' "$RECORD" >&9
) 9>> "$BATCH_LOG"; then
    echo "警告：作业已提交，但写入 Batch.log 失败。Job ID: ${JOB_ID}" >&2
fi

echo "Submitted batch job ${JOB_ID}"
