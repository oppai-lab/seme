# __PROJECT_NAME__

__PROJECT_DESCRIPTION__

__LICENSE_NOTICE__

## Requirements

- Python __PYTHON_VERSION__ or later
- [uv](https://docs.astral.sh/uv/getting-started/installation/)
- `make`
- [direnv](https://direnv.net/) (optional, recommended)

## Quick start

```bash
make setup
```

This command creates `.venv`, synchronizes all dependencies from `uv.lock`, and installs the
Git `pre-commit` and `pre-push` hooks.

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

## Layout

The `src/` structure prevents tests from accidentally importing code from the working
directory instead of the installed package.

- `src/__PROJECT_NAME__/` - package source
- `tests/` - pytest suite

All tool configuration lives in `pyproject.toml`.
