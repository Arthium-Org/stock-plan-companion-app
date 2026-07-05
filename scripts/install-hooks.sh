#!/usr/bin/env bash
# One-command installer: activate the versioned pre-commit PII hook (Phase 4.2, D-08).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

git config core.hooksPath scripts/githooks

echo "Activated hooks dir: scripts/githooks (core.hooksPath)"
echo "The deterministic pre-commit PII scan (scripts/githooks/pre-commit) now runs on every commit in this repo."
