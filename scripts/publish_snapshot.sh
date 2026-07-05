#!/usr/bin/env bash
# Build the clean-history public snapshot for Stock Plan Manager (Phase 3, REPO-02).
#
# Produces a single-commit, PII-clean copy of the tracked repo content in an isolated
# scratch directory (git archive -> filter excluded PII paths -> sanitize scan tooling ->
# fresh `git init` -> commit -> re-run scripts/pii_scan.sh -> final literal-token grep),
# then STOPS at a human-review gate. This script never creates a GitHub org, never
# creates a remote repo, and never pushes — those steps are manual, by design (see
# .planning/phases/03-public-repository-ci/03-RESEARCH.md Pitfall 6).
#
# Usage:
#   scripts/publish_snapshot.sh [REF] [SNAPSHOT_DIR] [--force]
#
#   REF           git ref to snapshot (default: HEAD). Never hardcode "main" — work
#                 happens on a feature branch until Phase 3 is ready to publish.
#   SNAPSHOT_DIR  scratch directory to build the snapshot in (default:
#                 <repo-root>/.gsd-scratch/public-snapshot). Relative paths are resolved
#                 against the repo root. Never point this at an arbitrary system path.
#   --force       remove a pre-existing non-empty SNAPSHOT_DIR without prompting.
#
# This script NEVER modifies the working-repo originals of scripts/pii_scan.sh or
# .gitleaks.toml — sanitization is applied only to the copies inside SNAPSHOT_DIR.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# --- Argument parsing -------------------------------------------------------

FORCE=0
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --force)
      FORCE=1
      ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      POSITIONAL+=("$arg")
      ;;
  esac
done

REF="${POSITIONAL[0]:-HEAD}"
SNAPSHOT_ARG="${POSITIONAL[1]:-.gsd-scratch/public-snapshot}"

