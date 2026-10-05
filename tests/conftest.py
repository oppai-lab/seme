"""Fixtures shared by the whole test suite."""

from pathlib import Path

import pytest


@pytest.fixture(scope="session")
def project_root() -> Path:
    """The repository root, resolved from this file rather than the working directory."""
    return Path(__file__).resolve().parent.parent
