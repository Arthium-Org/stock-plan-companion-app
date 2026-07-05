#!/usr/bin/env bash
# Self-contained functional test for scripts/githooks/pre-commit (Phase 4.2, D-08).
# Builds a throwaway git sandbox in a temp dir, activates the hook there via
# core.hooksPath, and asserts real-token blocking, clean-commit pass-through, and
# self-exclusion of scripts/pii_scan.sh. Never mutates this repo's index or config.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

TMPDIR=""
cleanup() {
  if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

TMPDIR="$(mktemp -d)"
echo "==> Sandbox: $TMPDIR"

cp -R "$ROOT/scripts" "$TMPDIR/scripts"

cd "$TMPDIR"
git init -q
git config user.email "selftest@example.com"
git config user.name "Hook Selftest"
git config core.hooksPath scripts/githooks

FAIL=0

# --- Extract the real token from the sandboxed copy of pii_scan.sh (never hardcode it here) ---
REAL_TOKEN="$(awk '
  /^REAL_TOKENS=\(/ { inarr = 1; next }
  inarr && /^\)/ { inarr = 0; next }
  inarr { print }
' scripts/pii_scan.sh | grep -oE '"[^"]*"' | sed 's/^"//; s/"$//' | head -n1)"

if [ -z "$REAL_TOKEN" ]; then
  echo "ERROR: could not extract a REAL_TOKEN from sandboxed scripts/pii_scan.sh." >&2
  exit 1
fi

# --- Assertion (a): staging a file containing the real token fails the commit ---
echo "account: $REAL_TOKEN" > leak.txt
git add leak.txt
if git commit -m "test: should be blocked" >commit_a.log 2>&1; then
  echo "FAIL (a): commit with real token succeeded (expected block)"
  cat commit_a.log
  FAIL=1
else
  echo "OK (a): commit with real token was blocked"
fi
git reset -q HEAD -- leak.txt 2>/dev/null || true
rm -f leak.txt commit_a.log

# --- Assertion (b): staging only a clean file commits successfully ---
echo "hello world" > clean.txt
git add clean.txt
if git commit -q -m "test: clean commit"; then
  echo "OK (b): clean commit succeeded"
else
  echo "FAIL (b): clean commit was blocked unexpectedly"
  FAIL=1
fi

# --- Assertion (c): staging pii_scan.sh itself (which legitimately contains REAL_TOKENS)
# is self-excluded and does not trip the hook ---
git add scripts/pii_scan.sh
if git commit -q -m "test: self-exclusion"; then
  echo "OK (c): staging scripts/pii_scan.sh did not trip the hook"
else
  echo "FAIL (c): staging scripts/pii_scan.sh was incorrectly blocked (self-exclusion broken)"
  FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
  echo "=== hook_selftest.sh: PASS ==="
  exit 0
else
  echo "=== hook_selftest.sh: FAIL ==="
  exit 1
fi
