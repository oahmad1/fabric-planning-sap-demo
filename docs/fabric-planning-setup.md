# Fabric Planning Setup

Use this after `scripts\Deploy-FabricDemo.ps1` creates the workspace, lakehouse, notebook, and semantic model.

## 1. Confirm the lakehouse data

The deployment script runs the notebook automatically when you use `-CompleteSetup -WaitForNotebook`.

Confirm the following gold tables exist in `SAPPlanningLakehouse`:

- `gold_time_period`
- `gold_inventory_position`
- `gold_supplier_performance`
- `gold_replenishment_plan`
- `gold_plan_vs_actual`

## 2. Confirm the semantic model

Open `SAP Planning Semantic Model` and confirm it has these five tables. The model is Import mode for Planning compatibility; the lakehouse remains the source/data-foundation part of the demo story:

- `gold_time_period`
- `gold_inventory_position`
- `gold_supplier_performance`
- `gold_replenishment_plan`
- `gold_plan_vs_actual`

Recommended measures are created on `gold_plan_vs_actual`:

- Available Qty
- Planned Demand Qty
- Reorder Qty
- Working Capital Impact
- Projected Inventory After Plan
- High Risk Count

## 3. Configure Planning time mapping

When creating or configuring the Plan item, use:

- Time table: `gold_time_period`
- Time column: `period_start_date`
- Month label: `year_month`

A separate SQL database is not required for the first-run demo. Fabric Planning creates backing storage for the Plan item as needed.

## 4. Create the Fabric Planning item

Create a new Planning item in the same workspace.

Connect it to `SAP Planning Semantic Model` using a Power BI Semantic Model cloud connection owned by an account that has:

- Member or Admin access to workspace `Fabric SAP Planning Demo`.
- Build permission on `SAP Planning Semantic Model`.

Add a planning sheet with these rows and columns:

- Rows: product family, material, plant.
- Time: `gold_time_period[period_start_date]`.
- Actuals: available quantity, open demand, open inbound supply.
- Baseline plan: baseline forecast, baseline reorder quantity, baseline projected inventory.
- Planner inputs: demand uplift percent, safety stock days, lead-time override days, revised reorder quantity.
- Outcomes: revised projected inventory, risk before plan, risk after plan, working capital impact.

Suggested planning interaction:

1. Filter to Electronics and Industrial product families.
2. Increase safety stock for high-risk supplier/material combinations.
3. Increase reorder quantity for `MAT-400` in `PL-20`.
4. Add comments explaining the planning decision.
5. Save the revised plan.

## 5. Optional Data Agent

Create a Fabric Data Agent and add the lakehouse and semantic model. Add ontology only if you created the optional ontology item.

Paste the content from `agents\data-agent-instructions.md` into the agent instructions.

## 6. M365 Chat demo

If your tenant supports M365 Copilot access to Fabric IQ/Data Agent experiences, use the prompts in `docs\m365-copilot-questions.md`.

If not, run the same prompts directly in the Fabric Data Agent.
