#!/usr/bin/env bash
# PII / secret scan gate for the public open-source release (Phase 1, DATA-01/02/03).
# Adapted for the public-primary model (Phase 4.2, D-07).
#
# Runs standalone. gitleaks is used OPTIONALLY, only if `command -v gitleaks` succeeds —
# it is NOT a hard dependency of this gate (it is not installed in this environment).
#
# Two checks determine the result:
#
#   CHECK 1 — Code-tree PII: is any code-tree PII path (docs/Sample-Data/,
#   docs/Etrade-Screenshots/, docs/Issues/, priv/static/uploads/) or a tracked real broker
#   export binary (*.xlsx / *.pdf, anywhere in the tree — except the small, human-reviewed doc
#   allowlist in DOC_BINARY_ALLOWLIST) present in `git ls-files`? In the
#   public-primary repo, `.planning/`/`.claude/`/`.cursor/` are gitignored (Phase 4.2, D-04),
#   so this check no longer needs to special-case those dirs — its job narrows to protecting
#   the code tree. A finding here is a REAL leak to fix before committing, not expected-for-now.
#
#   CHECK 2 — Publishable-set leakage: does a known real PII token (or an excluded path)
#   appear in the PUBLISHABLE set (`git ls-files` minus the excluded paths above, minus this
#   script's own definition files)? This must be clean NOW and always — a finding here is a
#   real leak requiring immediate action, not an expected/pending one.
#
# Exit code: non-zero if EITHER check finds something. Both checks are real leaks requiring
# immediate action before any commit/push — there is no "expected-for-now" case anymore.
#
# Usage: ./scripts/pii_scan.sh   (run from anywhere; cds to repo root)

set -uo pipefail  # deliberately no -e: run every check and report a full summary

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# --- Config: excluded paths (verified 2026-07-03, see
# .planning/phases/01-pii-scrub-anonymized-test-fixtures/01-CONTEXT.md) ---
# Used by Check 2's publishable-set filter (below); these paths are gitignored in the
# public-primary repo (D-04) so they are normally simply absent from `git ls-files`.
EXCLUDED_PATH_PATTERNS=(
  "docs/Sample-Data/"
  "docs/Etrade-Screenshots/"
  "docs/Issues/"
  ".planning/"
  ".claude/"
)

# --- Config: code-tree PII paths (Phase 4.2, D-07) ---
# Unlike EXCLUDED_PATH_PATTERNS above, these are NEVER expected to be tracked, in either the
# private or the public repo. Check 1 hard-fails if any of these prefixes (or a real broker
# export binary) is tracked.
CODE_TREE_FORBIDDEN=(
  "docs/Sample-Data/"
  "docs/Etrade-Screenshots/"
  "docs/Issues/"
  "priv/static/uploads/"
)

# --- Config: known real PII tokens (never scale/anonymize these into fixtures) ---
# NOTE (public template): no real PII tokens ship in this open-source copy.
# Maintainers running this scan against their own fork/data should add their
# own sensitive tokens here, or keep them in a local, gitignored override
# file and source it before invoking this script.
REAL_TOKENS=(
  "REPLACE-WITH-YOUR-OWN-TOKEN"  # placeholder -- never matches real data
)

# --- Self-exclusion: this scan gate's own definition files legitimately contain the
# token/path patterns above (as documentation/config); never treat them as findings. ---
SELF_FILES=(
  "scripts/pii_scan.sh"
  ".gitleaks.toml"
  "scripts/publish_snapshot.sh"  # emits the placeholder token above literally
)

# --- Config: reviewed doc-binary allowlist (Phase 4.2 checkpoint deviation, 2026-07-05) ---
# Check 1 blocks all tracked *.xlsx/*.pdf by extension because it cannot read image content.
# These two files are how-to walkthrough PDFs (image-only screenshots of the E*Trade download
# UI). They were HUMAN-REVIEWED page-by-page and confirmed to carry no account number, no name,
# and no real PII token — only a de-identified sample sell order. They are the ONLY binaries
# exempt from Check 1's extension block; every other *.xlsx/*.pdf still hard-fails. To exempt a
# new binary, a human must review it and add its exact repo-relative path here.
DOC_BINARY_ALLOWLIST=(
  "docs/How To/Etrade_Files_Download_Help.pdf"
  "docs/How To/Etrade_Files_Download_Help_2.pdf"
)

