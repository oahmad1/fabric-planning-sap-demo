-- Run in the Fabric Warehouse if you mirror or load the gold lakehouse tables into the warehouse.
-- The notebook creates equivalent gold tables in the lakehouse.

CREATE OR ALTER VIEW dbo.vw_plan_vs_actual AS
SELECT
    material_id,
    plant_id,
    product_family,
    scenario_id,
    available_qty,
    consensus_demand_qty,
    planned_demand_qty,
    reorder_qty,
    projected_inventory_after_plan,
    stockout_risk_before_plan,
    stockout_risk_after_plan,
    working_capital_impact
FROM dbo.gold_plan_vs_actual;

