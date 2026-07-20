#!/usr/bin/env bash

# Usage:
#   myvasp.sh [queue] [nodes] [type]
#
# Queue:
#   s / small       默认
#   c / community
#   h / highio
#
# Type:
#   std             默认
#   gam
#   ncl

set -u

usage() {
    cat <<'EOF'
Usage:
  myvasp.sh [queue] [nodes] [type]

Queue:
  s | small        default
  c | community
  h | highio

Nodes:
  Positive integer; default: 1

Type:
  std              default
  gam
  ncl

Examples:
  myvasp.sh
  myvasp.sh community
  myvasp.sh h 2
  myvasp.sh small 2 gam
  myvasp.sh highio 4 ncl
EOF
}

if (( $# > 3 )); then
    echo "Error: Too many arguments." >&2
    usage
    exit 1
fi

case "${1:-}" in
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
        echo "Error: Unknown queue: $1" >&2
        usage
        exit 1
        ;;
esac

NODES=${2:-1}
if [[ ! "$NODES" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: Nodes must be a positive integer: $NODES" >&2
    exit 1
fi

case "${3:-std}" in
    std|gam|ncl)
        VASP_TYPE=${3:-std}
        ;;
    *)
        echo "Error: Unsupported VASP type: $3" >&2
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

CORES_PER_NODE=32
MPI_PROCESSES=$((NODES * CORES_PER_NODE))
JOB_NAME=$(basename -- "$TASK_DIR")
VASP_COMMAND="vasp_${VASP_TYPE}"
OUTPUT_FILE="log"
ERROR_FILE="vasp.err"
VASP_BIN="/home/liqh/soft/vasp/6.5.1-vtst/bin"
TOOLCHAIN_ENV="/home/liqh/soft/toolchain/vasp651.env"

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

# 清空原路径内容并重建固定运行环境
export PATH=/slurm/bin:/slurm/sbin:/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin:/home/liqh/soft/vaspkit.1.5.1/bin:${VASP_BIN}
export LD_LIBRARY_PATH=/slurm/lib:/lib64:/usr/lib64:/usr/local/lib64

if ! source ${TOOLCHAIN_ENV}; then
    echo "Error: Failed to load the VASP toolchain environment: ${TOOLCHAIN_ENV}" >&2
    exit 1
fi

export I_MPI_ADJUST_REDUCE=3

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
echo "VASP output   : $TASK_DIR/$OUTPUT_FILE"
echo "VASP error    : $TASK_DIR/$ERROR_FILE"
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

if ! SBATCH_OUTPUT=$(sbatch --parsable \
    --job-name="$JOB_NAME" \
    --nodes="$NODES" \
    --ntasks="$MPI_PROCESSES" \
    --partition="$QUEUE" \
    "$TMP_SCRIPT"); then
    echo "Error: VASP job submission failed." >&2
    exit 1
fi

JOB_ID=${SBATCH_OUTPUT%%;*}
if [[ -z "$JOB_ID" ]]; then
    echo "Error: Slurm accepted the job but returned no Job ID." >&2
    exit 1
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
BATCH_LOG="${TASK_DIR}/Batch.log"
RECORD="${TIMESTAMP} | VASP | job_id=${JOB_ID} | job=${JOB_NAME} | partition=${QUEUE} | nodes=${NODES} | processes=${MPI_PROCESSES} | directory=${TASK_DIR} | input=${INPUT_SUMMARY} | output=${OUTPUT_FILE}"

if ! (
    flock -x 9
    printf '%s\n' "$RECORD" >&9
) 9>> "$BATCH_LOG"; then
    echo "警告：作业已提交，但写入 Batch.log 失败。Job ID: ${JOB_ID}" >&2
fi

echo "Submitted batch job ${JOB_ID}"
