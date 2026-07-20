#!/usr/bin/env bash

# 使用 source ~/soft/slurm-batchs/env.sh 加载提交脚本命令。

SLURM_BATCHS_ROOT="${SLURM_BATCHS_HOME:-${HOME}/soft/slurm-batchs}"

if [[ ! -d "$SLURM_BATCHS_ROOT" ]]; then
    echo "Error: Slurm batch scripts directory does not exist: $SLURM_BATCHS_ROOT" >&2
    return 1 2>/dev/null || exit 1
fi

for SLURM_BATCHS_DIR in "$SLURM_BATCHS_ROOT"/*; do
    [[ -d "$SLURM_BATCHS_DIR" ]] || continue

    SLURM_BATCHS_HAS_COMMAND=false
    for SLURM_BATCHS_FILE in "$SLURM_BATCHS_DIR"/*; do
        if [[ -f "$SLURM_BATCHS_FILE" && -x "$SLURM_BATCHS_FILE" ]]; then
            SLURM_BATCHS_HAS_COMMAND=true
            break
        fi
    done

    [[ "$SLURM_BATCHS_HAS_COMMAND" == true ]] || continue

    case ":${PATH:-}:" in
        *":${SLURM_BATCHS_DIR}:"*) ;;
        *) PATH="${SLURM_BATCHS_DIR}${PATH:+:${PATH}}" ;;
    esac
done

export PATH
unset SLURM_BATCHS_ROOT SLURM_BATCHS_DIR SLURM_BATCHS_FILE SLURM_BATCHS_HAS_COMMAND
