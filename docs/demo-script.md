# Sales Demo Script: SAP-Powered Inventory Planning in Fabric

## One-line story

Fabric turns SAP actuals into a live planning decision: detect inventory risk, explain the cause, simulate a response, and show the service-level and working-capital tradeoff.

## Audience

Sales teams, SAP account teams, Fabric sellers, solution specialists, and customer executives evaluating Fabric Planning, SAP modernization, and AI-powered business processes.

## Positioning

This demo is not trying to replace SAP as the system of record. SAP remains where operational transactions live. Fabric becomes the governed decision layer where SAP actuals, forecast, supplier risk, planning assumptions, Power BI, and Copilot-style Q&A come together.

## Demo setup

Default automated deployment creates:

- `SAPPlanningLakehouse` with dummy SAP-style operational data and curated gold tables.
- `Load SAP Planning Demo` notebook to seed and shape the data.
- `SAP Planning Semantic Model`, a Planning-compatible import model with the same curated demo data.

Manual setup:

- Create a new Plan item.
- Connect it to `SAP Planning Semantic Model`.
- Create a Planning sheet using the fields below.

## Opening narrative

> "A demand spike hits Electronics. SAP has the actual inventory, open demand, and purchase orders, but the planning decision still happens in spreadsheets. The planner needs to decide whether to invest more working capital to protect service levels. Fabric brings that decision into the governed data estate."

## Scene 1: Show the problem

Open the Planning sheet or semantic model fields and show:

- Product family: Electronics and Industrial.
- Materials: Contoso Smart Sensor, AdventureWorks Battery Pack, Northwind Pump Kit.
- Plants: Atlanta and Chicago.
- Scenario: Current baseline plan vs Planner revised replenishment.

Talk track:

> "The baseline plan keeps working capital lower, but several material/plant combinations remain at elevated stockout risk. Supplier delay risk is also high for key electronics components."

Recommended sheet fields:

Rows:

- `product_family`
- `material_name`
- `plant_name`

Columns:

- `scenario_name`

Values:

- `Available Qty`
- `Planned Demand Qty`
- `Reorder Qty`
- `Projected Inventory After Plan`
- `Working Capital Impact`
- `Working Capital Delta`
- `High Risk Before Count`
- `High Risk After Count`
- `Risk Reduction Count`
- `Service Level Before %`
- `Service Level After %`
- `Service Level Improvement %`

## Scene 2: Make the planning decision

Focus on `AdventureWorks Battery Pack` in `Chicago Manufacturing Hub`.

Talk track:

> "The revised plan increases reorder quantity and safety stock because the supplier is high risk and demand is elevated. This raises working capital, but improves projected inventory and reduces high-risk exposure."

Point to:

- Working Capital Delta.
- Service Level Improvement %.
- Risk Reduction Count.
- Projected Inventory After Plan.

## Scene 3: Explain the tradeoff

Use this sentence:

> "This is the business tradeoff: invest more inventory now to protect service level, or keep working capital lower and accept stockout risk."

Call out that sellers should not position this as a spreadsheet replacement only. The stronger message is:

> "The plan is connected to governed enterprise data, not a copy/paste workbook."

## Scene 4: Add AI/Data Agent narrative

If a Fabric Data Agent is configured, ask:

> "What changed between the baseline plan and revised replenishment plan?"

Expected response:

- Reorder quantities increased for high-risk material/plant combinations.
- Working capital increased.
- Projected inventory and service level improved.
- Supplier delay risk is concentrated in electronics components.

If M365 Copilot integration is available, ask:

> "Summarize the revised inventory plan for a supply chain VP."

## Scene 5: Connect to SAP and Business Process Solutions

Talk track:

> "Today this is dummy SAP-style data. With Business Process Solutions, the same subject areas can come from SAP S/4HANA or ECC: material master, plants, inventory balances, sales orders, purchase orders, goods receipts, suppliers, and forecast. Fabric Planning then sits on top of that governed model."

## Competitive positioning

| Competitor | Sales positioning |
| --- | --- |
| SAP Analytics Cloud / SAP IBP | Fabric plans across SAP and non-SAP data in OneLake, with Power BI and Copilot experiences in the same platform. |
| Anaplan | Fabric avoids creating another planning silo; planning uses the same data estate, semantic model, governance, and AI stack. |
| Excel | Familiar planning interaction, but connected, governed, shared, and auditable. |
| Kinaxis / Blue Yonder / o9 | Fabric is not replacing deep supply-chain optimization; it is ideal for flexible executive scenario planning and cross-domain decision apps. |
| OneStream / Board / Pigment | Fabric combines data engineering, semantic modeling, reporting, AI, and planning in one SaaS analytics estate. |

## Close

> "This is Fabric as the decision layer over SAP: actuals, forecast, planning assumptions, risk explanation, and financial impact in one governed experience."

