CREATE TABLE dbo.PlanningWriteback (
    ScenarioId varchar(40) NOT NULL,
    ScenarioName varchar(120) NOT NULL,
    MaterialId varchar(40) NOT NULL,
    PlantId varchar(40) NOT NULL,
    Planner varchar(120) NULL,
    DemandUpliftPct decimal(9, 4) NOT NULL,
    SafetyStockDays int NOT NULL,
    LeadTimeOverrideDays int NULL,
    ReorderQty int NOT NULL,
    WorkingCapitalImpact decimal(18, 2) NULL,
    Comment varchar(1000) NULL,
    LastUpdatedAt datetime2 NOT NULL DEFAULT sysutcdatetime()
);

CREATE INDEX IX_PlanningWriteback_ScenarioMaterialPlant
ON dbo.PlanningWriteback (ScenarioId, MaterialId, PlantId);

