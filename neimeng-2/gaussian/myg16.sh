#!/usr/bin/env bash

# Usage: myg16.sh <input.gjf> [cores]
set -u

usage() {
    echo "Usage: myg16.sh <input.gjf> [cores] (default: 40, maximum: 40)"
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

PARTITION="p1"
MAX_CORES=40
CORES=${2:-$MAX_CORES}
if [[ ! "$CORES" =~ ^[1-9][0-9]*$ ]] || (( ${#CORES} > 2 )); then
    echo "Error: Cores must be an integer from 1 to $MAX_CORES." >&2
    exit 1
fi
if (( CORES > MAX_CORES )); then
    echo "Error: Cores must not exceed $MAX_CORES." >&2
    exit 1
fi

# Validate every Link 0 processor setting, including Link1 sections.
FOUND_NPROC=false
shopt -s nocasematch
while IFS= read -r LINE || [[ -n "$LINE" ]]; do
    LINE=${LINE%$'\r'}
    if [[ "$LINE" =~ ^[[:space:]]*%(CPU|LindaWorkers|NProcLinda|NProc)([[:space:]=]|$) ]]; then
        echo "Error: Use %NProcShared for this single-node submission; unsupported CPU/Linda directive." >&2
        exit 1
    fi
    if [[ "$LINE" =~ ^[[:space:]]*%NProcShared([[:space:]=]|$) ]]; then
        if [[ ! "$LINE" =~ ^[[:space:]]*%NProcShared[[:space:]]*=[[:space:]]*([1-9][0-9]*)[[:space:]]*$ ]]; then
            echo "Error: Invalid %NProcShared setting." >&2
            exit 1
        fi
        INPUT_CORES=${BASH_REMATCH[1]}
        if (( ${#INPUT_CORES} > 2 )) || (( INPUT_CORES > CORES )); then
            echo "Error: %NProcShared=$INPUT_CORES exceeds requested cores ($CORES)." >&2
            exit 1
        fi
        FOUND_NPROC=true
    fi
done < "$INPUT_FILE"
shopt -u nocasematch
if [[ "$FOUND_NPROC" != true ]]; then
    echo "Error: Input must explicitly specify %NProcShared (at most $CORES)." >&2
    exit 1
fi

if [[ -e "${INPUT_DIR}/${LOG_FILE}" ]]; then
    echo "警告：日志文件已存在，本次作业将覆盖该文件：${INPUT_DIR}/${LOG_FILE}" >&2
fi

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
#SBATCH --partition=${PARTITION}

echo "Starting Gaussian job \$SLURM_JOB_ID at \$(date)"
echo "SLURM_SUBMIT_DIR: \$SLURM_SUBMIT_DIR"
echo "Running on node(s): \$SLURM_NODELIST"
echo "Requested CPU cores: \$SLURM_CPUS_PER_TASK"

ulimit -s unlimited

# Gaussian 环境
export g16root=/data/app/gaussian/G16-A03

if [[ ! -r "\${g16root}/g16/bsd/g16.profile" || ! -x "\${g16root}/g16/g16" ]]; then
    echo "Error: Gaussian profile or executable is unavailable." >&2
    exit 1
fi

# 避免 g16.profile 中未定义的 PERLLIB 触发错误
set +u
if ! source "\${g16root}/g16/bsd/g16.profile"; then
    echo "Error: Failed to load the Gaussian environment." >&2
    exit 1
fi

# Gaussian 临时目录
if ! mkdir -p "/tmp/\${USER}"; then
    echo "Error: Cannot create scratch parent directory." >&2
    exit 1
fi
if ! GAUSS_SCRDIR=\$(mktemp -d "/tmp/\${USER}/g16_\${SLURM_JOB_ID}.XXXXXX"); then
    echo "Error: Cannot create GAUSS_SCRDIR: \${GAUSS_SCRDIR}" >&2
    exit 1
fi

export GAUSS_SCRDIR
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
"\${g16root}/g16/g16" < ${INPUT_NAME_Q} > ${LOG_FILE_Q} &
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
echo "Partition: $PARTITION"
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
RECORD="${TIMESTAMP} | Gaussian | job_id=${JOB_ID} | job=${JOB_NAME} | partition=${PARTITION} | nodes=1 | cores=${CORES} | directory=${INPUT_DIR} | input=${INPUT_NAME} | output=${LOG_FILE}"

if ! (
    flock -x 9 || exit 1
    printf '%s\n' "$RECORD" >&9
) 9>> "$BATCH_LOG"; then
    echo "警告：作业已提交，但写入 Batch.log 失败。Job ID: ${JOB_ID}" >&2
fi

echo "Submitted batch job ${JOB_ID}"
