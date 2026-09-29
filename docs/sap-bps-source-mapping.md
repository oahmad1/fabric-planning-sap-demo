# SAP and Business Process Solutions Source Mapping

Use this mapping when replacing the dummy data with Business Process Solutions or SAP S/4HANA extracts.

| Demo entity | SAP/BPS subject area | Typical source concept |
| --- | --- | --- |
| Material | Procurement, sales, inventory | Material master |
| Plant | Procurement, inventory | Plant / storage location |
| Supplier | Procurement | Vendor / supplier master |
| Inventory snapshot | Inventory | Stock on hand, allocated stock, quality hold |
| Sales order demand | Sales | Open sales order schedule lines |
| Purchase order supply | Procurement | Open purchase orders |
| Goods receipt | Procurement, inventory | Goods movement / goods receipt |
| Demand forecast | Planning/sales | Forecast, consensus demand, or demand planning extract |
| Planning scenario | Fabric Planning | Baseline and revised planning assumptions |

## Minimum viable SAP/BPS subject areas

For the first SAP-connected version, pull these:

1. Material master.
2. Plant/storage location.
3. Supplier/vendor master.
4. Inventory balance.
5. Open sales orders.
6. Open purchase orders.
7. Goods receipt history.
8. Forecast or demand signal.

## Why this scope works for sales teams

It keeps the story focused on inventory and replenishment planning. That lets sellers show SAP actuals, Fabric harmonization, Fabric Planning writeback, Power BI visuals, and Copilot/Data Agent questions without needing a full SAP replacement narrative.