# --- Config: synthetic fixture allowlist (Phase 5, 05-02-PLAN.md Task 3) ---
# Check 1 blocks all tracked *.xlsx/*.pdf by extension because it cannot read
# image/spreadsheet content. Anything under this prefix is a REVIEWED,
# generated (never hand-authored) synthetic fixture: uniformly x0.65-scaled
# from real E*Trade exports by the private-only
# .planning/tools/generate_synthetic_fixtures.py transform (D-08), which
# never embeds real financial values. This is a narrow PATH-PREFIX exemption
# only -- it does NOT touch Check 2 below, which still scans every file
# under this prefix (since it is NOT in EXCLUDED_PATH_PATTERNS) for the real
# account token via unzip/sharedStrings.xml. That token scan is the actual
# leak net for this fixture set and must never be weakened.
SYNTHETIC_FIXTURE_ALLOWLIST_PREFIX="test/fixtures/sample-data/"

is_synthetic_fixture() {
  local f="$1"
  [[ "$f" == "$SYNTHETIC_FIXTURE_ALLOWLIST_PREFIX"* ]]
}

if [ -t 1 ]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; NC=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; NC=""
fi

is_self_file() {
  local f="$1" s
  for s in "${SELF_FILES[@]}"; do
    [[ "$f" == "$s" ]] && return 0
  done
  return 1
}

is_under_excluded_path() {
  local f="$1" p
  for p in "${EXCLUDED_PATH_PATTERNS[@]}"; do
    [[ "$f" == "$p"* ]] && return 0
  done
  return 1
}

is_doc_binary_allowlisted() {
  local f="$1" a
  for a in "${DOC_BINARY_ALLOWLIST[@]}"; do
    [[ "$f" == "$a" ]] && return 0
  done
  return 1
}

# NUL-delimited to handle filenames with spaces / unicode safely.
ALL_TRACKED=()
while IFS= read -r -d '' f; do
  ALL_TRACKED+=("$f")
done < <(git ls-files -z)

PUBLISHABLE=()
for f in "${ALL_TRACKED[@]}"; do
  is_self_file "$f" && continue
  is_under_excluded_path "$f" && continue
  PUBLISHABLE+=("$f")
done

echo "=== PII / Secret Scan (scripts/pii_scan.sh) ==="
echo "Tracked files: ${#ALL_TRACKED[@]}   Publishable-set files: ${#PUBLISHABLE[@]}"
echo

FAIL=0

# --- CHECK 1: code-tree PII hard-fail (Phase 4.2, D-07) ---
echo "--- Check 1: code-tree PII (forbidden paths / broker export binaries tracked) ---"
CODE_TREE_PII_FOUND=0
for p in "${CODE_TREE_FORBIDDEN[@]}"; do
  count=0
  for f in "${ALL_TRACKED[@]}"; do
    [[ "$f" == "$p"* ]] && count=$((count + 1))
  done
  if [ "$count" -gt 0 ]; then
    echo "${RED}  CODE-TREE PII${NC}: $p is tracked ($count file(s))"
    CODE_TREE_PII_FOUND=1
  fi
done
for f in "${ALL_TRACKED[@]}"; do
  case "$f" in
    *.xlsx|*.pdf)
      is_doc_binary_allowlisted "$f" && continue
      is_synthetic_fixture "$f" && continue
      echo "${RED}  CODE-TREE PII${NC}: real broker export binary tracked: $f"
      CODE_TREE_PII_FOUND=1
      ;;
  esac
