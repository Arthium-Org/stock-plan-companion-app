# Stock Plan (ESOP / RSU / ESPP) PDD

## 1. Problem Statement

Users hold equity compensation via broker platforms (e.g., E*Trade “Stock Plan”) including:

- RSU (Restricted Stock Units)
- ESPP (Employee Stock Purchase Plan)
- Stock Options

Challenges:

- No unified portfolio view
- Complex tax implications
- No INR view
- Manual ITR prep

---

## 2. Scope

### Phase 1
- XLSX ingestion
- Portfolio view
- Income tracking
- USD + INR

### Phase 2
- Automated ingestion
- Tax engine
- Sell guidance
- ITR docs

---

## 3. Architecture

```
E*Trade XLSX
   ↓
Bronze
   ↓
Silver
   ↓
Gold
```

---

## 4. Core Principles

- Versioned ingestion
- Deterministic rebuild
- Dual FX model

---

## 5. Data Model

### stock_plan_ingestions

- ingestion_id
- user_id
- account_id
- status

### stock_plan_bronze_raw

- ingestion_id
- raw_row_json

### stock_plan_grants

- grant_id
- plan_type
- grant_date

### stock_plan_events

- event_type (VEST, PURCHASE, EXERCISE, SELL)
- quantity
- price
- fmv

---

## 6. Ingestion Pipeline

1. Upload
2. Bronze write
3. Silver rebuild
4. FX enrichment

---

## 7. Views

### Portfolio

- quantity
- cost
- pnl

### Income

- realized
- projected

---

## 8. FX

- Event FX stored
- Current FX computed

---

## 9. APIs

- POST /upload
- GET /portfolio
- GET /income

---

## 10. UI

- Portfolio grouping
- USD/INR toggle
- Income charts

---

## 11. Risks

- FX accuracy
- incorrect uploads

---

## 12. Phase 2

- Tax engine
- Sell optimization

---

## 13. Summary

- Medallion architecture
- Versioned ingestion
- Event-based model
