# Maintainer Workflow — Go-Public-Primary (Phase 4.2)

This document records how Stock Plan Manager is developed and released **after** the
one-time flip to the public repo. It replaces the old `publish_snapshot.sh` re-snapshot
loop for all routine work (that script is now retired except as an emergency reference —
see [One-Time Flip Runbook](#one-time-flip-runbook-2026-07) below).

## Go-Forward Development Loop

All new work happens directly in the fresh public clone. There is no more
scrub-and-squash-at-publish step — the public repo (`Arthium-Org/stock-plan-companion-app`)
is the single source of truth for code, issues, and releases.

```bash
git clone https://github.com/Arthium-Org/stock-plan-companion-app.git
cd stock-plan-companion-app
git checkout -b my-feature-branch
# ... make changes, commit ...
git push -u origin my-feature-branch
```

1. Branch from `main` in `Arthium-Org/stock-plan-companion-app`.
2. Open a PR against `main` on the public repo. CI (`.github/workflows/ci.yml`) runs the
   full precommit checklist plus the PII scan backstop (see below) on every push/PR.
3. Merge the PR once CI is green and review is complete.
4. Cut a release from the public repo when ready:

```bash
gh release create v1.2.0 \
  --repo Arthium-Org/stock-plan-companion-app \
  --title "v1.2.0" \
  --notes "Release notes here" \
  path/to/StockPlanManager-mac-signed.zip
```

The Phase 4.1 signed Mac binaries are attached as release assets on the public repo.

**This loop replaces the `publish_snapshot.sh` re-snapshot dance.** Routine work no longer
requires building a clean-history snapshot and force-pushing — the public repo's
`.gitignore` (see below) keeps PII out from the start, so ordinary branch → PR → merge is
safe.

## Enable the PII Pre-Commit Hook

Local hooks are a convenience, not a guarantee (CI is the real backstop — see next
section), but every contributor should still enable the deterministic pre-commit PII scan
before their first commit:

```bash
./scripts/install-hooks.sh
```

This is equivalent to:

```bash
git config core.hooksPath scripts/githooks
```

Either command points git at the versioned hooks directory. The hook runs the same
deterministic scan as CI (`scripts/pii_scan.sh`) against staged files and hard-blocks the
commit on any finding (real PII token, forbidden path, or tracked broker-export binary).

**CI is the bypass-proof backstop.** The pre-commit hook can be skipped with
`git commit --no-verify`, and it is not installed automatically on a fresh clone. The
`PII scan (deterministic backstop)` step in `.github/workflows/ci.yml` runs
`./scripts/pii_scan.sh` on every push/PR to `main` regardless of local hook state, so the
gate holds even if a contributor never runs `install-hooks.sh`.

## One-Time Flip Runbook (2026-07)

This section is a historical/reference runbook for the one-time resync that flipped
development from the private repo to the public repo. It is **not** part of the
go-forward loop above — routine work never repeats this. Kept for reference and for the
rare case of an emergency re-snapshot.

1. Confirm all wanted code is committed to the private repo HEAD:

   ```bash
   git status                              # must be clean
   mix format --check-formatted            # must pass
   mix compile --warnings-as-errors        # must pass
   ```

   `git archive HEAD` (used by the snapshot script) ships **tracked files only** — anything
   only on disk or unstaged will not be included.

2. Build the clean snapshot and STOP at the human-review gate:

   ```bash
   scripts/publish_snapshot.sh HEAD
   ```

   At the gate, confirm the scratch tree has **no** `.planning`, `.claude`, `.cursor`,
   `docs/Sample-Data`, `docs/Etrade-Screenshots`, or `docs/Issues`, and that
   `pii_scan.sh` / `.gitleaks.toml` in the scratch tree carry no real token.

3. **Manually** force-push the reviewed snapshot over
   `Arthium-Org/stock-plan-companion-app` `main`. This step is never scripted — a human
   must run it after review (Phase 3 Pitfall 6):

   ```bash
   cd <scratch-dir>
   git push --force <public-remote> HEAD:main
   ```

4. **Fresh-clone** the public repo into a new local working directory:

   ```bash
   git clone https://github.com/Arthium-Org/stock-plan-companion-app.git \
     ~/Projects/stock-plan-companion-app
   ```

   `~/Projects/stock-plan-companion-app` becomes the new working home for all
   go-forward development (the loop described above).

5. Verify on GitHub and in the fresh clone: latest code present, CI green, and **no**
   `.planning` / `.claude` / `.cursor` / Sample-Data anywhere in the tree or history.

## Repo Status

- **Public — `Arthium-Org/stock-plan-companion-app`** — the source of truth. All new
  branches, PRs, releases, and issues happen here.
- **Private — `kvakatidev/wealth-management-stock-plan`** — kept in place for
  history/backup only. It receives **no new work** after the flip. Its git history
  contains real financial PII (real tax filings, real E*Trade exports) and must never be
  made public or merged into the public repo.
