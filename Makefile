UV := uv

.DEFAULT_GOAL := help

.PHONY: help init-project setup install-hooks sync lock lock-check audit build format format-check lint typecheck test test-fast test-cov check clean

help: ## Show available commands
	@awk 'BEGIN {FS = ":.*## "; printf "Usage: make <target>\n\nTargets:\n"} /^[a-zA-Z_-]+:.*## / {printf "  %-14s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init-project: ## Personalize the cloned scaffold, then remove the bootstrap script
	bash scripts/init-project.sh

setup: sync install-hooks ## Create the environment and install Git hooks

install-hooks: ## Install pre-commit and pre-push hooks
	$(UV) run pre-commit install

sync: ## Synchronize .venv from uv.lock
	$(UV) sync --all-groups

lock: ## Refresh uv.lock
	$(UV) lock

lock-check: ## Verify uv.lock is in sync with pyproject.toml
	$(UV) lock --check

audit: ## Report known vulnerabilities in the dependencies
	$(UV) audit --preview-features audit-command

build: ## Build the Python distribution
	$(UV) build

format: ## Format source and test files
	$(UV) run ruff check --fix .
	$(UV) run ruff format .

format-check: ## Check formatting without changing files
	$(UV) run ruff format --check .

lint: ## Run Ruff linting
	$(UV) run ruff check .

typecheck: ## Run ty static type checking
	$(UV) run ty check

test: ## Run tests
	$(UV) run pytest

test-fast: ## Run tests, skipping the ones marked slow
	$(UV) run pytest -m "not slow"

test-cov: ## Run tests and enforce the coverage gate
	$(UV) run pytest --cov --cov-report=term-missing --cov-fail-under=100

check: lock-check format-check lint typecheck test-cov ## Run the same checks as the Git hooks

clean: ## Remove generated caches and build artifacts
	rm -rf .coverage coverage.xml htmlcov .pytest_cache .ruff_cache .ty_cache build dist
	find src tests -type d -name __pycache__ -prune -exec rm -rf {} +
	find src -type d -name '*.egg-info' -prune -exec rm -rf {} +
