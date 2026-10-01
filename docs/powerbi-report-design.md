# Power BI Report Design

Create a report over the semantic model built from the `gold` tables.

## Page 1: Executive inventory risk

Visuals:

- Card: High-risk material/plant combinations before plan.
- Card: High-risk combinations after revised plan.
- Card: Working capital delta.
- Card: Average service-level improvement.
- Bar chart: Stockout risk before vs after by product family.
- Matrix: Material, plant, available quantity, planned demand, reorder quantity, projected inventory.

## Page 2: Plan bridge

Visuals:

- Waterfall: Available inventory + inbound supply + revised reorder quantity - planned demand.
- Column chart: Working capital impact by plant.
- Column chart: Working capital delta by product family.
- Line or column chart: Service level before vs after by material.
- Matrix: Baseline scenario vs revised scenario by material and plant.

## Page 3: Supplier drivers

Visuals:

- Bar chart: Supplier delay risk by supplier.
- Table: Supplier, risk tier, average days late, affected materials, affected plants.
- Slicer: Product family.

## Recommended measures

```DAX
Available Qty = SUM('gold_plan_vs_actual'[available_qty])

Planned Demand Qty = SUM('gold_plan_vs_actual'[planned_demand_qty])

Reorder Qty = SUM('gold_plan_vs_actual'[reorder_qty])

Working Capital Impact = SUM('gold_plan_vs_actual'[working_capital_impact])

High Risk Before Count = SUM('gold_plan_vs_actual'[high_risk_before_count])

High Risk After Count = SUM('gold_plan_vs_actual'[high_risk_after_count])

Risk Reduction Count = SUM('gold_plan_vs_actual'[risk_reduction_count])

Working Capital Delta = SUM('gold_plan_vs_actual'[working_capital_delta])

Service Level Improvement % = AVERAGE('gold_plan_vs_actual'[service_level_delta_pct])

Projected Inventory After Plan =
SUM('gold_plan_vs_actual'[projected_inventory_after_plan])
```

## M365 Copilot visual moment

Ask:

> Create a visual comparing stockout risk before and after the revised plan by product family.

The expected visual should show Electronics and Industrial improving after the revised plan, with working capital increasing because the planner added buffer inventory.
