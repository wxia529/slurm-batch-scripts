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
CORES_PER_NODE=48
MPI_PROCESSES=$((NODES * CORES_PER_NODE))
PARTITION="p1"
CP2K_HOME="/data/home/liqh/soft/cp2k/2026.2"
CP2K_INSTALL="${CP2K_HOME}/install"
CP2K_ENV="${CP2K_INSTALL}/cp2k_env"
UCX_ENV="/data/home/liqh/soft/ucx/1.22-gcc8.5/env.sh"

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
#SBATCH --ntasks-per-node=${CORES_PER_NODE}
#SBATCH --partition=${PARTITION}

echo "Starting CP2K job \$SLURM_JOB_ID at \$(date)"
echo "SLURM_SUBMIT_DIR: \$SLURM_SUBMIT_DIR"
echo "Running on node(s): \$SLURM_NODELIST"
echo "Requested MPI processes: \$SLURM_NTASKS"
ulimit -s unlimited

export PATH=${CP2K_INSTALL}/bin:/data/home/liqh/.local/bin:/data/home/liqh/bin:/usr/share/Modules/bin:/usr/lpp/mmfs/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin
export LD_LIBRARY_PATH=${CP2K_INSTALL}/lib64:${CP2K_INSTALL}/lib:/usr/local/lib64:/usr/local/lib:/usr/lib64:/usr/lib:/lib64:/lib
if ! source ${CP2K_ENV}; then
    echo "Error: Failed to load the CP2K environment: ${CP2K_ENV}" >&2
    exit 1
fi
if ! source ${UCX_ENV}; then
    echo "Error: Failed to load the UCX environment: ${UCX_ENV}" >&2
    exit 1
fi

export OMPI_MCA_pml=ucx
export OMPI_MCA_btl=^openib
export OMP_NUM_THREADS=1

if ! command -v mpirun >/dev/null 2>&1; then
    echo "Error: mpirun is unavailable after loading ${CP2K_ENV}." >&2
    exit 1
fi
if ! command -v cp2k.psmp >/dev/null 2>&1; then
    echo "Error: cp2k.psmp is unavailable after loading ${CP2K_ENV}." >&2
    exit 1
fi

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
echo "Partition     : $PARTITION"
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
