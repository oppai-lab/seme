# SEME

**SEME — SEME is an Essential Modern Environment** — is a small, reusable scaffold for Python
packages, designed to provide a clean and sensible starting point without unnecessary complexity.

The environment and dependencies are managed entirely by [uv](https://docs.astral.sh/uv/).

## Requirements

- Python 3.12 or later
- [uv](https://docs.astral.sh/uv/getting-started/installation/)
- `make`
- [direnv](https://direnv.net/) (optional, recommended)

## Quick start

```bash
make setup
```

This command creates `.venv`, synchronizes all dependencies from `uv.lock`, and installs the
Git `pre-commit` and `pre-push` hooks. If the project is not yet a Git repository, run
`git init` first.

With direnv:

```bash
direnv allow
```

When first entering the directory, `.envrc` creates the virtual environment if it is missing,
adds it to `PATH`, and loads variables from `.env`. `.env` is local and ignored by Git;
`.env.example` documents shared variables without containing secrets.

## Commands

```bash
make help          # show all targets
make init-project  # customize the clone and remove the bootstrap script
make sync          # synchronize .venv from uv.lock
make lock          # refresh uv.lock
make lock-check    # verify uv.lock matches pyproject.toml
make audit         # report known vulnerabilities in the dependencies
make build         # generate wheel and source distribution
make format        # apply Ruff fixes and formatting
make format-check  # check formatting without making changes
make lint          # run Ruff linting
make typecheck     # run ty
make test          # run pytest
make test-fast     # run pytest, skipping the slow tests
make test-cov      # run pytest and enforce the coverage gate
make check         # format-check + lint + typecheck + test
```

The Git hooks run in two tiers:

- **pre-commit** - fast, file-scoped checks on the staged files only: Ruff lint and format,
  plus hygiene hooks (trailing whitespace, final newline, line endings, TOML/YAML syntax,
  merge markers, oversized files, private keys). A couple of seconds.
- **pre-push** - the full `make check` gate, identical to the one you run locally.

`make check` stays the single source of truth for the quality gate, so there is no difference
between local checks and what blocks a push. Before committing, use `make format` to apply
fixes to the whole tree at once.

To run a command directly in the environment:

```bash
uv run python
uv run pytest tests/test_core.py
```

## Dependencies

Runtime dependencies belong in `[project].dependencies`:

```bash
uv add requests
```

Development tools belong to the `dev` group and are not included in the package:

```bash
uv add --dev pytest
uv remove --dev pytest
```

After each change, uv updates both `pyproject.toml` and `uv.lock`. The lockfile must be
versioned to make installations and CI reproducible: `make check` starts with `uv lock --check`,
so the two files can never drift apart unnoticed.

## Tool configuration

- **Ruff**: formatter and linter with rules for real errors, security, modernization, imports,
  performance, logging, pytest, and good practices. Tests allow `assert`.
- **ty**: analyzes `src/` and treats every active diagnostic as an error. Ruff infers its
  target version from `requires-python`, so only ty needs the version spelled out.
- **pytest**: unknown markers and configurations are errors, so every marker is registered
  in `[tool.pytest.ini_options].markers`. The `slow` marker is applied to the scaffold
  end-to-end tests; `make test-fast` skips them for a sub-second inner loop. The 100% branch coverage gate
  lives in `make test-cov`, not in `addopts`, so running a single test file stays useful.
- **uv audit**: `make audit` reports known vulnerabilities. It is deliberately kept out of
  `make check`: a newly published advisory would otherwise fail commits on code you have
  not touched. Run it periodically, or wire it into a scheduled CI job.
- **pre-commit**: fast file-scoped hooks on commit, the full `make check` gate on push.
  Ruff runs through `uv run`, so the version in `uv.lock` is the only one in play.

All Python configuration lives in `pyproject.toml`.

## Adapting the scaffold

Immediately after cloning, initialize the new project:

```bash
make init-project
```

The script is interactive and asks for:

| Question | Default |
| --- | --- |
| Importable Python package name (for example, `my_project`) | none, required |
| Project type (`library`, `application`, `internal`) | `library` |
| Short project description | `A Python project.` |
| Author name and email | taken from `git config user.name` / `user.email` |
| Minimum Python version | the value in `.python-version` |
| License (`Apache-2.0`, `MIT`, `proprietary`) | `Apache-2.0` |
| Copyright holder | the author name |
| Git remote URL for `origin` | none, skipped when blank |
| Whether to reset the Git history | yes |

| Type | Generated configuration |
| --- | --- |
| `library` | Distributable package with `py.typed`, to declare type checker support to consumers. |
| `application` | CLI entry point in `[project.scripts]`, `__main__.py`, and tests for command-line behavior. |
| `internal` | Importable package with `py.typed` but no CLI and no publishing intent, suitable for internally shared code. |

It then renames `src/seme` with `git mv`, rewrites every scaffold reference in
`pyproject.toml` and in the tests, propagates the Python version to `requires-python`,
`.python-version`, and ty, turns `README.template.md` into the new `README.md`, drops the
scaffold-only files (`scripts/`, `tests/test_scaffold.py`, the `init-project` target in the
`Makefile`), and refreshes `uv.lock`.

The license is never inherited. `Apache-2.0` keeps the text and rewrites only the copyright
line with the current year and the chosen holder; `MIT` replaces `LICENSE` entirely;
`proprietary` removes it, sets `license = "LicenseRef-Proprietary"`, and adds the
`Private :: Do Not Upload` classifier, which makes an accidental PyPI upload fail
server-side. In every case `[project].license` and the notice in the new `README.md` are
kept in step with the choice.

When you accept the history reset, the script replaces `.git` and commits everything as a
single `Initial commit`, so the new project starts from a clean tree with no scaffold history.
Declining it only stages the changes, leaving the commit to you. In both cases `origin` is
created or updated when a remote URL was given.

Every substitution is verified: if the scaffold has been modified and a replacement no longer
matches, the script aborts and restores the working tree to its original state rather than
leaving a half-initialized project behind. `tests/test_scaffold.py` covers this end to end,
generating all three project types in a temporary repository and running `make check` on the
result.

Once initialization is done, run `make setup`.

The `src/` structure prevents tests from accidentally importing code from the working
directory instead of the installed package.
