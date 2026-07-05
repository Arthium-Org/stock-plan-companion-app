# Test Plan: M8 — Ingestion Orchestrator

---

## TP-1: Benefit History Ingestion

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.1 | Valid BH file, full pipeline | `{:ok, summary}` with ingestion_id, bronze.inserted > 0, silver.origins > 0 |
| TP-1.2 | Non-existent file | `{:error, :file_not_found}` |
| TP-1.3 | Previous BH archived on new upload | Old status = ARCHIVED, new = ACTIVE |
| TP-1.4 | Ingestion record fields correct | category=BENEFIT_HISTORY, file_hash set, status=ACTIVE |
| TP-1.5 | No ingestion on parse failure | Ingestion count unchanged |

## TP-2: G&L Ingestion

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-2.1 | Valid G&L after BH | `{:ok, summary}` |
| TP-2.2 | G&L without BH | `{:error, :no_benefit_history}` |
| TP-2.3 | Multiple G&L coexist | Both ACTIVE |
| TP-2.4 | G&L enriches Silver | vest_fmv populated after rebuild |

## TP-3: Duplicate Detection

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-3.1 | Same BH file twice | `{:error, :duplicate_file, id}` |
| TP-3.2 | Same G&L file twice | `{:error, :duplicate_file, id}` |

## TP-4: Rebuild

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.1 | Rebuild with data | `{:ok, summary}` |
| TP-4.2 | Rebuild no BH | `{:error, :no_benefit_history}` |

## TP-5: Full Pipeline Integration

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-5.1 | BH + 2 G&L + rebuild | Silver data correct, FX + stock prices, RSU allocs |

---

## Test Count: ~14
