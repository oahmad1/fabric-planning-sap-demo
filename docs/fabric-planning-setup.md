# Fabric Planning Setup

Use this after `scripts\Deploy-FabricDemo.ps1` creates the workspace, lakehouse, warehouse, and notebook.

## 1. Seed the lakehouse

1. Open the deployed notebook named `Load SAP Planning Demo`.
2. Attach `SAPPlanningLakehouse` as the default lakehouse if prompted.
3. Run all cells.
4. Confirm the following gold tables exist:
   - `gold_inventory_position`
   - `gold_supplier_performance`
   - `gold_replenishment_plan`
   - `gold_plan_vs_actual`

## 2. Create the semantic model

Create or use a semantic model over these gold tables:

- `gold_inventory_position`
- `gold_supplier_performance`
- `gold_replenishment_plan`
- `gold_plan_vs_actual`

Recommended measures:

- Available Qty = sum of available quantity.
- Planned Demand Qty = sum of planned demand quantity.
- Reorder Qty = sum of reorder quantity.
- Working Capital Impact = sum of working capital impact.
- Stockout Risk Count = count of rows where stockout risk is High or Medium.
- Service Recovery Qty = projected inventory after revised plan minus projected inventory before plan.

## 3. Create the Planning writeback database

Fabric Planning writeback supports Fabric SQL database. Create a SQL database named `PlanningWriteback`, then run `sql\planning_writeback_schema.sql`.

If Planning creates its own writeback table during setup, map fields to these demo concepts:

- Scenario ID.
- Scenario name.
- Material.
- Plant.
- Demand uplift percent.
- Safety stock days.
- Lead-time override days.
- Reorder quantity.
- Planner comment.

## 4. Create the Fabric Planning item

Create a new Planning item in the same workspace.

Connect it to the semantic model from step 2. Add a planning sheet with these rows and columns:

- Rows: Product family, material, plant.
- Actuals: Available quantity, open demand, open inbound supply.
- Baseline plan: Baseline forecast, baseline reorder quantity, baseline projected inventory.
- Planner inputs: Demand uplift percent, safety stock days, lead-time override days, revised reorder quantity.
- Outcomes: Revised projected inventory, risk before plan, risk after plan, working capital impact.

Suggested planning interaction:

1. Filter to Electronics and Industrial product families.
2. Increase safety stock for high-risk supplier/material combinations.
3. Increase reorder quantity for `MAT-400` in `PL-20`.
4. Add comments explaining the planning decision.
5. Write the revised plan back to Fabric SQL.

## 5. Create the Data Agent

Create a Fabric Data Agent and add the lakehouse, semantic model, ontology if created, and planning writeback database if available.

Paste the content from `agents\data-agent-instructions.md` into the agent instructions.

## 6. M365 Chat demo

If your tenant supports M365 Copilot access to Fabric IQ/Data Agent experiences, use the prompts in `docs\m365-copilot-questions.md`.

If not, run the same prompts directly in the Fabric Data Agent.

