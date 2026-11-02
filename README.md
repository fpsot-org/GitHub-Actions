# FPSOT GitHub Actions

Shared CI for FPSOT repositories: reusable workflows and the small tools they run.

## Reusable workflows

Call them from a spec repo and pin them to the major tag `@v0`.

| Workflow | Inputs | What it checks |
|---|---|---|
| `spec-check.yml` | `prefix` (required), `strict` (false), `working-directory` (`.`), `tools-ref` (`v0`) | Renders `spec/` and `docs/` with Asciidoctor, checks every link, checks requirement IDs (`reqcheck`), checks English/French page parity (`langparity`), and checks the prose (`ProseLint.java`). |
| `pr-title.yml` | none | The pull request title follows Conventional Commits 1.0.0. The caller job must grant `pull-requests: read`. |
| `diagrams.yml` | `working-directory` (`.`) | Renders `diagrams/**/*.puml` with a pinned PlantUML and fails when a committed SVG is missing or out of date. The rendered SVGs are in the `diagrams-svg` artifact: commit those, because fonts differ between machines. |
| `signed-commits.yml` | `tools-ref` (`v0`) | On a pull request: GitHub verified the signature of every commit. The caller job must grant `pull-requests: read`. |
| `spec-release.yml` | `prefix` (required), `working-directory` (`.`), `tools-ref` (`v0`) | On a release tag: the tag is an annotated `vX.Y.Z` whose signature GitHub verified, then `spec-check` runs in strict mode. |

## Tools

- `tools/cmd/reqcheck`: requirement IDs are defined once per language and every citation exists.
- `tools/cmd/langparity`: every English page has a translated French page.
- `tools/prose-lint/ProseLint.java`: readability checks for Markdown and AsciiDoc, in English and French.

## Rules for this repository

- Every third-party action is pinned by its full commit SHA, with the version in a comment.
  `scripts/check-pinned.sh` enforces this.
- Callers pin the reusable workflows to the major tag, for example `@v0`.

## Licence

Apache-2.0. See `LICENSE` and `NOTICE`.
