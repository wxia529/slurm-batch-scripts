#!/usr/bin/env bash

set -u

usage() {
    echo "Usage: myqe-core.sh <program> <error_file> <tmp_script> <input_file> [queue] [nodes]"
}

if (( $# < 4 || $# > 6 )); then
    echo "Error: A QE program, error file, temporary script name, input file, and optional queue/nodes are required." >&2
    usage
    exit 1
fi

PROGRAM=$1
ERROR_FILE=$2
TMP_SCRIPT_NAME=$3
INPUT_ARG=$4
if [[ ! -f "$INPUT_ARG" ]]; then
    echo "Error: Input file does not exist: $INPUT_ARG" >&2
    exit 1
fi

case "${5:-}" in
    s|small) QUEUE="small" ;;
    c|community) QUEUE="community" ;;
    h|highio) QUEUE="highio" ;;
    "") QUEUE="small" ;;
    *)
        echo "Error: Unknown queue: $5" >&2
        usage
        exit 1
        ;;
esac

NODES=${6:-1}
if [[ ! "$NODES" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: Nodes must be a positive integer: $NODES" >&2
    exit 1
fi

INPUT_FILE=$(readlink -f -- "$INPUT_ARG")
INPUT_DIR=$(dirname -- "$INPUT_FILE")
INPUT_NAME=$(basename -- "$INPUT_FILE")
JOB_NAME=${INPUT_NAME%.*}
OUTPUT_FILE="${JOB_NAME}.log"
MPI_PROCESSES=$((NODES * 32))

case "$PROGRAM" in
    neb.x|fdvib) INPUT_MODE="named" ;;
    *)           INPUT_MODE="redirect" ;;
esac

printf -v INPUT_DIR_Q '%q' "$INPUT_DIR"
printf -v INPUT_NAME_Q '%q' "$INPUT_NAME"
printf -v OUTPUT_FILE_Q '%q' "$OUTPUT_FILE"
printf -v ERROR_FILE_Q '%q' "$ERROR_FILE"
printf -v PROGRAM_Q '%q' "$PROGRAM"

if [[ "$INPUT_MODE" == "redirect" ]]; then
    RUN_COMMAND="mpirun -n ${MPI_PROCESSES} ${PROGRAM_Q} < ${INPUT_NAME_Q} > ${OUTPUT_FILE_Q} 2> ${ERROR_FILE_Q}"
else
    RUN_COMMAND="mpirun -n ${MPI_PROCESSES} ${PROGRAM_Q} -inp ${INPUT_NAME_Q} > ${OUTPUT_FILE_Q} 2> ${ERROR_FILE_Q}"
fi

TMP_SCRIPT="${PWD}/${TMP_SCRIPT_NAME}"

cat > "$TMP_SCRIPT" <<EOF
#!/usr/bin/env bash

echo "Starting QE ${PROGRAM} job \$SLURM_JOB_ID at \$(date)"
echo "SLURM_SUBMIT_DIR: \$SLURM_SUBMIT_DIR"
echo "Running on node(s): \$SLURM_NODELIST"
echo "QE input: ${INPUT_FILE}"
echo "Requested MPI processes: \$SLURM_NTASKS"
ulimit -s unlimited

export PATH=/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin:/home/liqh/soft/QE/qe-7.5/bin
export LD_LIBRARY_PATH=/lib64:/usr/lib64:/usr/local/lib64:/home/liqh/soft/QE/qe-7.5/lib
if ! source /home/liqh/soft/QE/env.sh; then
    echo "Error: Failed to load the Quantum ESPRESSO environment." >&2
    exit 1
fi
export OMP_NUM_THREADS=1

cd ${INPUT_DIR_Q} || exit 1
${RUN_COMMAND}
STATUS=\$?
echo "QE ${PROGRAM} job \$SLURM_JOB_ID finished with status \$STATUS at \$(date)"
exit \$STATUS
EOF

chmod 700 "$TMP_SCRIPT"
if ! bash -n "$TMP_SCRIPT"; then
    echo "Error: Generated Slurm script has a syntax error." >&2
    exit 1
fi

echo "Input         : $INPUT_FILE"
echo "QE program    : $PROGRAM"
echo "QE output     : $INPUT_DIR/$OUTPUT_FILE"
echo "QE error      : $INPUT_DIR/$ERROR_FILE"
echo "Queue         : $QUEUE"
echo "Nodes         : $NODES"
echo "MPI processes : $MPI_PROCESSES"
echo "Input mode    : $INPUT_MODE"

if ! command -v sbatch >/dev/null 2>&1 || ! command -v flock >/dev/null 2>&1; then
    echo "Error: sbatch and flock are required." >&2
    exit 1
fi
if ! SBATCH_OUTPUT=$(sbatch --parsable --job-name="$JOB_NAME" --nodes="$NODES" --ntasks="$MPI_PROCESSES" --partition="$QUEUE" "$TMP_SCRIPT"); then
    echo "Error: QE job submission failed." >&2
    exit 1
fi

JOB_ID=${SBATCH_OUTPUT%%;*}
[[ -n "$JOB_ID" ]] || { echo "Error: Slurm returned no Job ID." >&2; exit 1; }
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
BATCH_LOG="${INPUT_DIR}/Batch.log"
RECORD="${TIMESTAMP} | QE | job_id=${JOB_ID} | job=${JOB_NAME} | partition=${QUEUE} | nodes=${NODES} | processes=${MPI_PROCESSES} | directory=${INPUT_DIR} | input=${INPUT_NAME} | output=${OUTPUT_FILE}"
if ! (flock -x 9; printf '%s\n' "$RECORD" >&9) 9>> "$BATCH_LOG"; then
    echo "警告：作业已提交，但写入 Batch.log 失败。Job ID: ${JOB_ID}" >&2
fi
echo "Submitted batch job ${JOB_ID}"
