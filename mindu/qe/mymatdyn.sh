#!/usr/bin/env bash
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage: mymatdyn.sh <input_file> [queue] [nodes]

Submit Quantum ESPRESSO matdyn.x using Slurm.
Queue: s | small (default), c | community, h | highio
Nodes: positive integer; default: 1
MPI processes per node: 32

Output: <input_stem>.log in the input directory.
Options: -h, --help    Show this help and exit without submitting a job.

Example: mymatdyn.sh input.in
EOF
    exit 0
fi

exec "$(dirname -- "${BASH_SOURCE[0]}")/myqe-core.sh" matdyn.x matdyn.err mymatdyn-tmp "$@"
