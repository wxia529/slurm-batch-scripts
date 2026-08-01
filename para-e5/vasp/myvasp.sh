#!/usr/bin/env bash

set -u

usage() {
    cat <<'EOF'
Usage: myvasp.sh [nodes] [type]

Nodes: positive integer; default: 1
Type : std | gam | ncl; default: std
EOF
}

if (( $# > 2 )); then
    echo "Error: Too many arguments." >&2
    usage
    exit 1
fi

NODES=${1:-1}
if [[ ! "$NODES" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: Nodes must be a positive integer: $NODES" >&2
    exit 1
fi

case "${2:-std}" in
    std|gam|ncl) VASP_TYPE=${2:-std} ;;
    *)
        echo "Error: Unsupported VASP type: ${2:-}" >&2
        usage
        exit 1
        ;;
esac

TASK_DIR=$(pwd -P)
for INPUT_NAME in INCAR POTCAR; do
    if [[ ! -f "${TASK_DIR}/${INPUT_NAME}" ]]; then
        echo "Error: Required VASP input file does not exist: ${TASK_DIR}/${INPUT_NAME}" >&2
        exit 1
    fi
done

if [[ -f "${TASK_DIR}/POSCAR" ]]; then
    INPUT_SUMMARY="INCAR,POSCAR,POTCAR"
else
    IMAGE_DIRECTORIES=()
    for IMAGE_PATH in "${TASK_DIR}"/*; do
        [[ -d "$IMAGE_PATH" ]] || continue
        IMAGE_NAME=${IMAGE_PATH##*/}
        [[ "$IMAGE_NAME" =~ ^[0-9]{2,}$ ]] || continue
        IMAGE_DIRECTORIES+=("$IMAGE_PATH")
    done

    if (( ${#IMAGE_DIRECTORIES[@]} < 2 )); then
        echo "Error: POSCAR is missing and fewer than two VTST image directories were found." >&2
        exit 1
    fi

    for IMAGE_PATH in "${IMAGE_DIRECTORIES[@]}"; do
        if [[ ! -f "${IMAGE_PATH}/POSCAR" ]]; then
            echo "Error: VTST image POSCAR does not exist: ${IMAGE_PATH}/POSCAR" >&2
            exit 1
        fi
    done
    INPUT_SUMMARY="INCAR,POTCAR,numeric-image-directories/POSCAR"
fi

PARTITION="v3_64"
MPI_PROCESSES=$((NODES * 24))
JOB_NAME=$(basename -- "$TASK_DIR")
VASP_COMMAND="vasp_${VASP_TYPE}"
OUTPUT_FILE="log"
ERROR_FILE="vasp.err"

printf -v TASK_DIR_Q '%q' "$TASK_DIR"
TMP_SCRIPT=$(mktemp "${TMPDIR:-/tmp}/myvasp-${USER:-user}-${VASP_TYPE}.XXXXXX")
trap 'rm -f "$TMP_SCRIPT"' EXIT

cat > "$TMP_SCRIPT" <<EOF
#!/usr/bin/env bash

echo "Starting VASP job \$SLURM_JOB_ID at \$(date)"
echo "SLURM_SUBMIT_DIR: \$SLURM_SUBMIT_DIR"
echo "Running on node(s): \$SLURM_NODELIST"
echo "Requested MPI processes: \$SLURM_NTASKS"
ulimit -s unlimited

export PATH=/publicfs01/fs1-9/home/sc32041/soft/vasp/6.5.1-vtst/bin:/opt/slurm/slurm/sbin:/opt/slurm/slurm/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/opt/ibutils/bin
export LD_LIBRARY_PATH=/opt/slurm/slurm/lib:/lib64:/usr/lib64:/usr/local/lib64
if ! source /publicfs01/fs1-9/home/sc32041/soft/toolchain/vasp651.env; then
    echo "Error: Failed to load the VASP environment." >&2
    exit 1
fi
export OMP_NUM_THREADS=1

cd ${TASK_DIR_Q} || exit 1
mpirun -n ${MPI_PROCESSES} ${VASP_COMMAND} >> ${OUTPUT_FILE} 2> ${ERROR_FILE}
STATUS=\$?
echo "VASP job \$SLURM_JOB_ID finished with status \$STATUS at \$(date)"
exit \$STATUS
EOF

chmod 700 "$TMP_SCRIPT"
if ! bash -n "$TMP_SCRIPT"; then
    echo "Error: Generated Slurm script has a syntax error." >&2
    exit 1
fi

echo "Directory     : $TASK_DIR"
echo "Job name      : $JOB_NAME"
echo "VASP command  : $VASP_COMMAND"
echo "Partition     : $PARTITION"
echo "Nodes         : $NODES"
echo "MPI processes : $MPI_PROCESSES"

if ! command -v sbatch >/dev/null 2>&1 || ! command -v flock >/dev/null 2>&1; then
    echo "Error: sbatch and flock are required." >&2
    exit 1
fi
if ! SBATCH_OUTPUT=$(sbatch --parsable --job-name="$JOB_NAME" --nodes="$NODES" --ntasks="$MPI_PROCESSES" --partition="$PARTITION" "$TMP_SCRIPT"); then
    echo "Error: VASP job submission failed." >&2
    exit 1
fi

JOB_ID=${SBATCH_OUTPUT%%;*}
[[ -n "$JOB_ID" ]] || { echo "Error: Slurm returned no Job ID." >&2; exit 1; }
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
BATCH_LOG="${TASK_DIR}/Batch.log"
RECORD="${TIMESTAMP} | VASP | job_id=${JOB_ID} | job=${JOB_NAME} | partition=${PARTITION} | nodes=${NODES} | processes=${MPI_PROCESSES} | directory=${TASK_DIR} | input=${INPUT_SUMMARY} | output=${OUTPUT_FILE}"
if ! (flock -x 9; printf '%s\n' "$RECORD" >&9) 9>> "$BATCH_LOG"; then
    echo "警告：作业已提交，但写入 Batch.log 失败。Job ID: ${JOB_ID}" >&2
fi
echo "Submitted batch job ${JOB_ID}"
