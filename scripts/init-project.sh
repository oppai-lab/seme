#!/usr/bin/env bash
#
# One-shot bootstrap: turns a clone of the M.A.R.K. I scaffold into a new project.
# Personalizes every scaffold reference, drops the scaffold-only files, and removes itself.
# On any failure before the Git phase, the working tree is restored to its original state.

set -euo pipefail

readonly TEMPLATE_NAME="seme"
readonly TEMPLATE_PACKAGE_DIR="src/${TEMPLATE_NAME}"
readonly README_TEMPLATE="README.template.md"
readonly SCAFFOLD_ONLY_FILES=("tests/test_scaffold.py")

backup_tar=""
created_paths=()
is_git_repo=0
git_phase_started=0

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

info() {
  printf '%s\n' "$1"
}

cleanup() {
  local status=$?
  if [[ $status -ne 0 && $git_phase_started -eq 0 && -n "$backup_tar" && -f "$backup_tar" ]]; then
    printf 'Restoring the scaffold to its original state...\n' >&2
    local path
    for path in "${created_paths[@]+"${created_paths[@]}"}"; do
      rm -rf -- "$path"
    done
    tar -xf "$backup_tar" -C .
    # git mv stages its rename; drop it so the index matches the restored tree.
    if [[ $is_git_repo -eq 1 ]]; then
      git reset -q
    fi
  fi
  if [[ -n "$backup_tar" ]]; then
    rm -rf -- "$(dirname "$backup_tar")"
  fi
  return $status
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# ask VARIABLE "prompt" ["default"]
ask() {
  local variable=$1 prompt=$2 default=${3:-} reply
  if [[ -n "$default" ]]; then
    read -r -p "${prompt} [${default}]: " reply
    reply=${reply:-$default}
  else
    read -r -p "${prompt}: " reply
  fi
  printf -v "$variable" '%s' "$reply"
}

# confirm "prompt" -> 0 when the answer is yes
confirm() {
  local reply
  read -r -p "$1 [Y/n]: " reply
  [[ -z "$reply" || "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# escape_toml VARIABLE -> escapes backslashes and double quotes for a TOML basic string
escape_toml() {
  local variable=$1 value=${!1}
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  printf -v "$variable" '%s' "$value"
}

# substitute FILE 'perl expression' "what is being replaced"
# The expression must be a single Perl expression evaluating to the number of
# substitutions (chain several with "+"). When nothing matches the script aborts,
# instead of silently producing a half-initialized project.
substitute() {
  local file=$1 expression=$2 what=$3
  local temporary="${file}.init-tmp.$$"
  if perl -0pe "\$count += (${expression}); END { exit(\$count ? 0 : 3) }" -- "$file" >"$temporary"; then
    mv -- "$temporary" "$file"
  else
    rm -f -- "$temporary"
    fail "could not update ${what} in ${file}; run this script once, from an unmodified scaffold."
  fi
}

track_created() {
  created_paths+=("$1")
}

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------

if [[ ! -f pyproject.toml || ! -d "$TEMPLATE_PACKAGE_DIR" || ! -f "$README_TEMPLATE" ]]; then
  fail "run this script once, from an unmodified scaffold root."
fi

command -v uv >/dev/null 2>&1 || fail "uv is required: https://docs.astral.sh/uv/getting-started/installation/"
command -v perl >/dev/null 2>&1 || fail "perl is required."

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  is_git_repo=1
fi

# ---------------------------------------------------------------------------
# Questions
# ---------------------------------------------------------------------------

ask project_name "Python package name (for example: my_project)"
if [[ ! "$project_name" =~ ^[a-z][a-z0-9_]*$ ]]; then
  fail "the package name must start with a lowercase letter and contain only lowercase letters, digits, and underscores."
fi
if [[ -e "src/${project_name}" ]]; then
  fail "src/${project_name} already exists."
fi

ask project_type "Project type [library/application/internal]" "library"
case "$project_type" in
  library | application | internal) ;;
  *) fail "project type must be library, application, or internal." ;;
esac

ask project_description "Short project description" "A Python project."

default_author_name=$(git config --get user.name 2>/dev/null || true)
default_author_email=$(git config --get user.email 2>/dev/null || true)
ask author_name "Author name" "${default_author_name:-unknown}"
ask author_email "Author email (leave blank to skip)" "${default_author_email:-}"

default_python_version=$(tr -d '[:space:]' <.python-version 2>/dev/null || true)
ask python_version "Minimum Python version" "${default_python_version:-3.12}"
if [[ ! "$python_version" =~ ^3\.[0-9]+$ ]]; then
  fail "the Python version must look like 3.12."
fi

ask project_license "License [Apache-2.0/MIT/proprietary]" "Apache-2.0"
case "$project_license" in
  Apache-2.0 | MIT | proprietary) ;;
  *) fail "license must be Apache-2.0, MIT, or proprietary." ;;
