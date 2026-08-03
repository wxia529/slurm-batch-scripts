#!/usr/bin/env bash
exec "$(dirname -- "${BASH_SOURCE[0]}")/myqe-core.sh" neb.x neb.err "$@"
