#!/usr/bin/env bash
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage: myq2r.sh <input_file> [nodes]

Submit Quantum ESPRESSO q2r.x using Slurm.
Partition: p1
Nodes: positive integer; default: 1
MPI processes per node: 48

Output: <input_stem>.log in the input directory.
Options: -h, --help    Show this help and exit without submitting a job.

Example: myq2r.sh input.in
EOF
    exit 0
fi

exec "$(dirname -- "${BASH_SOURCE[0]}")/myqe-core.sh" q2r.x q2r.err myq2r-tmp "$@"