esac

ask copyright_holder "Copyright holder" "${author_name:-unknown}"
copyright_year=$(date +%Y)

remote_url=""
reset_history=0
if [[ $is_git_repo -eq 1 ]]; then
  ask remote_url "Git remote URL for origin (leave blank to skip)"
  if confirm "Reset Git history and start the new project from a single initial commit?"; then
    reset_history=1
  fi
else
  info "Not a Git repository: skipping Git configuration."
fi

escape_toml project_description
escape_toml author_name
escape_toml author_email

# ---------------------------------------------------------------------------
# Backup
# ---------------------------------------------------------------------------

backup_dir=$(mktemp -d)
backup_tar="${backup_dir}/worktree.tar"
tar -cf "$backup_tar" --exclude=./.git --exclude=./.venv --exclude=./.direnv .

# ---------------------------------------------------------------------------
# pyproject.toml
# ---------------------------------------------------------------------------

# Package name: covers [project].name, hatch packages, isort, coverage and pytest options.
substitute pyproject.toml "s/\\b${TEMPLATE_NAME}\\b/${project_name}/g" "the package name"

PROJECT_DESCRIPTION="$project_description" \
  substitute pyproject.toml 's/^description = ".*"$/description = "$ENV{PROJECT_DESCRIPTION}"/m' "the description"

if [[ -n "$author_email" ]]; then
  authors_line="authors = [{ name = \"${author_name}\", email = \"${author_email}\" }]"
else
  authors_line="authors = [{ name = \"${author_name}\" }]"
fi
AUTHORS_LINE="$authors_line" \
  substitute pyproject.toml 's/^authors = \[.*\]$/$ENV{AUTHORS_LINE}/m' "the author"

substitute pyproject.toml "s/^requires-python = \".*\"\$/requires-python = \">=${python_version}\"/m" "requires-python"

# Ruff infers its target version from requires-python, so only ty needs the explicit value.
substitute pyproject.toml \
  "s/^(\\[tool\\.ty\\.environment\\]\\npython-version = )\".*\"\$/\${1}\"${python_version}\"/m" \
  "the ty Python version"

# The scaffold ships Apache-2.0; the new project picks its own, so neither the
# license text nor the copyright line is ever inherited by accident.
case "$project_license" in
  Apache-2.0)
    COPYRIGHT_LINE="   Copyright ${copyright_year} ${copyright_holder}" \
      substitute LICENSE 's/^   Copyright \d{4} .*$/$ENV{COPYRIGHT_LINE}/m' "the copyright notice"
    ;;
  MIT)
    cat >LICENSE <<EOF
MIT License

Copyright (c) ${copyright_year} ${copyright_holder}

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
    ;;
  proprietary)
    rm -f LICENSE
    ;;
esac

if [[ "$project_license" == "proprietary" ]]; then
  # LicenseRef- is the SPDX form for a license with no public identifier, and the
  # Private classifier makes an accidental PyPI upload fail server-side.
  substitute pyproject.toml \
    's/^license = ".*"$/license = "LicenseRef-Proprietary"\nclassifiers = ["Private :: Do Not Upload"]/m' \
    "the license metadata"
else
  substitute pyproject.toml "s/^license = \".*\"\$/license = \"${project_license}\"/m" "the license metadata"
fi

if [[ "$project_type" == "application" ]]; then
  SCRIPTS_BLOCK="[project.scripts]
${project_name} = \"${project_name}.__main__:main\"
" substitute pyproject.toml \
    's/^(dependencies = \[\]\n)/$1\n$ENV{SCRIPTS_BLOCK}/m' "the console script entry point"
fi

# ---------------------------------------------------------------------------
# Python version pin
# ---------------------------------------------------------------------------

printf '%s\n' "$python_version" >.python-version

# ---------------------------------------------------------------------------
# Package and tests
# ---------------------------------------------------------------------------

substitute "${TEMPLATE_PACKAGE_DIR}/__init__.py" "s/\\b${TEMPLATE_NAME}\\b/${project_name}/g" "the package import"
substitute tests/test_core.py "s/\\b${TEMPLATE_NAME}\\b/${project_name}/g" "the package import"

