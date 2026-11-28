#!/usr/bin/env bash

set -u

usage() {
    cat <<'EOF'
Usage:
  myabinit.sh <input_file> [queue] [nodes]

Queue:
  s | small        default
  c | community
  h | highio

Nodes:
  Positive integer; default: 1

Examples:
  myabinit.sh silicon.abi
  myabinit.sh silicon.abi community
  myabinit.sh silicon.abi h 2
Options: -h, --help    Show this help and exit without submitting a job.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ -z "${1:-}" ]]; then
    echo "Error: No ABINIT input file provided." >&2
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
if [[ "$INPUT_FILE" == *$'\n'* || "$INPUT_FILE" == *$'\t'* ]]; then
    echo "Error: Input path must not contain tabs or newlines." >&2
    exit 1
fi
INPUT_DIR=$(dirname -- "$INPUT_FILE")
INPUT_NAME=$(basename -- "$INPUT_FILE")
JOB_NAME=${INPUT_NAME%.*}
if [[ -z "$JOB_NAME" || ! "$JOB_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "Error: Input basename must use only letters, numbers, dots, underscores, and hyphens: $INPUT_NAME" >&2
    exit 1
fi
OUTPUT_FILE="${JOB_NAME}.log"
ERROR_FILE="abinit.err"

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
printf -v INPUT_FILE_Q '%q' "$INPUT_FILE"
printf -v INPUT_NAME_Q '%q' "$INPUT_NAME"
printf -v OUTPUT_FILE_Q '%q' "$OUTPUT_FILE"
printf -v ERROR_FILE_Q '%q' "$ERROR_FILE"

TMP_SCRIPT="${PWD}/myabinit-tmp"

if ! cat > "$TMP_SCRIPT" <<EOF
#!/usr/bin/env bash
#SBATCH --job-name=${JOB_NAME}
#SBATCH --nodes=${NODES}
#SBATCH --ntasks=${MPI_PROCESSES}
#SBATCH --ntasks-per-node=${CORES_PER_NODE}
#SBATCH --partition=${QUEUE}

echo "Starting ABINIT job \$SLURM_JOB_ID at \$(date)"
echo "SLURM_SUBMIT_DIR: \$SLURM_SUBMIT_DIR"
echo "Running on node(s): \$SLURM_NODELIST"
printf 'ABINIT input: %s\n' ${INPUT_FILE_Q}
echo "Requested MPI processes: \$SLURM_NTASKS"

ulimit -s unlimited

export PATH=/slurm/bin:/slurm/sbin:/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin
export LD_LIBRARY_PATH=/slurm/lib:/lib64:/usr/lib64:/usr/local/lib64
if ! source /home/liqh/soft/ABINIT/env-10.8.3-oneapi2022-avx512.sh; then
    echo "Error: Failed to load the ABINIT environment." >&2
    exit 1
fi
export OMP_NUM_THREADS=1

if ! command -v abinit >/dev/null 2>&1; then
    echo "Error: abinit is unavailable after loading the ABINIT environment." >&2
    exit 1
fi
if ! command -v mpirun >/dev/null 2>&1; then
    echo "Error: mpirun is unavailable after loading the ABINIT environment." >&2
    exit 1
fi

cd ${INPUT_DIR_Q} || exit 1

mpirun -n ${MPI_PROCESSES} abinit ${INPUT_NAME_Q} > ${OUTPUT_FILE_Q} 2> ${ERROR_FILE_Q}
STATUS=\$?

echo "ABINIT job \$SLURM_JOB_ID finished with status \$STATUS at \$(date)"
exit \$STATUS
EOF
then
    echo "Error: Failed to write generated Slurm script: $TMP_SCRIPT" >&2
    exit 1
fi

if ! chmod 700 "$TMP_SCRIPT"; then
    echo "Error: Failed to make generated Slurm script executable: $TMP_SCRIPT" >&2
    exit 1
fi

if ! bash -n "$TMP_SCRIPT"; then
    echo "Error: Generated Slurm script has a syntax error." >&2
    exit 1
fi

echo "Input         : $INPUT_FILE"
echo "ABINIT output : $INPUT_DIR/$OUTPUT_FILE"
echo "ABINIT error  : $INPUT_DIR/$ERROR_FILE"
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
    echo "Error: ABINIT job submission failed." >&2
    exit 1
fi

JOB_ID=${SBATCH_OUTPUT%%;*}
if [[ ! "$JOB_ID" =~ ^[0-9]+$ ]]; then
    echo "Error: Slurm returned an invalid Job ID: $SBATCH_OUTPUT" >&2
    exit 1
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
BATCH_LOG="${INPUT_DIR}/Batch.log"
RECORD="${TIMESTAMP} | ABINIT | job_id=${JOB_ID} | job=${JOB_NAME} | partition=${QUEUE} | nodes=${NODES} | processes=${MPI_PROCESSES} | directory=${INPUT_DIR} | input=${INPUT_NAME} | output=${OUTPUT_FILE}"

if ! (
    flock -x 9
    printf '%s\n' "$RECORD" >&9
) 9>> "$BATCH_LOG"; then
    echo "警告：作业已提交，但写入 Batch.log 失败。Job ID: ${JOB_ID}" >&2
fi

echo "Submitted batch job ${JOB_ID}"