done
if [ "$CODE_TREE_PII_FOUND" -eq 1 ]; then
  echo "  -> This is a real leak to fix before committing — code-tree PII paths and broker"
  echo "     export binaries must never be tracked, in either the private or public repo."
  FAIL=1
else
  echo "  OK: no code-tree PII paths or broker export binaries are currently tracked."
fi
echo

# --- CHECK 2: real PII token / excluded-path leakage into the PUBLISHABLE set ---
echo "--- Check 2: PII token leakage into the publishable set ---"
LEAK_FOUND=0
HAVE_UNZIP=0; command -v unzip >/dev/null 2>&1 && HAVE_UNZIP=1
HAVE_PDFTOTEXT=0; command -v pdftotext >/dev/null 2>&1 && HAVE_PDFTOTEXT=1

for f in "${PUBLISHABLE[@]}"; do
  [ -f "$f" ] || continue

  # Defensive: the publishable set should never itself contain an excluded path
  # (would indicate a bug in the filter above).
  if is_under_excluded_path "$f"; then
    echo "${RED}  BUG${NC}: excluded path leaked into publishable set: $f"
    LEAK_FOUND=1
  fi

  case "$f" in
    *.xlsx)
      if [ "$HAVE_UNZIP" -eq 1 ]; then
        text="$(unzip -p "$f" xl/sharedStrings.xml 2>/dev/null || true)"
        for tok in "${REAL_TOKENS[@]}"; do
          if [[ "$text" == *"$tok"* ]]; then
            echo "${RED}  LEAK${NC}: token '$tok' found in xlsx: $f"
            LEAK_FOUND=1
          fi
        done
      fi
      ;;
    *.pdf)
      if [ "$HAVE_PDFTOTEXT" -eq 1 ]; then
        text="$(pdftotext -layout "$f" - 2>/dev/null || true)"
        for tok in "${REAL_TOKENS[@]}"; do
          if [[ "$text" == *"$tok"* ]]; then
            echo "${RED}  LEAK${NC}: token '$tok' found in pdf: $f"
            LEAK_FOUND=1
          fi
        done
      fi
      ;;
    *)
      # Plain-text-ish files: grep directly. `-I` skips files that look binary.
      for tok in "${REAL_TOKENS[@]}"; do
        if grep -Iq -- "$tok" "$f" 2>/dev/null; then
          echo "${RED}  LEAK${NC}: token '$tok' found in: $f"
          LEAK_FOUND=1
        fi
      done
      ;;
  esac
done

if [ "$LEAK_FOUND" -eq 1 ]; then
  FAIL=1
else
  echo "  OK: no PII token or excluded-path leakage in the publishable set."
fi
if [ "$HAVE_UNZIP" -eq 0 ]; then
  echo "  NOTE: unzip not found — xlsx binary-text extraction skipped."
fi
if [ "$HAVE_PDFTOTEXT" -eq 0 ]; then
  echo "  NOTE: pdftotext not found — pdf binary-text extraction skipped."
fi
echo

# --- Optional: gitleaks (secrets), only if installed ---
echo "--- Optional: gitleaks (secrets) ---"
if command -v gitleaks >/dev/null 2>&1; then
  if gitleaks detect --no-git --source "$ROOT" --config "$ROOT/.gitleaks.toml" --redact; then
    echo "  OK: gitleaks found no secrets."
  else
    echo "${RED}  FAIL${NC}: gitleaks reported findings (see above)."
    FAIL=1
  fi
else
  echo "  SKIPPED: gitleaks not installed (optional; not a hard dependency of this gate)."
fi
echo

echo "=== Summary ==="
if [ "$FAIL" -eq 0 ]; then
  echo "${GREEN}PASS${NC}: publishable set is clean; no code-tree PII tracked."
  exit 0
else
  echo "${RED}FAIL${NC}: see findings above."
  echo "Both Check 1 (code-tree PII) and Check 2 (publishable-set token leak) are REAL"
  echo "issues that must be fixed before any commit/public push — neither is expected-for-now."
  exit 1
fi
