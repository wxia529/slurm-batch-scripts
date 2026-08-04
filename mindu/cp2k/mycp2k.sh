#!/usr/bin/env bash

# Usage:
#   mycp2k.sh input_file [queue] [nodes]
#
# Queue:
#   s / small       默认
#   c / community
#   h / highio

set -u

usage() {
    cat <<'EOF'
Usage:
  mycp2k.sh <input_file> [queue] [nodes]

Queue:
  s | small        default
  c | community
  h | highio

Nodes:
  Positive integer; default: 1

Examples:
  mycp2k.sh test.inp
  mycp2k.sh test.inp community
  mycp2k.sh test.inp h 2
EOF
}

if [[ -z "${1:-}" ]]; then
    echo "Error: No CP2K input file provided." >&2
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
OUTPUT_FILE="${JOB_NAME}.out"
ERROR_FILE="cp2k.err"

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

CORES_PER_NODE=32
MPI_PROCESSES=$((NODES * CORES_PER_NODE))

printf -v INPUT_DIR_Q '%q' "$INPUT_DIR"
printf -v INPUT_NAME_Q '%q' "$INPUT_NAME"
printf -v OUTPUT_FILE_Q '%q' "$OUTPUT_FILE"
printf -v ERROR_FILE_Q '%q' "$ERROR_FILE"

TMP_SCRIPT="${PWD}/mycp2k-tmp"

cat > "$TMP_SCRIPT" <<EOF
#!/usr/bin/env bash
#SBATCH --job-name=${JOB_NAME}
#SBATCH --nodes=${NODES}
#SBATCH --ntasks=${MPI_PROCESSES}
#SBATCH --partition=${QUEUE}

echo "Starting CP2K job \$SLURM_JOB_ID at \$(date)"
echo "SLURM_SUBMIT_DIR: \$SLURM_SUBMIT_DIR"
echo "Running on node(s): \$SLURM_NODELIST"
echo "Requested MPI processes: \$SLURM_NTASKS"

ulimit -s unlimited

export PATH=/slurm/bin:/slurm/sbin:/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin:/home/liqh/soft/cp2k/latest/exe/bin
export LD_LIBRARY_PATH=/slurm/lib:/lib64:/usr/lib64:/usr/local/lib64:/home/liqh/soft/cp2k/latest/exe/lib64

if ! source /home/liqh/soft/cp2k/latest/install/cp2k_env; then
    echo "Error: Failed to load the CP2K environment." >&2
    exit 1
fi

if ! source /home/liqh/soft/ucx/1.20.1-gcc13.4/env.sh; then
    echo "Error: Failed to load the UCX environment." >&2
    exit 1
fi

export OMPI_MCA_btl="^openib"
export OMP_NUM_THREADS=1

cd ${INPUT_DIR_Q} || exit 1

mpirun -n ${MPI_PROCESSES} cp2k.psmp ${INPUT_NAME_Q} > ${OUTPUT_FILE_Q} 2> ${ERROR_FILE_Q}
STATUS=\$?

echo "CP2K job \$SLURM_JOB_ID finished with status \$STATUS at \$(date)"
exit \$STATUS
EOF

chmod 700 "$TMP_SCRIPT"

if ! bash -n "$TMP_SCRIPT"; then
    echo "Error: Generated Slurm script has a syntax error." >&2
    exit 1
fi

echo "Input         : $INPUT_FILE"
echo "CP2K output   : $INPUT_DIR/$OUTPUT_FILE"
echo "CP2K error    : $INPUT_DIR/$ERROR_FILE"
echo "Slurm         : slurm-<jobid>.out"
echo "Queue         : $QUEUE"
echo "Nodes         : $NODES"
echo "MPI processes : $MPI_PROCESSES"

if ! command -v sbatch >/dev/null 2>&1; then
    echo "Error: sbatch command not found." >&2
    exit 1
fi

if ! command -v flock >/dev/null 2>&1; then
    echo "Error: flock command not found; cannot safely update Batch.log." >&2
    exit 1
fi

if ! SBATCH_OUTPUT=$(sbatch --parsable "$TMP_SCRIPT"); then
    echo "Error: CP2K job submission failed." >&2
    exit 1
fi

JOB_ID=${SBATCH_OUTPUT%%;*}
if [[ -z "$JOB_ID" ]]; then
    echo "Error: Slurm accepted the job but returned no Job ID." >&2
    exit 1
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
BATCH_LOG="${INPUT_DIR}/Batch.log"
RECORD="${TIMESTAMP} | CP2K | job_id=${JOB_ID} | job=${JOB_NAME} | partition=${QUEUE} | nodes=${NODES} | processes=${MPI_PROCESSES} | directory=${INPUT_DIR} | input=${INPUT_NAME} | output=${OUTPUT_FILE}"

if ! (
    flock -x 9
    printf '%s\n' "$RECORD" >&9
) 9>> "$BATCH_LOG"; then
    echo "警告：作业已提交，但写入 Batch.log 失败。Job ID: ${JOB_ID}" >&2
fi

echo "Submitted batch job ${JOB_ID}"
