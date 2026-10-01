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
- Working Capital Delta
- Projected Inventory After Plan
- High Risk Before Count
- High Risk After Count
- Risk Reduction Count
- Service Level Before %
- Service Level After %
- Service Level Improvement %

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

### Recommended planning sheet layout

Use `gold_plan_vs_actual` as the primary table for the sheet. Use `gold_time_period` only for time mapping.

In the Planning sheet field picker, expand `gold_plan_vs_actual` and add these fields:

| Planning area | Table | Field or measure | Purpose |
| --- | --- | --- | --- |
| Rows | `gold_plan_vs_actual` | `product_family` | Executive grouping, for example Electronics vs Industrial. |
| Rows | `gold_plan_vs_actual` | `material_name` | SKU/material being planned. |
| Rows | `gold_plan_vs_actual` | `plant_name` | Plant/location where inventory risk occurs. |
| Columns | `gold_plan_vs_actual` | `scenario_name` | Compares `Current baseline plan` vs `Planner revised replenishment`. |
| Values | `gold_plan_vs_actual` | `Available Qty` | Current inventory available to promise. |
| Values | `gold_plan_vs_actual` | `Planned Demand Qty` | Demand after the scenario assumptions. |
| Values | `gold_plan_vs_actual` | `Reorder Qty` | Planned replenishment quantity. |
| Values | `gold_plan_vs_actual` | `Projected Inventory After Plan` | Inventory position after demand and replenishment. |
| Values | `gold_plan_vs_actual` | `Working Capital Impact` | Inventory investment in the scenario. |
| Values | `gold_plan_vs_actual` | `Working Capital Delta` | Incremental investment compared with baseline. |
| Values | `gold_plan_vs_actual` | `High Risk Before Count` | Number of high-risk combinations before replanning. |
| Values | `gold_plan_vs_actual` | `High Risk After Count` | Number of high-risk combinations after replanning. |
| Values | `gold_plan_vs_actual` | `Risk Reduction Count` | How many high-risk combinations improved. |
| Values | `gold_plan_vs_actual` | `Service Level Before %` | Baseline service-level estimate. |
| Values | `gold_plan_vs_actual` | `Service Level After %` | Revised-plan service-level estimate. |
| Values | `gold_plan_vs_actual` | `Service Level Improvement %` | Improvement from the revised plan. |

Optional descriptive fields from `gold_plan_vs_actual`:

| Field | Use |
| --- | --- |
| `stockout_risk_before_plan` | Show the initial risk state. |
| `stockout_risk_after_plan` | Show the revised risk state. |
| `supplier_delay_risk` | Explain supplier-driven risk. |
| `action_priority` | Identify P1/P2 planning actions. |
| `planning_recommendation` | Use as the talk-track note for the planner decision. |

For time mapping, use `gold_time_period`:

| Mapping | Table | Field |
| --- | --- | --- |
| Time table | `gold_time_period` | |
| Time dimension/date | `gold_time_period` | `period_start_date` |
| Interval | | Month |
| Format | | `YYYY-MM-DD` |

If Planning asks for dimension ID mapping and no fields appear, leave it blank. The demo model already relates `gold_plan_vs_actual[time_period_id]` to `gold_time_period[time_period_id]`.

### Minimal sheet if you want a simple first view

If the full layout feels busy, start with only these:

- Rows: `product_family`, `material_name`, `plant_name`
- Columns: `scenario_name`
- Values: `Reorder Qty`, `Projected Inventory After Plan`, `Working Capital Delta`, `Risk Reduction Count`, `Service Level Improvement %`

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
