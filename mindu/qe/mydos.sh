#!/usr/bin/env bash
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage: mydos.sh <input_file> [queue] [nodes]

Submit Quantum ESPRESSO dos.x using Slurm.
Queue: s | small (default), c | community, h | highio
Nodes: positive integer; default: 1
MPI processes per node: 32

Output: <input_stem>.log in the input directory.
Options: -h, --help    Show this help and exit without submitting a job.

Example: mydos.sh input.in
EOF
    exit 0
fi

exec "$(dirname -- "${BASH_SOURCE[0]}")/myqe-core.sh" dos.x dos.err mydos-tmp "$@"
