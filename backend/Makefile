.PHONY: help install install-dev test lint format type-check clean build run docker-build docker-run pre-commit

# Default target
help:
	@echo "Novel Builder Backend - Development Commands"
	@echo ""
	@echo "Setup:"
	@echo "  install      Install production dependencies"
	@echo "  install-dev  Install development dependencies"
	@echo "  pre-commit   Install pre-commit hooks"
	@echo ""
	@echo "Development:"
	@echo "  run          Run development server"
	@echo "  format       Format code with ruff/black/isort"
	@echo "  lint         Run linting (ruff, pylint, bandit)"
	@echo "  type-check   Run type checking with mypy"
	@echo "  test         Run all tests"
	@echo "  test-cov     Run tests with coverage"
	@echo ""
	@echo "Docker:"
	@echo "  docker-build Build Docker image"
	@echo "  docker-run   Run with Docker"
	@echo "  docker-test  Run tests in Docker"
	@echo ""
	@echo "Maintenance:"
	@echo "  clean        Clean cache files"
	@echo "  check-all    Run all quality checks"

# Installation
install:
	pip install -e .

install-dev:
	pip install -e ".[dev]"
	pre-commit install

pre-commit:
	pre-commit install

# Development
run:
	uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Code quality
format:
	ruff format .
	ruff check . --fix
	isort .

lint:
	@echo "Running ruff..."
	ruff check .
	@echo "Running pylint..."
	pylint app/
	@echo "Running bandit..."
	bandit -r app/ -f custom

type-check:
	@echo "Running mypy..."
	mypy app/

# Testing
test:
	pytest

test-cov:
	pytest --cov=app --cov-report=html --cov-report=term-missing

test-watch:
	pytest-watch

# Quality check (all)
check-all: format lint type-check test
	@echo "All checks completed!"

# Docker
docker-build:
	docker build -t novel-backend .

docker-run:
	docker run -p 8000:8000 --env-file .env novel-backend

# Cleanup
clean:
	find . -type d -name "__pycache__" -exec rm -rf {} +
	find . -type d -name "*.egg-info" -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete
	find . -type f -name "*.pyo" -delete
	find . -type f -name "*.pyd" -delete
	find . -type f -name ".coverage" -delete
	find . -type d -name ".pytest_cache" -exec rm -rf {} +
	find . -type d -name ".ruff_cache" -exec rm -rf {} +
	find . -type d -name ".mypy_cache" -exec rm -rf {} +
	rm -rf htmlcov/

# CI/CD helpers
ci-install:
	pip install -e ".[dev]"

ci-test:
	pytest --cov=app --cov-report=xml --cov-report=term-missing

ci-lint:
	ruff check .
	mypy app/
	bandit -r app/ -f json -o bandit-report.json