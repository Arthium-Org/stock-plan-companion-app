# Test Plan: M9 — Upload UI

---

## TP-1: Routes

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.1 | GET /upload | 200, contains "Upload Files" |
| TP-1.2 | GET /portfolio | 200, contains "Portfolio" |
| TP-1.3 | Nav links present on home page | /upload and /portfolio in HTML |

## TP-2: Upload — Benefit History

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-2.1 | Upload valid BH XLSX | Success summary shown (origins, tranches, sales) |
| TP-2.2 | Upload non-XLSX file | Validation error shown |
| TP-2.3 | Upload same file twice | Duplicate error shown |
| TP-2.4 | Processing spinner visible during pipeline | @processing = true |
| TP-2.5 | Buttons disabled during processing | disabled attribute set |

## TP-3: Upload — G&L

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-3.1 | Upload G&L after BH | Success summary shown |
| TP-3.2 | Upload G&L without BH | "Please upload Benefit History first" error |
| TP-3.3 | Multiple G&L files | All appear in upload history |

## TP-4: Upload History

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.1 | After uploads, history shows all ingestions | Correct file names, categories, statuses |
| TP-4.2 | ACTIVE vs ARCHIVED visually distinct | Badge colors differ |
| TP-4.3 | Newest first ordering | Most recent at top |

## TP-5: Error Handling

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-5.1 | Unknown error from pipeline | "Something went wrong" fallback message |
| TP-5.2 | Task crash during processing | UI recovers, shows error, processing = false |

---

## Test Approach

- TP-1: Automated (ConnCase — already implemented)
- TP-2 through TP-5: Manual browser testing (LiveView upload requires browser interaction)
- Future: LiveView test helpers for programmatic upload testing

## Test Count: ~13 (3 automated, ~10 manual)
