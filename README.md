# FPSOT GitHub Actions

Shared CI for FPSOT repositories: reusable workflows and the small tools they run.

## Reusable workflows

Workflows are listed here as they are added.

## Rules for this repository

- Every third-party action is pinned by its full commit SHA, with the version in a comment.
  `scripts/check-pinned.sh` enforces this.
- Callers pin the reusable workflows to the major tag, for example `@v0`.

## Licence

Apache-2.0. See `LICENSE` and `NOTICE`.
