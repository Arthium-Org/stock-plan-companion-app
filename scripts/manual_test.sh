#!/usr/bin/env bash
# Golden-file verification: Portfolio, Capital Gains, Schedule FA vs Sample-Data XLSX.
# Prerequisite: Sample User 3 (or configured user) already uploaded to dev DB.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

exec mix stock_plan.manual_test "$@"
