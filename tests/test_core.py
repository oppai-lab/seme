"""Tests for the core module."""

import pytest

from seme import greet


def test_greet() -> None:
    assert greet("Python") == "Hello, Python!"


def test_greet_rejects_empty_name() -> None:
    with pytest.raises(ValueError, match="name must not be empty"):
        greet(" ")
