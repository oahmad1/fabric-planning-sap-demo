# Ontology Design

The ontology is optional, but useful for the sales story because it lets business users ask planning questions in domain language instead of table language.

## Core concepts

| Concept | Description |
| --- | --- |
| Product | SAP material or product being planned. |
| Product Family | Grouping used for planning and executive reporting. |
| Plant | Location where demand, supply, and inventory are planned. |
| Supplier | Vendor providing inbound supply. |
| Demand | Forecast or open sales order demand. |
| Supply | Open purchase order or goods receipt signal. |
| Inventory Position | Current available quantity after allocations and quality holds. |
| Planning Scenario | Baseline or revised planner assumptions. |
| Inventory Risk | Risk classification derived from available inventory, demand, inbound supply, and supplier performance. |

## Relationships

- Product belongs to Product Family.
- Inventory Position is for Product at Plant.
- Demand is for Product at Plant.
- Supply is provided by Supplier for Product at Plant.
- Planning Scenario changes assumptions for Product at Plant.
- Inventory Risk is calculated from Inventory Position, Demand, Supply, and Planning Scenario.

## Ontology value

The ontology adds value when showing:

- Natural-language navigation across SAP-like entities.
- Reusable definitions for business terms such as available inventory and stockout risk.
- Agent grounding over business concepts rather than raw tables.
- Future extensibility to Business Process Solutions or real SAP data.

