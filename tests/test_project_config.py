"""Guards on project configuration that no other tool enforces.

The minimum Python version is necessarily declared in three places, each read by a
different tool: ``requires-python`` by the build backend and uv, ``.python-version``
by uv when creating the environment, and ``[tool.ty.environment]`` by ty, which
resolves its target from the active interpreter rather than from ``requires-python``.
Nothing makes them agree, so this test does.
"""

import tomllib
from pathlib import Path
from typing import Any

import pytest


@pytest.fixture(scope="session")
def pyproject(project_root: Path) -> dict[str, Any]:
    """The parsed ``pyproject.toml``."""
    return tomllib.loads((project_root / "pyproject.toml").read_text())


def test_the_python_version_is_declared_consistently(
    pyproject: dict[str, Any], project_root: Path
) -> None:
    pinned = (project_root / ".python-version").read_text().strip()

    assert pyproject["project"]["requires-python"] == f">={pinned}"
    assert pyproject["tool"]["ty"]["environment"]["python-version"] == pinned


def test_ruff_does_not_pin_a_redundant_target_version(pyproject: dict[str, Any]) -> None:
    """Ruff derives its target from ``requires-python``; a second pin can only drift."""
    assert "target-version" not in pyproject["tool"]["ruff"]


def test_every_ignored_lint_rule_belongs_to_a_selected_family(pyproject: dict[str, Any]) -> None:
    """An ignore for an unselected family is dead configuration."""
    lint = pyproject["tool"]["ruff"]["lint"]
    selected = tuple(lint["select"])

    for rule in lint["ignore"]:
        assert rule.startswith(selected), f"{rule} is ignored but its family is not selected"


def test_the_coverage_gate_is_not_in_addopts(pyproject: dict[str, Any]) -> None:
    """It lives in ``make test-cov``, so running a single test file stays useful."""
    addopts = pyproject["tool"]["pytest"]["ini_options"]["addopts"]

    assert not any(option.startswith("--cov") for option in addopts)
