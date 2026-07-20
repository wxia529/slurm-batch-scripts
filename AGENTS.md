# Repository Guidelines

## Project Structure & Module Organization

Cluster-specific submission scripts live under `mindu/` and `para-amd/`, grouped by software (`gaussian/`, `cp2k/`, `vasp/`, and `orca/`). Top-level `deploy.sh` installs the selected cluster into `~/soft/slurm-batchs`; `env.sh` discovers deployed command directories and adds them to `PATH`.

`docs/` is the only documentation source. Cluster and software pages belong in `docs/clusters/<cluster>/`. Do not add duplicate READMEs beside scripts: deployment maps documentation pages to target `README.md` files. MkDocs configuration is in `mkdocs.yml`, and Pages automation is in `.github/workflows/docs.yml`.

## Build, Test, and Development Commands

- `bash -n deploy.sh env.sh && find mindu para-amd -type f -name '*.sh' -print0 | xargs -0 -r bash -n` recursively checks shell syntax without submitting jobs.
- `mkdocs serve` starts a local documentation preview after installing `requirements-docs.txt`.
- `mkdocs build --strict` builds documentation and treats warnings as failures.
- `./deploy.sh mindu` or `./deploy.sh para-amd` deploys one cluster. For isolated testing, set `SLURM_BATCHS_TARGET` to a temporary directory.
- `git diff --check` detects whitespace errors before committing.

Do not run real `sbatch` tests unless explicitly authorized on the target cluster. Mock `sbatch --parsable` when testing Job ID handling and `Batch.log` output locally.

## Coding Style & Naming Conventions

Use Bash with `#!/usr/bin/env bash`, four-space indentation, uppercase configuration variables, quoted expansions, and `[[ ... ]]` conditionals. Submission scripts follow `my<software>.sh`, such as `mycp2k.sh`. Keep cluster paths and resource counts explicit; do not silently inherit software environments. Changes to script behavior must update the matching page under `docs/clusters/`.

When adding a cluster or software, also update `deploy.sh` (`MANAGED_FILES` and source resolution), the `mkdocs.yml` navigation, and Workflow path filters when documentation inputs change.

## Testing Guidelines

There is no standalone test framework. At minimum, run Bash syntax checks, validate invalid arguments, simulate successful and failed submissions, and verify concurrent `Batch.log` appends remain complete. Deployment tests must confirm unrelated user files are unchanged.

## Commit & Pull Request Guidelines

Commit subjects and bodies must be written in English. Use Conventional Commit-style prefixes, for example: `feat: add para-amd VASP submission script`. Keep commits focused. Pull requests should identify the cluster and software, describe behavior or default changes, list tests performed, and state whether users must redeploy. Include screenshots only for documentation-site visual changes.

## Safety & Configuration

Never commit credentials or private calculation data. Deployment must modify only explicitly managed project files; never add broad deletion, recursive permission changes, or automatic edits to user shell configuration.
