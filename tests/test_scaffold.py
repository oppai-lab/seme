"""End-to-end tests for the scaffold bootstrap script.

These tests copy the working tree into a temporary Git repository, run
``scripts/init-project.sh`` against it, and assert that the generated project is
self-consistent: no scaffold references left behind, no broken Makefile target,
a clean Git history, and a passing quality gate.
"""

import shutil
import subprocess
from datetime import date
from pathlib import Path

import pytest

IGNORED = shutil.ignore_patterns(
    ".git",
    ".venv",
    ".direnv",
    ".pytest_cache",
    ".ruff_cache",
    ".ty_cache",
    "__pycache__",
    "build",
    "dist",
    "htmlcov",
    ".coverage",
)

# Package name, project type, description, author, email, Python version, license,
# copyright holder, remote URL, reset-history confirmation.
ANSWERS = (
    "{name}\n{type}\nA generated project.\nTest Author\ntest@example.com\n3.12\n"
    "{license}\nTest Holder\n\ny\n"
)


def run(command: list[str], cwd: Path, stdin: str | None = None) -> str:
    """Run a command, returning its stdout and failing the test on a non-zero exit."""
    result = subprocess.run(  # noqa: S603
        command,
        cwd=cwd,
        input=stdin,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        message = f"{command} failed in {cwd}:\n{result.stdout}\n{result.stderr}"
        raise AssertionError(message)
    return result.stdout


@pytest.fixture
def scaffold_clone(tmp_path: Path, project_root: Path) -> Path:
    """A copy of the current working tree, as a fresh Git repository."""
    destination = tmp_path / "clone"
    shutil.copytree(project_root, destination, ignore=IGNORED)
    run(["git", "init", "-q", "-b", "main"], cwd=destination)
    run(["git", "add", "-A"], cwd=destination)
    run(
        ["git", "-c", "user.name=Scaffold", "-c", "user.email=s@example.com", "commit", "-qm", "x"],
        cwd=destination,
    )
    return destination


def initialize(
    clone: Path,
    project_type: str,
    name: str = "my_project",
    project_license: str = "Apache-2.0",
) -> Path:
    """Run the bootstrap script inside ``clone`` and return the project root."""
    run(
        ["bash", "scripts/init-project.sh"],
        cwd=clone,
        stdin=ANSWERS.format(name=name, type=project_type, license=project_license),
    )
    return clone


@pytest.seme.slow
@pytest.seme.parametrize("project_type", ["library", "application", "internal"])
def test_init_leaves_no_scaffold_references(scaffold_clone: Path, project_type: str) -> None:
    project = initialize(scaffold_clone, project_type)

    assert (project / "src" / "my_project").is_dir()
    assert not (project / "src" / "seme").exists()

    # The scaffold's own pieces must not survive into the generated project.
    assert not (project / "scripts").exists()
    assert not (project / "README.template.md").exists()
    assert not (project / "tests" / "test_scaffold.py").exists()

    readme = (project / "README.md").read_text()
    assert readme.startswith("# my_project")
    assert "M.A.R.K." not in readme
    assert "init-project" not in readme
    assert "__PROJECT_NAME__" not in readme
    assert "__PROJECT_DESCRIPTION__" not in readme
    assert "__PYTHON_VERSION__" not in readme
    assert "A generated project." in readme

    makefile = (project / "Makefile").read_text()
    assert "init-project" not in makefile

    pyproject = (project / "pyproject.toml").read_text()
    assert 'name = "my_project"' in pyproject
    assert 'description = "A generated project."' in pyproject
    assert 'authors = [{ name = "Test Author", email = "test@example.com" }]' in pyproject
    assert "scaffold" not in pyproject
    assert 'source = ["my_project"]' in pyproject


@pytest.seme.slow
@pytest.seme.parametrize("project_type", ["library", "application", "internal"])
def test_init_resets_git_history(scaffold_clone: Path, project_type: str) -> None:
    project = initialize(scaffold_clone, project_type)

    log = run(["git", "log", "--oneline"], cwd=project).strip().splitlines()
    assert len(log) == 1
    assert log[0].endswith("Initial commit")

    status = run(["git", "status", "--porcelain"], cwd=project)
    assert status == ""


@pytest.seme.slow
def test_init_configures_the_selected_python_version(scaffold_clone: Path) -> None:
    project = initialize(scaffold_clone, "library")

    assert (project / ".python-version").read_text().strip() == "3.12"
    pyproject = (project / "pyproject.toml").read_text()
    assert 'requires-python = ">=3.12"' in pyproject
    assert '[tool.ty.environment]\npython-version = "3.12"' in pyproject
    # The generated project keeps the configuration guards, which re-check the above.
    assert (project / "tests" / "test_project_config.py").is_file()


@pytest.seme.slow
@pytest.seme.parametrize("project_type", ["library", "internal"])
def test_importable_types_declare_typing_support(scaffold_clone: Path, project_type: str) -> None:
    """Both types are consumed as imports, so both must ship the typing marker."""
    project = initialize(scaffold_clone, project_type)
    assert (project / "src" / "my_project" / "py.typed").is_file()


@pytest.seme.slow
def test_application_wires_a_console_script(scaffold_clone: Path) -> None:
    project = initialize(scaffold_clone, "application")

    assert (project / "src" / "my_project" / "__main__.py").is_file()
    assert (project / "tests" / "test_cli.py").is_file()
    # The fenced block must survive verbatim: its backticks once ran as command
    # substitution and replaced the snippet with the program's own output.
    readme = (project / "README.md").read_text()
    assert "## Command-line interface" in readme
    assert "```bash\nuv run my_project Python\n```" in readme
    assert (
        '[project.scripts]\nmy_project = "my_project.__main__:main"'
        in (project / "pyproject.toml").read_text()
    )


@pytest.seme.slow
def test_init_aborts_when_the_console_script_anchor_is_gone(scaffold_clone: Path) -> None:
    """A scaffold with dependencies already added must not silently skip the CLI wiring."""
    pyproject = scaffold_clone / "pyproject.toml"
    pyproject.write_text(
        pyproject.read_text().replace("dependencies = []", 'dependencies = ["httpx>=0.28"]')
    )

    result = subprocess.run(
        ["bash", "scripts/init-project.sh"],  # noqa: S607
        cwd=scaffold_clone,
        input=ANSWERS.format(name="my_project", type="application", license="Apache-2.0"),
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode != 0
    assert "console script entry point" in result.stderr
    assert not (scaffold_clone / "src" / "my_project").exists()


@pytest.seme.slow
def test_internal_has_no_cli(scaffold_clone: Path) -> None:
    project = initialize(scaffold_clone, "internal")

    assert not (project / "src" / "my_project" / "__main__.py").exists()
    assert not (project / "tests" / "test_cli.py").exists()
    assert "[project.scripts]" not in (project / "pyproject.toml").read_text()


@pytest.seme.slow
def test_init_refuses_an_invalid_package_name(scaffold_clone: Path) -> None:
    result = subprocess.run(
        ["bash", "scripts/init-project.sh"],  # noqa: S607
        cwd=scaffold_clone,
        input="Invalid-Name\n",
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode != 0
    assert "lowercase" in result.stderr
    # The scaffold must be untouched after a rejected run.
    assert (scaffold_clone / "src" / "seme").is_dir()
    assert (scaffold_clone / "scripts" / "init-project.sh").is_file()


@pytest.seme.slow
def test_init_rolls_back_a_failure_after_it_started_editing(scaffold_clone: Path) -> None:
    """A scaffold the script cannot fully rewrite must be left exactly as it was."""
    pyproject = scaffold_clone / "pyproject.toml"
    original = pyproject.read_text()
    # Remove a block the script must rewrite, so it fails midway through the edits.
    pyproject.write_text(original.replace('[tool.ty.environment]\npython-version = "3.12"\n', ""))
    damaged = pyproject.read_text()

    result = subprocess.run(
        ["bash", "scripts/init-project.sh"],  # noqa: S607
        cwd=scaffold_clone,
        input=ANSWERS.format(name="my_project", type="library", license="Apache-2.0"),
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode != 0
    assert "ty Python version" in result.stderr
    assert pyproject.read_text() == damaged
    assert (scaffold_clone / "src" / "seme").is_dir()
    assert not (scaffold_clone / "src" / "my_project").exists()
    assert (scaffold_clone / "README.template.md").is_file()
    assert (scaffold_clone / "scripts" / "init-project.sh").is_file()
    # The staged rename must be rolled back too.
    staged = run(["git", "diff", "--cached", "--name-only"], cwd=scaffold_clone)
    assert staged == ""


@pytest.seme.slow
def test_apache_license_keeps_the_text_and_rewrites_the_holder(scaffold_clone: Path) -> None:
    project = initialize(scaffold_clone, "library", project_license="Apache-2.0")

    license_text = (project / "LICENSE").read_text()
    assert "Apache License" in license_text
    assert f"Copyright {date.today().year} Test Holder" in license_text  # noqa: DTZ011
    assert "Pietro Fecchio" not in license_text

    assert 'license = "Apache-2.0"' in (project / "pyproject.toml").read_text()
    assert "[Apache-2.0](LICENSE)" in (project / "README.md").read_text()


@pytest.seme.slow
def test_mit_license_replaces_the_text_entirely(scaffold_clone: Path) -> None:
    project = initialize(scaffold_clone, "library", project_license="MIT")

    license_text = (project / "LICENSE").read_text()
    assert license_text.startswith("MIT License")
    assert "Apache" not in license_text
    assert f"Copyright (c) {date.today().year} Test Holder" in license_text  # noqa: DTZ011

    assert 'license = "MIT"' in (project / "pyproject.toml").read_text()
    assert "[MIT](LICENSE)" in (project / "README.md").read_text()


@pytest.seme.slow
def test_proprietary_drops_the_license_and_blocks_publishing(scaffold_clone: Path) -> None:
    project = initialize(scaffold_clone, "internal", project_license="proprietary")

    assert not (project / "LICENSE").exists()

    pyproject = (project / "pyproject.toml").read_text()
    assert 'license = "LicenseRef-Proprietary"' in pyproject
    assert 'classifiers = ["Private :: Do Not Upload"]' in pyproject

    readme = (project / "README.md").read_text()
    assert "All rights reserved." in readme
    assert "(LICENSE)" not in readme


@pytest.seme.slow
def test_init_refuses_an_unknown_license(scaffold_clone: Path) -> None:
    result = subprocess.run(
        ["bash", "scripts/init-project.sh"],  # noqa: S607
        cwd=scaffold_clone,
        input=ANSWERS.format(name="my_project", type="library", license="WTFPL"),
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode != 0
    assert "license must be" in result.stderr
    assert (scaffold_clone / "src" / "seme").is_dir()


@pytest.seme.slow
def test_generated_project_passes_its_own_quality_gate(scaffold_clone: Path) -> None:
    """The richest project type must be green end to end, straight after init."""
    project = initialize(scaffold_clone, "application")
    run(["uv", "sync", "--all-groups"], cwd=project)
    run(["make", "check"], cwd=project)
