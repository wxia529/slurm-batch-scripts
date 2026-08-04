#!/usr/bin/env bash

set -u

usage() {
    echo "Usage: mycp2k.sh <input_file> [nodes]"
}

if (( $# < 1 || $# > 2 )); then
    echo "Error: A CP2K input file and optional node count are required." >&2
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
OUTPUT_FILE="${JOB_NAME}.out"
ERROR_FILE="cp2k.err"
PARTITION="amd_256"
MPI_PROCESSES=$((NODES * 64))

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
#SBATCH --partition=${PARTITION}

echo "Starting CP2K job \$SLURM_JOB_ID at \$(date)"
echo "SLURM_SUBMIT_DIR: \$SLURM_SUBMIT_DIR"
echo "Running on node(s): \$SLURM_NODELIST"
echo "Requested MPI processes: \$SLURM_NTASKS"
ulimit -s unlimited

export PATH=/opt/slurm/slurm/sbin:/opt/slurm/slurm/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/opt/ibutils/bin:/public3/home/sc71468/soft/cp2k/latest/exe/bin:/public3/home/sc71468/soft/Multiwfn:/public3/home/sc71468/soft/shs/cp2k
export LD_LIBRARY_PATH=/opt/slurm/slurm/lib:/lib64:/usr/lib64:/usr/local/lib64:/public3/home/sc71468/soft/cp2k/latest/exe/lib64

if ! source /public3/home/sc71468/soft/cp2k/latest/install/cp2k_env; then
    echo "Error: Failed to load the CP2K environment." >&2
    exit 1
fi
if ! source /public3/home/sc71468/soft/ucx/1.21-gcc-13.2/env.sh; then
    echo "Error: Failed to load the UCX environment." >&2
    exit 1
fi
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
echo "Queue         : $PARTITION"
echo "Nodes         : $NODES"
echo "MPI processes : $MPI_PROCESSES"

if ! command -v sbatch >/dev/null 2>&1 || ! command -v flock >/dev/null 2>&1; then
    echo "Error: sbatch and flock are required." >&2
    exit 1
fi
if ! SBATCH_OUTPUT=$(sbatch --parsable "$TMP_SCRIPT"); then
    echo "Error: CP2K job submission failed." >&2
    exit 1
fi

JOB_ID=${SBATCH_OUTPUT%%;*}
[[ -n "$JOB_ID" ]] || { echo "Error: Slurm returned no Job ID." >&2; exit 1; }
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
BATCH_LOG="${INPUT_DIR}/Batch.log"
RECORD="${TIMESTAMP} | CP2K | job_id=${JOB_ID} | job=${JOB_NAME} | partition=${PARTITION} | nodes=${NODES} | processes=${MPI_PROCESSES} | directory=${INPUT_DIR} | input=${INPUT_NAME} | output=${OUTPUT_FILE}"
if ! (flock -x 9; printf '%s\n' "$RECORD" >&9) 9>> "$BATCH_LOG"; then
    echo "警告：作业已提交，但写入 Batch.log 失败。Job ID: ${JOB_ID}" >&2
fi
echo "Submitted batch job ${JOB_ID}"
