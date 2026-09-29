# Automation Support

The repo automates the Fabric APIs that are publicly documented for workspace and item management.

## Automated

| Asset | Method |
| --- | --- |
| Workspace | Fabric REST `POST /v1/workspaces` |
| Capacity assignment | Fabric REST `POST /v1/workspaces/{workspaceId}/assignToCapacity` |
| Lakehouse | Fabric REST `POST /v1/workspaces/{workspaceId}/lakehouses` |
| Warehouse | Fabric REST `POST /v1/workspaces/{workspaceId}/warehouses` |
| Notebook | Fabric REST `POST /v1/workspaces/{workspaceId}/notebooks` with ipynb definition |
| Notebook execution | Fabric job scheduler with `jobType=RunNotebook` |
| Ontology shell | Fabric REST `POST /v1/workspaces/{workspaceId}/ontologies` |
| Default semantic model discovery | Fabric item listing for `SemanticModel` |

## Attempted when requested

`scripts\Complete-DemoSetup.ps1 -AttemptPreviewItems -CreateSqlDatabase` attempts tenant-supported or preview item creation for:

- Fabric SQL database named `PlanningWriteback`.
- Data Agent named `SAP Planning Data Agent`.
- Planning item named `SAP Inventory Planning`.

If the tenant rejects an item type through the public API, the script records `ManualRequired` in `outputs\post-deployment-summary.json` and points to the guided setup docs.

## Guided because public automation varies by tenant or feature state

| Asset | Why guided |
| --- | --- |
| Fabric Planning item and sheets | Planning items are not currently listed in the public Fabric REST item-management support matrix like Lakehouse, Warehouse, Notebook, and Ontology. |
| Fabric SQL database for Planning writeback | The script attempts known endpoints, but public portal docs remain the reliable path when tenants reject API creation. |
| Fabric Data Agent creation | The script attempts generic item creation when requested, but configuration APIs are not exposed in the same public REST item-management pattern used by core items. |
| M365 Chat integration | Requires tenant Copilot/Fabric settings and user licensing; user experience can vary by rollout state. |

The repo still gives complete setup instructions for the guided pieces so the demo can be run end-to-end.
