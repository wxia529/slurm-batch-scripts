#!/usr/bin/env bash
exec "$(dirname -- "${BASH_SOURCE[0]}")/myqe-core.sh" dos.x dos.err mydos-tmp "$@"