if [[ $is_git_repo -eq 1 ]] && git ls-files --error-unmatch "$TEMPLATE_PACKAGE_DIR" >/dev/null 2>&1; then
  git mv "$TEMPLATE_PACKAGE_DIR" "src/${project_name}"
else
  mv "$TEMPLATE_PACKAGE_DIR" "src/${project_name}"
fi
track_created "src/${project_name}"

# Both library and internal packages get imported by other projects, so both ship the
# typing marker. An application is consumed as a command, not as an import.
if [[ "$project_type" != "application" ]]; then
  touch "src/${project_name}/py.typed"
fi

case "$project_type" in
  library) ;;
  application)
    cat >"src/${project_name}/__main__.py" <<EOF
"""Command-line entry point."""

from collections.abc import Sequence

from ${project_name} import greet


def main(argv: Sequence[str] | None = None) -> int:
    """Run the application."""
    arguments = list(argv) if argv is not None else []
    name = arguments[0] if arguments else "World"
    print(greet(name))  # noqa: T201
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
EOF
    cat >tests/test_cli.py <<EOF
"""Tests for the command-line entry point."""

import pytest

from ${project_name}.__main__ import main


def test_main_uses_argument(capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["Python"]) == 0
    assert capsys.readouterr().out == "Hello, Python!\\n"


def test_main_uses_default_name(capsys: pytest.CaptureFixture[str]) -> None:
    assert main() == 0
    assert capsys.readouterr().out == "Hello, World!\\n"
EOF
    track_created tests/test_cli.py
    ;;
  internal) ;;
esac

# ---------------------------------------------------------------------------
# README
# ---------------------------------------------------------------------------

if [[ "$project_license" == "proprietary" ]]; then
  license_notice="Copyright ${copyright_year} ${copyright_holder}. All rights reserved."
else
  license_notice="Copyright ${copyright_year} ${copyright_holder}. Distributed under the
[${project_license}](LICENSE) license."
fi

PROJECT_NAME="$project_name" \
PROJECT_DESCRIPTION="$project_description" \
PYTHON_VERSION="$python_version" \
LICENSE_NOTICE="$license_notice" \
  substitute "$README_TEMPLATE" \
  's/__PROJECT_NAME__/$ENV{PROJECT_NAME}/g + s/__PROJECT_DESCRIPTION__/$ENV{PROJECT_DESCRIPTION}/g + s/__PYTHON_VERSION__/$ENV{PYTHON_VERSION}/g + s/__LICENSE_NOTICE__/$ENV{LICENSE_NOTICE}/g' \
  "the README placeholders"

if [[ "$project_type" == "application" ]]; then
  # Quoted heredoc: the fenced code block contains backticks that must not be
  # interpreted as command substitution.
  cat >>"$README_TEMPLATE" <<'EOF'

## Command-line interface

The package installs a `__PROJECT_NAME__` console script:

```bash
uv run __PROJECT_NAME__ Python
```
EOF
  PROJECT_NAME="$project_name" \
    substitute "$README_TEMPLATE" 's/__PROJECT_NAME__/$ENV{PROJECT_NAME}/g' "the CLI section placeholders"
fi

mv "$README_TEMPLATE" README.md

# ---------------------------------------------------------------------------
# Drop the scaffold-only pieces
# ---------------------------------------------------------------------------

substitute Makefile \
  's/^init-project:.*\n(\t.*\n)+\n//m + s/^(\.PHONY: help) init-project/$1/m' \
  "the init-project target"

for scaffold_file in "${SCAFFOLD_ONLY_FILES[@]}"; do
  rm -f -- "$scaffold_file"
done

uv lock

# ---------------------------------------------------------------------------
# Git
# ---------------------------------------------------------------------------

git_phase_started=1
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
rm -- "$0"
rmdir "$script_dir" 2>/dev/null || true

if [[ $is_git_repo -eq 1 ]]; then
  if [[ $reset_history -eq 1 ]]; then
    rm -rf .git
    git init -q -b main
    git add -A
    git -c core.hooksPath=/dev/null commit -q -m "Initial commit"
  else
    git add -A
  fi
  if [[ -n "$remote_url" ]]; then
    if git remote get-url origin >/dev/null 2>&1; then
      git remote set-url origin "$remote_url"
    else
      git remote add origin "$remote_url"
    fi
  fi
fi

printf '\nInitialized %s project %s.\n' "$project_type" "$project_name"
printf 'Next step: make setup\n'
