#!/usr/bin/env bash

set -u

usage() {
    echo "Usage: mybands.sh <input_file> [nodes]"
}

if (( $# < 1 || $# > 2 )); then
    echo "Error: A Quantum ESPRESSO bands.x input file and optional node count are required." >&2
    usage
    exit 1
fi
if [[ ! -f "$1" ]]; then
    echo "Error: Input file does not exist: $1" >&2
    exit 1
fi

NODES=${2:-1}
if [[ ! "$NODES" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: Nodes must be a positive integer: $NODES" >&2
    exit 1
fi

INPUT_FILE=$(readlink -f -- "$1")
INPUT_DIR=$(dirname -- "$INPUT_FILE")
INPUT_NAME=$(basename -- "$INPUT_FILE")
JOB_NAME=${INPUT_NAME%.*}
OUTPUT_FILE="${JOB_NAME}.log"
ERROR_FILE="bands.err"
PARTITION="v3_64"
MPI_PROCESSES=$((NODES * 24))

printf -v INPUT_DIR_Q '%q' "$INPUT_DIR"
printf -v INPUT_NAME_Q '%q' "$INPUT_NAME"
printf -v OUTPUT_FILE_Q '%q' "$OUTPUT_FILE"
printf -v ERROR_FILE_Q '%q' "$ERROR_FILE"

TMP_SCRIPT=$(mktemp "${TMPDIR:-/tmp}/mybands-${USER:-user}-${JOB_NAME}.XXXXXX")
trap 'rm -f "$TMP_SCRIPT"' EXIT

cat > "$TMP_SCRIPT" <<EOF
#!/usr/bin/env bash

echo "Starting QE bands.x job \$SLURM_JOB_ID at \$(date)"
echo "SLURM_SUBMIT_DIR: \$SLURM_SUBMIT_DIR"
echo "Running on node(s): \$SLURM_NODELIST"
echo "Requested MPI processes: \$SLURM_NTASKS"
ulimit -s unlimited

export PATH=/publicfs01/fs1-9/home/sc32041/soft/QE/qe-7.5/bin:/opt/slurm/slurm/sbin:/opt/slurm/slurm/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/opt/ibutils/bin
export LD_LIBRARY_PATH=/publicfs01/fs1-9/home/sc32041/soft/QE/qe-7.5/lib:/opt/slurm/slurm/lib:/lib64:/usr/lib64:/usr/local/lib64
if ! source /publicfs01/fs1-9/home/sc32041/soft/toolchain/qe.env; then
    echo "Error: Failed to load the Quantum ESPRESSO environment." >&2
    exit 1
fi
export OMP_NUM_THREADS=1

cd ${INPUT_DIR_Q} || exit 1
mpirun -n ${MPI_PROCESSES} bands.x -inp ${INPUT_NAME_Q} > ${OUTPUT_FILE_Q} 2> ${ERROR_FILE_Q}
STATUS=\$?
echo "QE bands.x job \$SLURM_JOB_ID finished with status \$STATUS at \$(date)"
exit \$STATUS
EOF

chmod 700 "$TMP_SCRIPT"
if ! bash -n "$TMP_SCRIPT"; then
    echo "Error: Generated Slurm script has a syntax error." >&2
    exit 1
fi

echo "Input         : $INPUT_FILE"
echo "QE program    : bands.x"
echo "QE output     : $INPUT_DIR/$OUTPUT_FILE"
echo "Partition     : $PARTITION"
echo "Nodes         : $NODES"
echo "MPI processes : $MPI_PROCESSES"

if ! command -v sbatch >/dev/null 2>&1 || ! command -v flock >/dev/null 2>&1; then
    echo "Error: sbatch and flock are required." >&2
    exit 1
fi
if ! SBATCH_OUTPUT=$(sbatch --parsable --job-name="$JOB_NAME" --nodes="$NODES" --ntasks="$MPI_PROCESSES" --partition="$PARTITION" "$TMP_SCRIPT"); then
    echo "Error: QE bands.x job submission failed." >&2
    exit 1
fi

JOB_ID=${SBATCH_OUTPUT%%;*}
[[ -n "$JOB_ID" ]] || { echo "Error: Slurm returned no Job ID." >&2; exit 1; }
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
BATCH_LOG="${INPUT_DIR}/Batch.log"
RECORD="${TIMESTAMP} | QE | job_id=${JOB_ID} | job=${JOB_NAME} | partition=${PARTITION} | nodes=${NODES} | processes=${MPI_PROCESSES} | directory=${INPUT_DIR} | input=${INPUT_NAME} | output=${OUTPUT_FILE}"
if ! (flock -x 9; printf '%s\n' "$RECORD" >&9) 9>> "$BATCH_LOG"; then
    echo "警告：作业已提交，但写入 Batch.log 失败。Job ID: ${JOB_ID}" >&2
fi
echo "Submitted batch job ${JOB_ID}"
