# Stock Plan Manager — Full PDD (Claude-Ready)

---

## 0. TL;DR (Context Block)

**Goal:**  
Build a lightweight Stock Plan (RSU/ESPP/Stock Options) management app for E*Trade users.

**Core Design:**

Bronze (raw) → Silver (versioned events) → Gold (derived views)

**Key Decisions:**

- No ledger system
- Silver = financial truth (per ingestion)
- Full rebuild on upload
- Versioned ingestion (ACTIVE only)
- Dual FX model (event-time + current)

---

## 1. Problem Definition

### 1.1 User

- Software engineers with RSU / ESPP / Stock Options
- Using E*Trade “Stock Plan”

### 1.2 Pain Points

- No unified view of vested vs unvested
- No INR view
- Hard to track cost basis & PnL
- No projection of future income

### 1.3 Success Criteria

Upload XLSX → See:
- Portfolio (USD + INR)
- Realized income
- Projected income
- Per-grant breakdown

---

## 2. System Architecture

E*Trade XLSX → Bronze → Silver → Gold

### Core Principles

- Versioned ingestion
- Full rebuild
- Deterministic output
- No cross-version mixing

---

## 3. Data Model

### stock_plan_ingestions

- ingestion_id (uuid)
- user_id
- account_id
- broker = ETRADE
- source_type = XLSX
- file_name
- status (ACTIVE / ARCHIVED)
- created_at

---

### stock_plan_bronze_raw

- id
- ingestion_id
- raw_row_json
- row_hash
- created_at

---

### stock_plan_grants

- grant_id
- ingestion_id
- account_id
- instrument_id
- plan_type (RSU / ESPP / STOCK_OPTION)
- grant_date
- total_quantity
- vesting_schedule_json
- currency (USD)

---

### stock_plan_events

- event_id
- ingestion_id
- source_event_id
- grant_id
- instrument_id
- event_type (VEST / PURCHASE / EXERCISE / SELL)
- event_date
- quantity
- price
- fmv
- currency
- event_fx_rate
- event_fx_value_in_inr
- created_at

---

## 4. Event Semantics

### RSU

VEST → income realized + cost basis = FMV

### ESPP

PURCHASE → discounted buy

### STOCK_OPTION

EXERCISE → buy at strike

---

## 5. Ingestion Pipeline

1. Upload XLSX
2. Create ingestion_id
3. Archive previous ingestion
4. Write Bronze
5. Rebuild Silver
6. Apply FX

---

## 6. Mapping Rules

### RSU

event_type = VEST  
price = fmv  

### ESPP

event_type = PURCHASE  
price = purchase_price  

### STOCK_OPTION

event_type = EXERCISE  
price = strike_price  

---

## 7. FX Model

- Store event FX
- Compute current FX dynamically

---

## 8. Gold Layer

### Portfolio

- quantity
- avg_cost
- pnl (USD + INR)

### Income

- realized (VEST)
- projected (unvested * current price)

---

## 9. APIs

- POST /stock-plan/upload
- GET /stock-plan/portfolio
- GET /stock-plan/income
- GET /stock-plan/timeline

---

## 10. UI

- Group by grant / plan type
- USD / INR toggle
- Income chart

---

## 11. Edge Cases

- Missing FMV → fallback to price
- Duplicate rows → dedupe via hash
- Partial upload → overwrite

---

## 12. Risks

- FX accuracy
- incorrect uploads
- interpretation drift

---

## 13. Phase 2

- Tax engine
- Sell optimization
- ITR docs

---

## 14. Summary

- Medallion architecture
- Versioned ingestion
- Event-based model
