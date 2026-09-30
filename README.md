# Fabric Planning for SAP Inventory Demo

This repository is a sales-ready demo that shows how Microsoft Fabric can become the governed planning and AI layer over SAP-style operational data.

The demo uses dummy SAP S/4HANA-like data today and is structured so the source adapter can later be replaced with Business Process Solutions or real SAP extracts.

## Demo story

1. SAP-style actuals land in Fabric: materials, plants, inventory, sales orders, purchase orders, suppliers, goods receipts, and demand forecast.
2. Fabric curates actuals into inventory position, stockout risk, supplier performance, and baseline replenishment views.
3. Fabric Planning is used to adjust demand, safety stock, supplier lead time, and reorder assumptions.
4. Planning writeback is compared to current actuals and the baseline plan.
5. Power BI, Fabric Data Agent, and M365 Copilot questions explain what changed and why.

## What is automated

`scripts\Deploy-FabricDemo.ps1` automates the public Fabric REST API pieces:

- Azure sign-in against the supplied tenant.
- Fabric workspace creation.
- Optional capacity assignment if you provide a capacity ID.
- Lakehouse creation.
- Notebook creation or update with a load-and-model notebook.
- Notebook execution to seed dummy SAP-style data.
- Planning-compatible Import semantic model creation or update using the same curated demo data.
- Deployment summary output with item IDs and next-step URLs.

The clean demo needs only a workspace, lakehouse, notebook, and semantic model. Warehouse, ontology, Fabric SQL database, Data Agent, and preview Plan item creation are optional add-ons; they are not created by default because they add assets without improving the first-run Planning demo.

## Prerequisites

- Azure CLI.
- Permission to create Fabric workspaces in the tenant.
- Fabric capacity, Fabric trial capacity, or Power BI Premium capacity with Fabric enabled.
- Workspace Admin or Member permissions.
- Fabric Planning enabled in the tenant and region.
- For Data Agent and M365 Copilot: tenant settings for Fabric AI/Data Agent and Copilot experiences enabled.

## Quick start

### Azure Cloud Shell

```powershell
cd ~
git clone https://github.com/oahmad1/fabric-planning-sap-demo.git
cd ./fabric-planning-sap-demo

./scripts/Deploy-FabricDemo.ps1 `
  -TenantId "<tenant-id>" `
  -WorkspaceName "Fabric SAP Planning Demo" `
  -CapacityId "<fabric-capacity-guid-or-resource-id>" `
  -CompleteSetup `
  -WaitForNotebook
```

### Local PowerShell

```powershell
cd .\fabric-planning-sap-demo

.\scripts\Deploy-FabricDemo.ps1 `
  -TenantId "<tenant-id>" `
  -WorkspaceName "Fabric SAP Planning Demo" `
  -CapacityId "<fabric-capacity-id>" `
  -CompleteSetup `
  -WaitForNotebook
```

The command creates the API-supported Fabric items, starts the notebook that seeds the lakehouse, and creates or updates `SAP Planning Semantic Model` over the gold planning tables.

`-CapacityId` accepts either the Fabric capacity GUID or the full Azure resource ID for a `Microsoft.Fabric/capacities` resource. If you pass the full Azure resource ID, the script resolves it to the Fabric capacity GUID by listing capacities you can access.

Optional switches:

| Switch | Use when |
| --- | --- |
| `-CreateWarehouse` | You want a Warehouse shell for a SQL/reporting variant of the demo. Not needed for Planning. |
| `-CreateOntology` | You want to discuss Fabric ontology as an optional semantic layer. Not needed for Planning. |
| `-CreateSqlDatabase` | You want to attempt a separate writeback database. Not needed to start the Planning demo because Plan items create their own backing database. |
| `-AttemptPreviewAutomation` | You want to attempt tenant-supported preview item creation for Plan/Data Agent. Manual UI setup is still the reliable path. |

After deployment:

1. Open the generated `outputs\deployment-summary.json`.
2. Open `outputs\post-deployment-summary.json`.
3. Confirm the notebook job completed and `SAP Planning Semantic Model` was created or updated.
4. Confirm the semantic model has five tables: `gold_time_period`, `gold_inventory_position`, `gold_plan_vs_actual`, `gold_replenishment_plan`, and `gold_supplier_performance`.
5. Create a new Plan item in Fabric and connect it to `SAP Planning Semantic Model`.
6. In Planning time mapping, use `gold_time_period[period_start_date]`.
7. Use `docs\demo-script.md` to run the sales demo.

You can also run post-deployment setup separately:

```powershell
.\scripts\Complete-DemoSetup.ps1 `
  -DeploymentSummaryPath .\outputs\deployment-summary.json `
  -RunNotebook `
  -WaitForNotebook
```

## Subject areas

The dummy model covers the SAP subject areas that map cleanly to inventory/replenishment planning:

- Material master.
- Plant and storage location.
- Supplier/vendor master.
- Inventory balances.
- Sales orders and open demand.
- Purchase orders and inbound supply.
- Goods receipts and supplier lead-time performance.
- Demand forecast.
- Baseline and revised plan scenarios.

## Key demo questions

- Which products are at stockout risk in the next four weeks?
- What changed between the baseline plan and revised plan?
- Which supplier delays are driving the most inventory risk?
- How much working capital does the revised plan add?
- Which plants should planners focus on first?

See `docs\m365-copilot-questions.md` for M365 Chat and Fabric Data Agent prompts.

## Swap-in path for SAP/BPS

When SAP access is available, replace the dummy CSV/notebook source step with Business Process Solutions outputs or SAP S/4HANA extracts mapped to the same curated entities:

- Product/Material.
- Plant.
- Supplier.
- Demand.
- Supply.
- Inventory position.
- Planning scenario.

The downstream planning, Power BI, Data Agent, and optional ontology story can remain the same.
