# Demo Script

## Audience

Sales teams, SAP account teams, Fabric sellers, and solution specialists who need to show Fabric Planning on top of SAP-style operational data.

## Positioning

This is not a replacement for SAP as the system of record. The story is that Fabric becomes the governed data, AI, analytics, and planning layer over SAP actuals.

## Demo flow

### 1. Set the business problem

"The planner has SAP actuals, procurement signals, inventory balances, and demand forecasts, but planning still happens across spreadsheets and siloed planning tools. Fabric brings actuals, forecast, AI, and planning into one governed environment."

Show the workspace items:

- Lakehouse with dummy SAP-style actuals.
- Notebook that loads and curates the data.
- Semantic model or report over gold tables.
- Planning item.
- Data Agent.
- Optional ontology.

### 2. Show actuals

Open the gold inventory table or Power BI report.

Call out:

- Inventory by plant and product family.
- Open demand.
- Open inbound purchase orders.
- Current stockout risk.
- Supplier lead-time risk.

### 3. Ask the first AI question

Ask in Fabric Data Agent or M365 Chat:

"Which material and plant combinations are at highest stockout risk before the revised plan?"

Expected answer:

- `MAT-400` at `PL-20` because demand is high, available inventory is low, and supplier risk is high.
- `MAT-100` at `PL-30` because demand is increasing and inbound supply has longer lead time.
- `MAT-300` at `PL-20` because the baseline plan underestimates demand.

### 4. Move into Planning

Open the Fabric Planning sheet.

Show baseline versus planner inputs:

- Demand uplift percent.
- Safety stock days.
- Lead-time override.
- Revised reorder quantity.

Change the revised plan:

- Increase `MAT-400` at `PL-20` reorder quantity.
- Increase safety stock for `MAT-100` at `PL-30`.
- Add a comment: "Supplier delay risk requires temporary buffer until lead time stabilizes."

Write the plan back.

### 5. Show before versus after

Open the Power BI report or gold plan-vs-actual table.

Show:

- Stockout risk before plan.
- Stockout risk after plan.
- Working capital impact.
- Top supplier drivers.

Ask:

"What changed between the baseline plan and the revised replenishment plan?"

### 6. Close with the SAP/BPS extension

"Today this uses dummy SAP-style data. With Business Process Solutions, the same demo can be sourced from SAP S/4HANA or ECC subject areas, preserving SAP semantics while enabling Fabric Planning, Power BI, Data Agent, ontology, and M365 Copilot experiences."

## Talk track close

"The value is not just reporting on SAP. It is moving from SAP actuals to governed planning decisions, with AI explaining the why, and with planning results available for downstream analytics."

