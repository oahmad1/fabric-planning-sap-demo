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
| Ontology shell | Fabric REST `POST /v1/workspaces/{workspaceId}/ontologies` |

## Guided because public automation varies by tenant or feature state

| Asset | Why guided |
| --- | --- |
| Fabric Planning item and sheets | Planning items are not currently listed in the public Fabric REST item-management support matrix like Lakehouse, Warehouse, Notebook, and Ontology. |
| Fabric SQL database for Planning writeback | Current public docs show portal creation for Fabric SQL database. |
| Fabric Data Agent creation | Data Agent is generally available, but creation/configuration APIs are not exposed in the same public REST item-management pattern used by core items. |
| M365 Chat integration | Requires tenant Copilot/Fabric settings and user licensing; user experience can vary by rollout state. |

The repo still gives complete setup instructions for the guided pieces so the demo can be run end-to-end.

