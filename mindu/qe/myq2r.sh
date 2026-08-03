#!/usr/bin/env bash
exec "$(dirname -- "${BASH_SOURCE[0]}")/myqe-core.sh" q2r.x q2r.err "$@"
