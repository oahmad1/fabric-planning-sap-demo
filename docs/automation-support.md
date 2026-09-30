# Automation Support

The repo automates the stable Fabric API pieces needed for the first-run demo. Optional assets are available behind switches so the default deployment stays clean.

## Default automated assets

| Asset | Why it exists |
| --- | --- |
| Workspace | Container for the demo. |
| Lakehouse | Stores dummy SAP-style actuals and curated gold planning tables. |
| Notebook | Loads dummy data and creates the gold tables. Redeploys update the notebook definition. |
| Semantic model | Planning-compatible Import model seeded with the same curated demo data, including `gold_time_period` for Planning time mapping. |

## Optional assets

| Switch | Asset | Use when |
| --- | --- | --- |
| `-CreateWarehouse` | Warehouse shell | You want a SQL/reporting variant. Not needed for Planning. |
| `-CreateOntology` | Ontology shell | You want to discuss Fabric ontology as an optional business-semantic layer. Not needed for Planning. |
| `-CreateSqlDatabase` | `PlanningWriteback` SQL database attempt | You want to test separate SQL writeback. Not needed for the first-run demo. |
| `-AttemptPreviewAutomation` | Plan/Data Agent item creation attempts | You want to test tenant-supported preview automation. Manual UI setup remains more reliable. |

## Guided because public automation varies by tenant or feature state

| Asset | Why guided |
| --- | --- |
| Fabric Planning item and sheets | Planning item configuration and sheet layout are tenant-feature dependent and connection-sensitive. |
| Fabric Data Agent configuration | Data Agent creation/configuration APIs are not exposed in the same public REST item-management pattern used by core items. |
| M365 Chat integration | Requires tenant Copilot/Fabric settings and user licensing; user experience can vary by rollout state. |

The default command produces the data foundation and semantic model. Then create a new Plan item in the portal and connect it to `SAP Planning Semantic Model`.