case "$SNAPSHOT_ARG" in
  /*) SNAPSHOT="$SNAPSHOT_ARG" ;;
  *) SNAPSHOT="$ROOT/$SNAPSHOT_ARG" ;;
esac

if [ "$SNAPSHOT" = "$ROOT" ] || [ "$SNAPSHOT" = "/" ] || [ -z "$SNAPSHOT" ]; then
  echo "ERROR: refusing to use '$SNAPSHOT' as the scratch dir (unsafe)." >&2
  exit 1
fi

echo "=== scripts/publish_snapshot.sh ==="
echo "REF:      $REF"
echo "SNAPSHOT: $SNAPSHOT"
echo

# --- Step 0: extract the real PII token list from the WORKING-REPO original ------------
# Never hardcode the literal token in this script's source — read it at runtime from
# scripts/pii_scan.sh so the guard below stays in sync and this script's own source
# (which itself ships in the public snapshot) never embeds the literal.

extract_real_tokens() {
  local file="$1"
  awk '
    /^REAL_TOKENS=\(/ { inarr = 1; next }
    inarr && /^\)/ { inarr = 0; next }
    inarr { print }
  ' "$file" | grep -oE '"[^"]*"' | sed 's/^"//; s/"$//'
}

REAL_TOKENS_TO_CHECK=()
while IFS= read -r tok; do
  [ -n "$tok" ] && REAL_TOKENS_TO_CHECK+=("$tok")
done < <(extract_real_tokens "$ROOT/scripts/pii_scan.sh")

if [ "${#REAL_TOKENS_TO_CHECK[@]}" -eq 0 ]; then
  echo "ERROR: could not extract REAL_TOKENS from $ROOT/scripts/pii_scan.sh." >&2
  echo "Refusing to proceed without a known token to guard against." >&2
  exit 1
fi

# --- Step 1: guard + prepare scratch dir ------------------------------------

echo "==> Preparing scratch directory"
if [ -d "$SNAPSHOT" ] && [ -n "$(ls -A "$SNAPSHOT" 2>/dev/null)" ]; then
  if [ "$FORCE" -ne 1 ]; then
    echo "ERROR: scratch dir '$SNAPSHOT' already exists and is not empty." >&2
    echo "Re-run with --force to remove it and rebuild, or delete it manually first." >&2
    exit 1
  fi
  echo "    --force given: removing existing scratch dir"
fi
rm -rf "$SNAPSHOT"
mkdir -p "$SNAPSHOT"

# --- Step 2: git archive -> tracked-only export -----------------------------

echo "==> Archiving tracked files at $REF"
git archive "$REF" | tar -x -C "$SNAPSHOT"

# --- Step 3: remove still-tracked PII-excluded paths ------------------------

echo "==> Removing excluded PII paths from scratch snapshot"
EXCLUDED_PATHS=(
  "docs/Sample-Data"
  "docs/Etrade-Screenshots"
  "docs/Issues"
  ".planning"
  ".claude"
  ".cursor"
)
for p in "${EXCLUDED_PATHS[@]}"; do
  if [ -e "$SNAPSHOT/$p" ]; then
    rm -rf "$SNAPSHOT/$p"
    echo "    removed: $p"
  else
    echo "    not present (already clean): $p"
  fi
done

echo "==> Listing docs/ subfolders for human review"
echo "    (not all of these were individually vetted by Phase 1 — eyeball before publishing)"
if [ -d "$SNAPSHOT/docs" ]; then
  ls -la "$SNAPSHOT/docs"
else
  echo "    (no docs/ directory in snapshot)"
fi
echo

# --- Step 4: sanitize scan-tooling copies (never touch the working-repo originals) ------

echo "==> Sanitizing scripts/pii_scan.sh / .gitleaks.toml in scratch snapshot"

sanitize_pii_scan_copy() {
  local target="$SNAPSHOT/scripts/pii_scan.sh"
  [ -f "$target" ] || return 0
  awk '
    /^REAL_TOKENS=\(/ {
      print "# NOTE (public template): no real PII tokens ship in this open-source copy."
      print "# Maintainers running this scan against their own fork/data should add their"
      print "# own sensitive tokens here, or keep them in a local, gitignored override"
      print "# file and source it before invoking this script."
      print "REAL_TOKENS=("
      print "  \"REPLACE-WITH-YOUR-OWN-TOKEN\"  # placeholder -- never matches real data"
      print ")"
      skip = 1
      next
    }
    skip && /^\)/ { skip = 0; next }
    skip { next }
    /^SELF_FILES=\(/ {
      # This script (publish_snapshot.sh) is the one that WRITES the placeholder
      # token above, so its own source literally contains that string -- add it to
      # SELF_FILES so the scratch-dir scan gate does not false-positive on itself,
      # the same reason pii_scan.sh/.gitleaks.toml already self-exclude below.
      print
      print "  \"scripts/publish_snapshot.sh\"  # emits the placeholder token above literally"
      next
    }
    { print }
  ' "$target" > "$target.tmp"
  mv "$target.tmp" "$target"
  chmod +x "$target"
}

sanitize_gitleaks_copy() {
  local target="$SNAPSHOT/.gitleaks.toml"
  [ -f "$target" ] || return 0
  cat > "$target" <<'EOF'
# gitleaks configuration (public template)
#
# This is the open-source, reusable-by-anyone version of the secret-scan config. The
# private working repo's project-specific PII rule is intentionally NOT included here --
# this generic config relies on gitleaks' built-in default rule set (API keys, AWS keys,
# private keys, etc.) plus a minimal allowlist for this repo's own scan tooling files.
[extend]
useDefault = true

[allowlist]
description = "Files that are the scan gate's own definitions, not findings."
paths = [
  '''^scripts/pii_scan\.sh$''',
  '''^\.gitleaks\.toml$''',
]
EOF
}

# Belt-and-suspenders: the REAL_TOKENS/SELF_FILES array edits above only touch the
# array literals -- pii_scan.sh's header COMMENTS also describe the real token in
# prose (e.g. "dirs hold real PII (incl. account <token>)"). Blanket-redact every
# literal occurrence of each real token anywhere in the scratch copy, comments
# included, so no documentation string can leak it.
redact_literal_tokens_in_pii_scan_copy() {
  local target="$SNAPSHOT/scripts/pii_scan.sh"
  [ -f "$target" ] || return 0
  local tok esc_tok
  for tok in "${REAL_TOKENS_TO_CHECK[@]}"; do
    esc_tok=$(printf '%s' "$tok" | sed 's/[.[\*^$/&]/\\&/g')
    sed -i.bak "s/$esc_tok/[EXAMPLE-TOKEN-REDACTED]/g" "$target"
    rm -f "$target.bak"
  done
}

sanitize_pii_scan_copy
redact_literal_tokens_in_pii_scan_copy
sanitize_gitleaks_copy
echo "    OK: scratch copies sanitized (working-repo originals untouched)"
echo

# --- Step 5: mix format (belt-and-suspenders; ref should already be formatted) ----------

echo "==> Running mix format in scratch snapshot (belt-and-suspenders)"
FORMAT_OK=0
if command -v mix >/dev/null 2>&1; then
  if ( cd "$SNAPSHOT" && MIX_ENV=dev mix deps.get > .publish_snapshot_format.log 2>&1 \
      && MIX_ENV=dev mix format >> .publish_snapshot_format.log 2>&1 ); then
    FORMAT_OK=1
  fi
fi
if [ "$FORMAT_OK" -eq 1 ]; then
  echo "    OK: mix format applied."
else
  echo "    WARNING: could not run 'mix format' inside the isolated scratch dir" >&2
  echo "    (deps unavailable/fetch failed, or mix not on PATH). Non-fatal --" >&2
  echo "    the archived ref should already be formatted by an earlier snapshot-prep" >&2
  echo "    step. Confirm 'mix format --check-formatted' passes in the working repo" >&2
  echo "    before publishing." >&2
fi
# Never let a deps fetch attempted here leak into the published commit.
rm -rf "$SNAPSHOT/deps" "$SNAPSHOT/_build" "$SNAPSHOT/.publish_snapshot_format.log"
echo

# --- Step 6: fresh git init + single commit (brand-new object database) ----------------

echo "==> Initializing fresh git repo (zero shared history)"
(
  cd "$SNAPSHOT"
  git init -q
  git add -A
  git commit -q -m "Initial public release snapshot

Clean-history snapshot generated by scripts/publish_snapshot.sh from ref $REF.
See LICENSE, README.md, and CONTRIBUTING.md for details."
)
echo "    OK: single commit created in a brand-new object database"
echo

# --- Step 7: re-run Phase 1's scan gate INSIDE the scratch repo ------------------------

echo "==> Running pii_scan.sh against scratch snapshot"
if [ -x "$SNAPSHOT/scripts/pii_scan.sh" ]; then
  if ! ( cd "$SNAPSHOT" && ./scripts/pii_scan.sh ); then
    echo "BLOCK: pii_scan.sh reported findings inside the scratch snapshot -- do not publish." >&2
    exit 1
  fi
else
  echo "BLOCK: scripts/pii_scan.sh not found/executable in scratch snapshot -- refusing to proceed." >&2
  exit 1
fi
echo

# --- Step 8: final literal-token guard --------------------------------------------------

echo "==> Final literal-token guard over scratch snapshot"
GUARD_FAILED=0
for tok in "${REAL_TOKENS_TO_CHECK[@]}"; do
  # --exclude-dir must come BEFORE the `--` end-of-options marker -- placing it after
  # (as in `grep -r -- "$tok" "$dir" --exclude-dir=.git`) makes grep treat it as a
  # literal path argument instead of a flag, silently defeating the exclusion.
  if grep -r --exclude-dir=.git -- "$tok" "$SNAPSHOT"; then
    GUARD_FAILED=1
  fi
done
if [ "$GUARD_FAILED" -eq 1 ]; then
  echo "BLOCK: real PII token still present in snapshot -- do not publish" >&2
  exit 1
fi
echo "    OK: no literal PII tokens found in scratch tree."
echo

# --- HUMAN REVIEW GATE -------------------------------------------------------

echo "==> HUMAN REVIEW GATE -- stop and confirm before any push"
echo
echo "Snapshot built at: $SNAPSHOT"
echo
echo "Review checklist before publishing:"
echo "  - Confirm the docs/ subfolders listed above contain nothing private/internal."
echo "  - Spot-check the scratch tree for anything unexpected."
echo "  - Confirm scripts/pii_scan.sh and .gitleaks.toml in the scratch tree contain no"
echo "    real tokens (this script sanitized them; double-check anyway)."
echo
echo "Next steps (MANUAL -- NOT run by this script):"
echo "  1. Confirm the target GitHub org exists (web UI only -- org creation cannot be"
echo "     scripted; see .planning/phases/03-public-repository-ci/03-RESEARCH.md Pitfall 6)."
echo "  2. cd $SNAPSHOT && gh repo create <org>/<repo> --public --source=. --push"
echo
exit 0
