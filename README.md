# FPSOT GitHub Actions

Shared CI for FPSOT repositories: reusable workflows and the small tools they run.

## Reusable workflows

Call them from a spec repo and pin them to the major tag `@v0`.

| Workflow | Inputs | What it checks |
|---|---|---|
| `spec-check.yml` | `prefix` (required), `strict` (false), `working-directory` (`.`), `tools-ref` (`v0`), `writing-ref`, `doc-ref`, `termbase-file`, `model-file`, `doc-rules` (false), `contributing-url` | Generates the term attributes, glossaries and jurisdiction pages (`scripts/spec-generate.sh`), renders `spec/` and `docs/` with each page's version and date (`scripts/spec-render.sh`), builds the book as tagged PDF and checks it with veraPDF (PDF/UA-1 and PDF/A-2b), checks every link (except iso.org, LégisQuébec, CanLII, merriam-webster.com and www.canada.ca, which refuse automated readers; a throttled 429 answer counts as reachable), requirement IDs, English/French parity and the prose. With `doc-rules`, also runs `doccheck`. A spec repo opts in to newer checks with a root file `.fpsot-checks`, one word per line: `references` (with `doc-rules`: each page lists its outside links under References, each RFC named links to it, each code block names its language) and `us-spelling` (the English prose check flags Canadian and British spellings). The term base and the jurisdiction model come from the highest `v0` tag of `fpsot-spec-writing` and `fpsot-spec-doc` unless a ref is given. |
| `pr-title.yml` | none | The pull request title follows Conventional Commits 1.0.0. The caller job must grant `pull-requests: read`. |
| `diagrams.yml` | `working-directory` (`.`) | Renders `diagrams/**/*.puml` with a pinned PlantUML and fails when a committed SVG is missing or out of date. The rendered SVGs are in the `diagrams-svg` artifact: commit those, because fonts differ between machines. |
| `signed-commits.yml` | `tools-ref` (`v0`) | On a pull request: GitHub verified the signature of every commit. The caller job must grant `pull-requests: read`. |
| `spec-release.yml` | `prefix` (required), `working-directory` (`.`), `tools-ref` (`v0`), `writing-ref`, `doc-ref`, `doc-rules` (false) | On a release tag: the tag is an annotated `vX.Y.Z` whose signature GitHub verified, then `spec-check` runs in strict mode, then the GitHub release is created with the PDF books, then the site is told to rebuild through the fpsot-ci GitHub App. The caller job must grant `contents: write` and pass `secrets: inherit`; the org sets the variable `FPSOT_CI_APP_CLIENT_ID` and the secret `FPSOT_CI_APP_PRIVATE_KEY`. |
| `site-build.yml` | `tools-ref` (`v0`), `working-directory` (`.`), `builder-image` (pinned) | For the site repo: builds each spec listed in `data/specs.yml` in its own Roq build, in parallel, and the home pages in one more. Merges them, checks that the site makes no external requests, checks every link offline and uploads the GitHub Pages artifact. The builds run in the website builder image. |

## Tools

- `tools/cmd/reqcheck`: requirement IDs are defined once per language and every citation exists.
- `tools/cmd/langparity`: every English page has a translated French page.
- `tools/prose-lint/ProseLint.java`: readability checks for Markdown and AsciiDoc, in English and French.
- `tools/cmd/termgen`: writes the `{abbr-ID}`, `{abbr-ID-first}` and `{term-ID}` attributes and a glossary from the term base.
  It also checks that each page spells an abbreviation out before it uses it.
- `tools/cmd/jurisgen`: writes the comparison pages from `jurisdictions/` data.
  It flags rows that nobody checked in the last 12 months.
- `tools/cmd/doccheck`: checks the documentation rules, such as required files and a document history on each page.
- `tools/cmd/sitecollect`: turns one generated spec into content for the fpsot.org site.
  It places each page at its site URL and rewrites the links between pages to site URLs.
- `scripts/site-bundle.sh`: generates a spec checked out at a release tag and runs `sitecollect` on it.
- `scripts/notify-site.sh`: sends the `spec-released` dispatch to the site repo, and fails when the App credentials are not set.
- `scripts/site-build.sh`: the steps of `site-build.yml` (`specs`, `map`, `home`, `reduce`), for local runs too.
- `scripts/check-site-offline.sh`: a built site makes no request to another host and runs no script other than the theme toggle.
- `scripts/build-pdf.sh`: AsciiDoc book to tagged PDF/UA-1 and PDF/A-2b, through DocBook, pandoc and LibreOffice. It keeps the text alternative of each image and names each link, which PDF/UA-1 requires.
- `scripts/resolve-major-tag.sh` and `scripts/fetch-spec-file.sh`: take a file from another spec at its highest `v0` tag.

## Rules for this repository

- Every third-party action is pinned by its full commit SHA, with the version in a comment.
  `scripts/check-pinned.sh` enforces this.
- Callers pin the reusable workflows to the major tag, for example `@v0`.

## Licence

Apache-2.0. See `LICENSE` and `NOTICE`.
