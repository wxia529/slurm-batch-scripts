#!/usr/bin/env bash
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage: myneb.sh <input_file> [nodes]

Submit Quantum ESPRESSO neb.x using Slurm.
Partition: p1
Nodes: positive integer; default: 1
MPI processes per node: 40

Output: <input_stem>.log in the input directory.
Options: -h, --help    Show this help and exit without submitting a job.

Example: myneb.sh input.in
EOF
    exit 0
fi

exec "$(dirname -- "${BASH_SOURCE[0]}")/myqe-core.sh" neb.x neb.err myneb-tmp "$@"
