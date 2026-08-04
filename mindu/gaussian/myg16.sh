#!/usr/bin/env bash

# Usage:
#   myg16.sh input.gjf [queue]
#
# Queue:
#   s / small       默认
#   c / community
#   h / highio

set -u

usage() {
    cat <<'EOF'
Usage:
  myg16.sh <input.gjf> [queue]

Queue:
  s | small        default
  c | community
  h | highio

Examples:
  myg16.sh test.gjf
  myg16.sh test.gjf c
  myg16.sh test.gjf h
EOF
}

# 检查输入文件
if [[ -z "${1:-}" ]]; then
    echo "Error: No Gaussian input file provided." >&2
    usage
    exit 1
fi

if (( $# > 2 )); then
    echo "Error: Too many arguments." >&2
    usage
    exit 1
fi

if [[ ! -f "$1" ]]; then
    echo "Error: Input file does not exist: $1" >&2
    exit 1
fi

# 输入文件信息
INPUT_FILE=$(readlink -f -- "$1")
INPUT_DIR=$(dirname -- "$INPUT_FILE")
INPUT_NAME=$(basename -- "$INPUT_FILE")
JOB_NAME=${INPUT_NAME%.*}
LOG_FILE="${JOB_NAME}.log"

# 队列选择
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

if [[ -e "${INPUT_DIR}/${LOG_FILE}" ]]; then
    echo "警告：日志文件已存在，本次作业将覆盖该文件：${INPUT_DIR}/${LOG_FILE}" >&2
fi

# Gaussian 固定使用 32 核
CORES=32

# 安全地把路径写入临时脚本
printf -v INPUT_DIR_Q '%q' "$INPUT_DIR"
printf -v INPUT_NAME_Q '%q' "$INPUT_NAME"
printf -v LOG_FILE_Q '%q' "$LOG_FILE"

# 临时 Slurm 脚本
TMP_SCRIPT="${PWD}/myg16-tmp"

cat > "$TMP_SCRIPT" <<EOF
#!/usr/bin/env bash
#SBATCH --job-name=${JOB_NAME}
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=${CORES}
#SBATCH --partition=${QUEUE}

echo "Starting Gaussian job \$SLURM_JOB_ID at \$(date)"
echo "SLURM_SUBMIT_DIR: \$SLURM_SUBMIT_DIR"
echo "Running on node(s): \$SLURM_NODELIST"
echo "Requested CPU cores: \$SLURM_CPUS_PER_TASK"

ulimit -s unlimited

# Gaussian 环境
export g16root=/share/soft/gaussian/G16C01AVX

# 避免 g16.profile 中未定义的 PERLLIB 触发错误
set +u
if ! source "\${g16root}/g16/bsd/g16.profile"; then
    echo "Error: Failed to load the Gaussian environment." >&2
    exit 1
fi

# Gaussian 临时目录
export GAUSS_SCRDIR="/tmp/\${USER}/g16_\${SLURM_JOB_ID}"
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

echo "GAUSS_SCRDIR: \$GAUSS_SCRDIR"

# 进入输入文件所在目录
cd ${INPUT_DIR_Q} || exit 1

# 运行 Gaussian
g16 < ${INPUT_NAME_Q} > ${LOG_FILE_Q} &
GAUSSIAN_PID=\$!
wait "\${GAUSSIAN_PID}"
STATUS=\$?
GAUSSIAN_PID=""

echo "Gaussian job \$SLURM_JOB_ID finished with status \$STATUS at \$(date)"

exit \$STATUS
EOF

chmod 700 "$TMP_SCRIPT"

# 检查生成脚本语法
if ! bash -n "$TMP_SCRIPT"; then
    echo "Error: Generated Slurm script has a syntax error." >&2
    exit 1
fi

echo "Input    : $INPUT_FILE"
echo "Gaussian : $INPUT_DIR/$LOG_FILE"
echo "Slurm    : slurm-<jobid>.out"
echo "Queue    : $QUEUE"
echo "Cores    : $CORES"

if ! command -v sbatch >/dev/null 2>&1; then
    echo "Error: sbatch command not found." >&2
    exit 1
fi

if ! command -v flock >/dev/null 2>&1; then
    echo "Error: flock command not found; cannot safely update Batch.log." >&2
    exit 1
fi

if ! SBATCH_OUTPUT=$(sbatch --parsable "$TMP_SCRIPT"); then
    echo "Error: Gaussian job submission failed." >&2
    exit 1
fi

JOB_ID=${SBATCH_OUTPUT%%;*}
if [[ -z "$JOB_ID" ]]; then
    echo "Error: Slurm accepted the job but returned no Job ID." >&2
    exit 1
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
BATCH_LOG="${INPUT_DIR}/Batch.log"
RECORD="${TIMESTAMP} | Gaussian | job_id=${JOB_ID} | job=${JOB_NAME} | partition=${QUEUE} | nodes=1 | cores=${CORES} | directory=${INPUT_DIR} | input=${INPUT_NAME} | output=${LOG_FILE}"

if ! (
    flock -x 9
    printf '%s\n' "$RECORD" >&9
) 9>> "$BATCH_LOG"; then
    echo "警告：作业已提交，但写入 Batch.log 失败。Job ID: ${JOB_ID}" >&2
fi

echo "Submitted batch job ${JOB_ID}"
