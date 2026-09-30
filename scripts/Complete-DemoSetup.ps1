param(
    [string]$DeploymentSummaryPath = ".\outputs\deployment-summary.json",
    [switch]$RunNotebook,
    [switch]$WaitForNotebook,
    [switch]$CreateSqlDatabase,
    [switch]$AttemptPreviewItems,
    [int]$NotebookTimeoutMinutes = 30
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$summaryFullPath = if ([System.IO.Path]::IsPathRooted($DeploymentSummaryPath)) {
    $DeploymentSummaryPath
} else {
    Join-Path $repoRoot $DeploymentSummaryPath
}

if (-not (Test-Path $summaryFullPath)) {
    throw "Deployment summary not found: $summaryFullPath"
}

$summary = Get-Content $summaryFullPath -Raw | ConvertFrom-Json
$outputsDir = Join-Path $repoRoot "outputs"
New-Item -ItemType Directory -Force -Path $outputsDir | Out-Null

function Test-CommandExists {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-FabricHeaders {
    $token = az account get-access-token --resource "https://api.fabric.microsoft.com" --query accessToken -o tsv
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw "Unable to acquire Fabric API token. Run 'az login --tenant <tenant-id>' first."
    }
    return @{
        Authorization = "Bearer $token"
        "Content-Type" = "application/json"
    }
}

function Invoke-FabricApi {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("GET", "POST", "PATCH", "DELETE")]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Url,

        [object]$Body,
        [switch]$AllowFailure
    )

    $headers = Get-FabricHeaders
    $request = @{
        Method = $Method
        Uri = $Url
        Headers = $headers
    }
    if ($null -ne $Body) {
        $request.Body = ($Body | ConvertTo-Json -Depth 50)
    }

    try {
        $response = Invoke-WebRequest @request
        $content = $null
        if (-not [string]::IsNullOrWhiteSpace($response.Content)) {
            $content = $response.Content | ConvertFrom-Json
        }
        return [pscustomobject]@{
            StatusCode = [int]$response.StatusCode
            Headers = $response.Headers
            Content = $content
            RawContent = $response.Content
        }
    }
    catch {
        if ($AllowFailure) {
            return [pscustomobject]@{
                StatusCode = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
                Headers = @{}
                Content = $null
                RawContent = $_.Exception.Message
            }
        }
        throw
    }
}

function Get-LocationHeader {
    param($Headers)
    if ($Headers.Location) {
        return $Headers.Location
    }
    if ($Headers["Location"]) {
        return $Headers["Location"]
    }
    return $null
}

function Wait-FabricJob {
    param(
        [string]$Location,
        [int]$TimeoutMinutes
    )

    if ([string]::IsNullOrWhiteSpace($Location)) {
        Write-Warning "No job Location header returned. Check Fabric job history in the workspace."
        return "Unknown"
    }

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 20
        $result = Invoke-FabricApi -Method GET -Url $Location -AllowFailure
        $status = $null
        if ($result.Content) {
            $status = $result.Content.status
        }
        if ([string]::IsNullOrWhiteSpace($status)) {
            Write-Host "Notebook job status unavailable yet..."
            continue
        }
        Write-Host "Notebook job status: $status"
        if ($status -in @("Completed", "Succeeded")) {
            return $status
        }
        if ($status -in @("Failed", "Cancelled")) {
            throw "Notebook job ended with status $status. See Fabric job details for diagnostics."
        }
    }

    throw "Timed out waiting for notebook job after $TimeoutMinutes minutes."
}

function Get-FabricItemByName {
    param(
        [string]$Type,
        [string]$Name,
        [int]$TimeoutSeconds = 180
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    $workspaceId = $summary.workspaceId
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $url = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/items?type=$Type"
        $result = Invoke-FabricApi -Method GET -Url $url
        $item = @($result.Content.value) |
            Where-Object { $_.displayName -eq $Name } |
            Select-Object -First 1
        if ($item) {
            return $item
        }
        Start-Sleep -Seconds 10
    } while ((Get-Date) -lt $deadline)

    return $null
}

function Repair-DeploymentSummary {
    $changed = $false

    $lookups = @(
        @{ Type = "Lakehouse"; NameProperty = "lakehouseName"; IdProperty = "lakehouseId" },
        @{ Type = "Warehouse"; NameProperty = "warehouseName"; IdProperty = "warehouseId" },
        @{ Type = "Notebook"; NameProperty = "notebookName"; IdProperty = "notebookId" },
        @{ Type = "Ontology"; NameProperty = "ontologyName"; IdProperty = "ontologyId" }
    )

    foreach ($lookup in $lookups) {
        $name = $summary.($lookup.NameProperty)
        $id = $summary.($lookup.IdProperty)
        if ([string]::IsNullOrWhiteSpace($name) -or -not [string]::IsNullOrWhiteSpace($id)) {
            continue
        }

        Write-Host "Resolving missing $($lookup.Type) ID for '$name'..."
        $item = Get-FabricItemByName -Type $lookup.Type -Name $name
        if (-not $item) {
            throw "Could not find $($lookup.Type) '$name' in workspace $($summary.workspaceId). Wait a minute and rerun this script."
        }

        $summary.($lookup.IdProperty) = $item.id
        $changed = $true
        Write-Host "Resolved $($lookup.Type): $($item.id)"
    }

    if ($changed) {
        $summary | ConvertTo-Json -Depth 20 | Set-Content -Path $summaryFullPath -Encoding UTF8
        Write-Host "Updated deployment summary with resolved item IDs."
    }
}

function Start-SeedNotebook {
    $workspaceId = $summary.workspaceId
    $notebookId = $summary.notebookId
    $lakehouseId = $summary.lakehouseId
    $lakehouseName = $summary.lakehouseName

    $url = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/items/$notebookId/jobs/instances?jobType=RunNotebook"
    $body = @{
        executionData = @{
            configuration = @{
                defaultLakehouse = @{
                    name = $lakehouseName
                    id = $lakehouseId
                    workspaceId = $workspaceId
                }
                useStarterPool = $true
            }
        }
    }

    Write-Host "Starting notebook run to seed dummy SAP-style data..."
    $result = Invoke-FabricApi -Method POST -Url $url -Body $body
    $location = Get-LocationHeader -Headers $result.Headers
    if ($WaitForNotebook) {
        $status = Wait-FabricJob -Location $location -TimeoutMinutes $NotebookTimeoutMinutes
    } else {
        $status = "Submitted"
    }

    return [pscustomobject]@{
        status = $status
        location = $location
    }
}

function Get-SemanticModels {
    $workspaceId = $summary.workspaceId
    $url = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/items?type=SemanticModel"
    $result = Invoke-FabricApi -Method GET -Url $url
    return @($result.Content.value)
}

function Start-SemanticModelRefresh {
    param([string]$SemanticModelId)

    if ([string]::IsNullOrWhiteSpace($SemanticModelId)) {
        return
    }

    $workspaceId = $summary.workspaceId
    $url = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/items/$SemanticModelId/jobs/instances?jobType=Refresh"
    Write-Host "Refreshing semantic model $SemanticModelId..."
    $result = Invoke-FabricApi -Method POST -Url $url -AllowFailure
    if ($result.StatusCode -notin @(200, 202)) {
        Write-Warning "Semantic model refresh was not accepted: $($result.RawContent)"
    }
}

function ConvertTo-Base64String {
    param([string]$Value)
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
}

function New-TmdlTablePart {
    param(
        [string]$TableName,
        [array]$Columns,
        [string[]]$Measures = @()
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("table $TableName")
    $lines.Add("")
    foreach ($measure in $Measures) {
        $lines.Add($measure)
        $lines.Add("")
    }
    foreach ($column in $Columns) {
        $lines.Add("`tcolumn $($column.Name)")
        $lines.Add("`t`tdataType: $($column.Type)")
        if ($column.IsHidden) {
            $lines.Add("`t`tisHidden")
        }
        if ($column.IsKey) {
            $lines.Add("`t`tisKey")
        }
        if ($column.Type -eq "string") {
            $lines.Add("`t`tsummarizeBy: none")
        }
        $lines.Add("`t`tsourceColumn: $($column.Source)")
        $lines.Add("")
    }
    $lines.Add("`tpartition $TableName = entity")
    $lines.Add("`t`tmode: directLake")
    $lines.Add("`t`tsource")
    $lines.Add("`t`t`tentityName: $TableName")
    $lines.Add("`t`t`tschemaName: gold")
    $lines.Add("`t`t`texpressionSource: DL_Lakehouse")
    return ($lines -join "`n")
}

function New-Column {
    param(
        [string]$Name,
        [string]$Type,
        [switch]$IsKey,
        [switch]$IsHidden
    )
    return [pscustomobject]@{
        Name = $Name
        Source = $Name
        Type = $Type
        IsKey = [bool]$IsKey
        IsHidden = [bool]$IsHidden
    }
}

function ConvertTo-MValue {
    param(
        [object]$Value,
        [string]$Type
    )

    if ($null -eq $Value) {
        return "null"
    }

    switch ($Type) {
        "string" {
            return '"' + ([string]$Value).Replace('"', '""') + '"'
        }
        "dateTime" {
            $date = [datetime]$Value
            return "#datetime($($date.Year), $($date.Month), $($date.Day), 0, 0, 0)"
        }
        "decimal" {
            return ([Convert]::ToString([decimal]$Value, [Globalization.CultureInfo]::InvariantCulture))
        }
        default {
            return ([Convert]::ToString($Value, [Globalization.CultureInfo]::InvariantCulture))
        }
    }
}

function Get-MType {
    param([string]$Type)
    switch ($Type) {
        "string" { return "text" }
        "int64" { return "Int64.Type" }
        "decimal" { return "number" }
        "dateTime" { return "datetime" }
        default { return "text" }
    }
}

function New-ImportTablePart {
    param(
        [string]$TableName,
        [array]$Columns,
        [array]$Rows,
        [string[]]$Measures = @()
    )

    $schema = ($Columns | ForEach-Object { "$($_.Name) = $(Get-MType $_.Type)" }) -join ", "
    $rowText = ($Rows | ForEach-Object {
        $row = $_
        "                {" + (($Columns | ForEach-Object { ConvertTo-MValue $row[$_.Name] $_.Type }) -join ", ") + "}"
    }) -join ",`n"

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("table $TableName")
    $lines.Add("")
    foreach ($measure in $Measures) {
        $lines.Add($measure)
        $lines.Add("")
    }
    foreach ($column in $Columns) {
        $lines.Add("`tcolumn $($column.Name)")
        $lines.Add("`t`tdataType: $($column.Type)")
        if ($column.IsHidden) {
            $lines.Add("`t`tisHidden")
        }
        if ($column.IsKey) {
            $lines.Add("`t`tisKey")
        }
        if ($column.Type -eq "string") {
            $lines.Add("`t`tsummarizeBy: none")
        }
        $lines.Add("`t`tsourceColumn: $($column.Source)")
        $lines.Add("")
    }
    $lines.Add("`tpartition $TableName = m")
    $lines.Add("`t`tmode: import")
    $lines.Add("`t`tsource =")
    $lines.Add("`t`t`tlet")
    $lines.Add("`t`t`t`tSource = #table(")
    $lines.Add("`t`t`t`t`ttype table [$schema],")
    $lines.Add("`t`t`t`t`t{")
    $lines.Add($rowText)
    $lines.Add("`t`t`t`t`t}")
    $lines.Add("`t`t`t`t)")
    $lines.Add("`t`t`tin")
    $lines.Add("`t`t`t`tSource")
    return ($lines -join "`n")
}

function New-SemanticModelDefinition {
    $definitionPbism = @"
{
  "`$schema": "https://developer.microsoft.com/json-schemas/fabric/item/semanticModel/definitionProperties/1.0.0/schema.json",
  "version": "5.0",
  "settings": {
    "qnaEnabled": true
  }
}
"@

    $databaseTmdl = @"
database
	compatibilityLevel: 1702
	compatibilityMode: powerBI
"@

    $modelTmdl = @"
model Model
	culture: en-US
	defaultPowerBIDataSourceVersion: powerBI_V3
	discourageImplicitMeasures
"@

    $planMeasures = @(
        "`tmeasure 'Available Qty' = SUM('gold_plan_vs_actual'[available_qty])`n`t`tformatString: #,##0",
        "`tmeasure 'Planned Demand Qty' = SUM('gold_plan_vs_actual'[planned_demand_qty])`n`t`tformatString: #,##0",
        "`tmeasure 'Reorder Qty' = SUM('gold_plan_vs_actual'[reorder_qty])`n`t`tformatString: #,##0",
        "`tmeasure 'Working Capital Impact' = SUM('gold_plan_vs_actual'[working_capital_impact])`n`t`tformatString: `$#,##0",
        "`tmeasure 'Projected Inventory After Plan' = SUM('gold_plan_vs_actual'[projected_inventory_after_plan])`n`t`tformatString: #,##0",
        "`tmeasure 'High Risk Count' = COUNTROWS(FILTER('gold_plan_vs_actual', 'gold_plan_vs_actual'[stockout_risk_after_plan] = `"High`"))`n`t`tformatString: #,##0"
    )

    $timeRows = @(
        @{ time_period_id = 202610; period_start_date = "2026-10-01"; year = 2026; quarter = 4; month_number = 10; month_name = "October"; year_month = "2026-10" }
    )
    $planRows = @(
        @{ scenario_id = "BASELINE"; scenario_name = "Current baseline plan"; scenario_type = "Baseline"; material_id = "MAT-100"; material_name = "Contoso Smart Sensor"; product_family = "Electronics"; plant_id = "PL-30"; plant_name = "Atlanta Fulfillment Center"; region = "East"; planning_owner = "Jordan Planner"; forecast_month = "2026-10"; forecast_month_start = "2026-10-01"; time_period_id = 202610; available_qty = 70; open_purchase_order_qty = 300; open_sales_order_qty = 220; baseline_demand_qty = 560; consensus_demand_qty = 680; planned_demand_qty = 680; safety_stock_days = 10; lead_time_override_days = 31; reorder_qty = 450; projected_inventory_after_plan = 140; stockout_risk_before_plan = "High"; stockout_risk_after_plan = "Medium"; working_capital_impact = 18900; supplier_delay_risk = "High" }
        @{ scenario_id = "REV1"; scenario_name = "Planner revised replenishment"; scenario_type = "Revised"; material_id = "MAT-100"; material_name = "Contoso Smart Sensor"; product_family = "Electronics"; plant_id = "PL-30"; plant_name = "Atlanta Fulfillment Center"; region = "East"; planning_owner = "Jordan Planner"; forecast_month = "2026-10"; forecast_month_start = "2026-10-01"; time_period_id = 202610; available_qty = 70; open_purchase_order_qty = 300; open_sales_order_qty = 220; baseline_demand_qty = 560; consensus_demand_qty = 680; planned_demand_qty = 734; safety_stock_days = 15; lead_time_override_days = 36; reorder_qty = 620; projected_inventory_after_plan = 256; stockout_risk_before_plan = "High"; stockout_risk_after_plan = "Low"; working_capital_impact = 26040; supplier_delay_risk = "High" }
        @{ scenario_id = "BASELINE"; scenario_name = "Current baseline plan"; scenario_type = "Baseline"; material_id = "MAT-400"; material_name = "AdventureWorks Battery Pack"; product_family = "Electronics"; plant_id = "PL-20"; plant_name = "Chicago Manufacturing Hub"; region = "Central"; planning_owner = "Casey Planner"; forecast_month = "2026-10"; forecast_month_start = "2026-10-01"; time_period_id = 202610; available_qty = 70; open_purchase_order_qty = 420; open_sales_order_qty = 360; baseline_demand_qty = 610; consensus_demand_qty = 790; planned_demand_qty = 790; safety_stock_days = 10; lead_time_override_days = 31; reorder_qty = 520; projected_inventory_after_plan = 220; stockout_risk_before_plan = "High"; stockout_risk_after_plan = "Medium"; working_capital_impact = 18200; supplier_delay_risk = "High" }
        @{ scenario_id = "REV1"; scenario_name = "Planner revised replenishment"; scenario_type = "Revised"; material_id = "MAT-400"; material_name = "AdventureWorks Battery Pack"; product_family = "Electronics"; plant_id = "PL-20"; plant_name = "Chicago Manufacturing Hub"; region = "Central"; planning_owner = "Casey Planner"; forecast_month = "2026-10"; forecast_month_start = "2026-10-01"; time_period_id = 202610; available_qty = 70; open_purchase_order_qty = 420; open_sales_order_qty = 360; baseline_demand_qty = 610; consensus_demand_qty = 790; planned_demand_qty = 884; safety_stock_days = 16; lead_time_override_days = 38; reorder_qty = 760; projected_inventory_after_plan = 366; stockout_risk_before_plan = "High"; stockout_risk_after_plan = "Low"; working_capital_impact = 26600; supplier_delay_risk = "High" }
        @{ scenario_id = "REV1"; scenario_name = "Planner revised replenishment"; scenario_type = "Revised"; material_id = "MAT-300"; material_name = "Northwind Pump Kit"; product_family = "Industrial"; plant_id = "PL-20"; plant_name = "Chicago Manufacturing Hub"; region = "Central"; planning_owner = "Casey Planner"; forecast_month = "2026-10"; forecast_month_start = "2026-10-01"; time_period_id = 202610; available_qty = 25; open_purchase_order_qty = 240; open_sales_order_qty = 190; baseline_demand_qty = 390; consensus_demand_qty = 470; planned_demand_qty = 517; safety_stock_days = 12; lead_time_override_days = 24; reorder_qty = 390; projected_inventory_after_plan = 138; stockout_risk_before_plan = "High"; stockout_risk_after_plan = "Medium"; working_capital_impact = 46020; supplier_delay_risk = "Medium" }
    )
    $inventoryRows = $planRows |
        Where-Object { $_.scenario_id -eq "REV1" } |
        ForEach-Object {
            @{
                snapshot_date = "2026-09-01"; material_id = $_.material_id; material_name = $_.material_name; product_family = $_.product_family; unit_cost = if ($_.material_id -eq "MAT-300") { 118 } elseif ($_.material_id -eq "MAT-400") { 35 } else { 42 }; plant_id = $_.plant_id; plant_name = $_.plant_name; region = $_.region; planning_owner = $_.planning_owner; forecast_month = $_.forecast_month; forecast_month_start = $_.forecast_month_start; time_period_id = $_.time_period_id; on_hand_qty = $_.available_qty + 390; allocated_qty = 390; quality_hold_qty = 0; available_qty = $_.available_qty; open_sales_order_qty = $_.open_sales_order_qty; baseline_demand_qty = $_.baseline_demand_qty; consensus_demand_qty = $_.consensus_demand_qty; open_purchase_order_qty = $_.open_purchase_order_qty; supplier_delay_risk = $_.supplier_delay_risk; stockout_risk_before_plan = $_.stockout_risk_before_plan
            }
        }
    $supplierRows = @(
        @{ supplier_id = "SUP-01"; supplier_name = "Alpine Components"; country = "US"; risk_tier = "Low"; standard_lead_time_days = 12; avg_days_late = 1; supplier_delay_risk = "Low" }
        @{ supplier_id = "SUP-02"; supplier_name = "Blue Yonder Metals"; country = "MX"; risk_tier = "Medium"; standard_lead_time_days = 18; avg_days_late = 2; supplier_delay_risk = "Medium" }
        @{ supplier_id = "SUP-03"; supplier_name = "Contoso Electronics"; country = "TW"; risk_tier = "High"; standard_lead_time_days = 31; avg_days_late = 6; supplier_delay_risk = "High" }
    )
    $replenishmentRows = $planRows | ForEach-Object {
        @{ scenario_id = $_.scenario_id; scenario_name = $_.scenario_name; scenario_type = $_.scenario_type; material_id = $_.material_id; material_name = $_.material_name; product_family = $_.product_family; plant_id = $_.plant_id; plant_name = $_.plant_name; region = $_.region; planning_owner = $_.planning_owner; demand_uplift_pct = if ($_.scenario_id -eq "REV1") { 0.10 } else { 0.00 }; safety_stock_days = $_.safety_stock_days; lead_time_override_days = $_.lead_time_override_days; reorder_qty = $_.reorder_qty; working_capital_impact = $_.working_capital_impact }
    }

    $tables = @(
        @{
            Path = "definition/tables/gold_time_period.tmdl"
            Content = New-ImportTablePart -TableName "gold_time_period" -Rows $timeRows -Columns @(
                New-Column "time_period_id" "int64" -IsKey
                New-Column "period_start_date" "dateTime"
                New-Column "year" "int64"
                New-Column "quarter" "int64"
                New-Column "month_number" "int64"
                New-Column "month_name" "string"
                New-Column "year_month" "string"
            )
        }
        @{
            Path = "definition/tables/gold_plan_vs_actual.tmdl"
            Content = New-ImportTablePart -TableName "gold_plan_vs_actual" -Rows $planRows -Measures $planMeasures -Columns @(
                New-Column "scenario_id" "string"
                New-Column "scenario_name" "string"
                New-Column "scenario_type" "string"
                New-Column "material_id" "string"
                New-Column "material_name" "string"
                New-Column "product_family" "string"
                New-Column "plant_id" "string"
                New-Column "plant_name" "string"
                New-Column "region" "string"
                New-Column "planning_owner" "string"
                New-Column "forecast_month" "string"
                New-Column "forecast_month_start" "dateTime"
                New-Column "time_period_id" "int64"
                New-Column "available_qty" "int64"
                New-Column "open_purchase_order_qty" "int64"
                New-Column "open_sales_order_qty" "int64"
                New-Column "baseline_demand_qty" "int64"
                New-Column "consensus_demand_qty" "int64"
                New-Column "planned_demand_qty" "int64"
                New-Column "safety_stock_days" "int64"
                New-Column "lead_time_override_days" "int64"
                New-Column "reorder_qty" "int64"
                New-Column "projected_inventory_after_plan" "int64"
                New-Column "stockout_risk_before_plan" "string"
                New-Column "stockout_risk_after_plan" "string"
                New-Column "working_capital_impact" "decimal"
                New-Column "supplier_delay_risk" "string"
            )
        }
        @{
            Path = "definition/tables/gold_inventory_position.tmdl"
            Content = New-ImportTablePart -TableName "gold_inventory_position" -Rows $inventoryRows -Columns @(
                New-Column "snapshot_date" "string"
                New-Column "material_id" "string"
                New-Column "material_name" "string"
                New-Column "product_family" "string"
                New-Column "unit_cost" "decimal"
                New-Column "plant_id" "string"
                New-Column "plant_name" "string"
                New-Column "region" "string"
                New-Column "planning_owner" "string"
                New-Column "forecast_month" "string"
                New-Column "forecast_month_start" "dateTime"
                New-Column "time_period_id" "int64"
                New-Column "on_hand_qty" "int64"
                New-Column "allocated_qty" "int64"
                New-Column "quality_hold_qty" "int64"
                New-Column "available_qty" "int64"
                New-Column "open_sales_order_qty" "int64"
                New-Column "baseline_demand_qty" "int64"
                New-Column "consensus_demand_qty" "int64"
                New-Column "open_purchase_order_qty" "int64"
                New-Column "supplier_delay_risk" "string"
                New-Column "stockout_risk_before_plan" "string"
            )
        }
        @{
            Path = "definition/tables/gold_supplier_performance.tmdl"
            Content = New-ImportTablePart -TableName "gold_supplier_performance" -Rows $supplierRows -Columns @(
                New-Column "supplier_id" "string"
                New-Column "supplier_name" "string"
                New-Column "country" "string"
                New-Column "risk_tier" "string"
                New-Column "standard_lead_time_days" "int64"
                New-Column "avg_days_late" "decimal"
                New-Column "supplier_delay_risk" "string"
            )
        }
        @{
            Path = "definition/tables/gold_replenishment_plan.tmdl"
            Content = New-ImportTablePart -TableName "gold_replenishment_plan" -Rows $replenishmentRows -Columns @(
                New-Column "scenario_id" "string"
                New-Column "scenario_name" "string"
                New-Column "scenario_type" "string"
                New-Column "material_id" "string"
                New-Column "material_name" "string"
                New-Column "product_family" "string"
                New-Column "plant_id" "string"
                New-Column "plant_name" "string"
                New-Column "region" "string"
                New-Column "planning_owner" "string"
                New-Column "demand_uplift_pct" "decimal"
                New-Column "safety_stock_days" "int64"
                New-Column "lead_time_override_days" "int64"
                New-Column "reorder_qty" "int64"
                New-Column "working_capital_impact" "decimal"
            )
        }
    )

    $relationshipsTmdl = @"
relationship 'Plan vs Actual to Date'
	fromColumn: gold_plan_vs_actual.time_period_id
	toColumn: gold_time_period.time_period_id

relationship 'Inventory Position to Date'
	fromColumn: gold_inventory_position.time_period_id
	toColumn: gold_time_period.time_period_id
"@

    $parts = @(
        @{ path = "definition.pbism"; payload = ConvertTo-Base64String $definitionPbism; payloadType = "InlineBase64" },
        @{ path = "definition/database.tmdl"; payload = ConvertTo-Base64String $databaseTmdl; payloadType = "InlineBase64" },
        @{ path = "definition/model.tmdl"; payload = ConvertTo-Base64String $modelTmdl; payloadType = "InlineBase64" },
        @{ path = "definition/relationships.tmdl"; payload = ConvertTo-Base64String $relationshipsTmdl; payloadType = "InlineBase64" }
    )

    foreach ($table in $tables) {
        $parts += @{ path = $table.Path; payload = ConvertTo-Base64String $table.Content; payloadType = "InlineBase64" }
    }

    return @{
        format = "TMDL"
        parts = $parts
    }
}

function Try-CreateSemanticModel {
    $workspaceId = $summary.workspaceId
    $modelName = "SAP Planning Semantic Model"
    $existing = Get-SemanticModels |
        Where-Object { $_.displayName -eq $modelName } |
        Select-Object -First 1
    if ($existing) {
        Write-Host "Updating semantic model '$modelName' with Planning-compatible import tables..."
        $updateUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/semanticModels/$($existing.id)/updateDefinition"
        $updateResult = Invoke-FabricApi -Method POST -Url $updateUrl -Body @{ definition = New-SemanticModelDefinition } -AllowFailure
        if ($updateResult.StatusCode -notin @(200, 202)) {
            Write-Warning "Semantic model update was not accepted: $($updateResult.RawContent)"
        }
        else {
            Start-SemanticModelRefresh -SemanticModelId $existing.id
        }
        return $existing
    }

    Write-Host "Creating semantic model '$modelName' over gold lakehouse tables..."
    $body = @{
        displayName = $modelName
        description = "Import semantic model with Planning-compatible SAP-style inventory planning demo data."
        definition = New-SemanticModelDefinition
    }
    $url = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/semanticModels"
    $result = Invoke-FabricApi -Method POST -Url $url -Body $body -AllowFailure

    if ($result.StatusCode -notin @(200, 201, 202)) {
        Write-Warning "Semantic model creation was not accepted: $($result.RawContent)"
        return $null
    }

    $deadline = (Get-Date).AddMinutes(5)
    do {
        Start-Sleep -Seconds 10
        $created = Get-SemanticModels |
            Where-Object { $_.displayName -eq $modelName } |
            Select-Object -First 1
        if ($created) {
            Write-Host "Semantic model created: $($created.id)"
            Start-SemanticModelRefresh -SemanticModelId $created.id
            return $created
        }
    } while ((Get-Date) -lt $deadline)

    Write-Warning "Semantic model creation was accepted but the model was not discoverable yet. Check the Fabric workspace in a minute."
    return $null
}

function Try-CreateSqlDatabase {
    $workspaceId = $summary.workspaceId
    $dbName = "PlanningWriteback"

    Write-Host "Attempting to create Fabric SQL database '$dbName'..."
    $url = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/sqlDatabases"
    $result = Invoke-FabricApi -Method POST -Url $url -Body @{ displayName = $dbName } -AllowFailure
    if ($result.StatusCode -in @(200, 201, 202)) {
        return [pscustomobject]@{
            status = "CreatedOrAccepted"
            itemName = $dbName
            result = $result.Content
            note = "If sqlcmd is available, run sql\planning_writeback_schema.sql against this database."
        }
    }

    $fallbackUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/items"
    $fallback = Invoke-FabricApi -Method POST -Url $fallbackUrl -Body @{
        displayName = $dbName
        type = "SQLDatabase"
        description = "Planning writeback database for the SAP inventory planning demo."
    } -AllowFailure

    if ($fallback.StatusCode -in @(200, 201, 202)) {
        return [pscustomobject]@{
            status = "CreatedOrAccepted"
            itemName = $dbName
            result = $fallback.Content
            note = "Created using generic item endpoint with type SQLDatabase."
        }
    }

    return [pscustomobject]@{
        status = "ManualRequired"
        itemName = $dbName
        note = "Fabric SQL database creation was not accepted by the public endpoints in this tenant. Create it in the Fabric portal, then run sql\planning_writeback_schema.sql."
        endpointResponse = $result.RawContent
        fallbackResponse = $fallback.RawContent
    }
}

function Try-CreatePreviewItem {
    param(
        [string]$DisplayName,
        [string]$Type,
        [string]$Description
    )

    $workspaceId = $summary.workspaceId
    $url = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/items"
    $result = Invoke-FabricApi -Method POST -Url $url -Body @{
        displayName = $DisplayName
        type = $Type
        description = $Description
    } -AllowFailure

    if ($result.StatusCode -in @(200, 201, 202)) {
        return [pscustomobject]@{
            status = "CreatedOrAccepted"
            itemName = $DisplayName
            itemType = $Type
            result = $result.Content
        }
    }

    return [pscustomobject]@{
        status = "ManualRequired"
        itemName = $DisplayName
        itemType = $Type
        note = "This item type was not accepted by the public item API in this tenant. Use the guided setup docs."
        response = $result.RawContent
    }
}

if (-not (Test-CommandExists -Name "az")) {
    throw "Azure CLI is required."
}

Write-Host "Using deployment summary: $summaryFullPath"
Repair-DeploymentSummary
$postSetup = [ordered]@{
    workspaceId = $summary.workspaceId
    lakehouseId = $summary.lakehouseId
    notebookId = $summary.notebookId
    notebookRun = $null
    semanticModels = @()
    selectedSemanticModel = $null
    planningWritebackDatabase = $null
    previewItems = @()
    nextSteps = @()
}

if ($RunNotebook) {
    $postSetup.notebookRun = Start-SeedNotebook
}

$semanticModels = Get-SemanticModels
if (@($semanticModels).Count -eq 0) {
    $createdModel = Try-CreateSemanticModel
    if ($createdModel) {
        $semanticModels = Get-SemanticModels
    }
}
$postSetup.semanticModels = $semanticModels | Select-Object id, displayName, type
$selectedModel = $semanticModels |
    Where-Object { $_.displayName -eq $summary.lakehouseName -or $_.displayName -like "*$($summary.lakehouseName)*" } |
    Select-Object -First 1
if (-not $selectedModel) {
    $selectedModel = $semanticModels | Select-Object -First 1
}
if ($selectedModel) {
    $postSetup.selectedSemanticModel = $selectedModel | Select-Object id, displayName, type
} else {
    $postSetup.nextSteps += "No semantic model was discovered. After the notebook creates gold tables, create or refresh a semantic model over gold_inventory_position, gold_supplier_performance, gold_replenishment_plan, and gold_plan_vs_actual."
}

if ($CreateSqlDatabase) {
    $postSetup.planningWritebackDatabase = Try-CreateSqlDatabase
} else {
    $postSetup.nextSteps += "Create a new Plan item in Fabric and connect it to SAP Planning Semantic Model. Use gold_time_period[period_start_date] for time mapping."
}

if ($AttemptPreviewItems) {
    $postSetup.previewItems += Try-CreatePreviewItem -DisplayName "SAP Planning Data Agent" -Type "DataAgent" -Description "Data Agent for SAP-style inventory planning demo."
    $postSetup.previewItems += Try-CreatePreviewItem -DisplayName "SAP Inventory Planning" -Type "Planning" -Description "Fabric Planning item for actuals vs baseline vs revised inventory plan."
}
else {
    $postSetup.nextSteps += "Create the Fabric Planning item using docs\fabric-planning-setup.md."
    $postSetup.nextSteps += "Create the Fabric Data Agent using agents\data-agent-instructions.md."
}

$postSetup.nextSteps += "Use docs\demo-script.md and docs\m365-copilot-questions.md for the sales demo."

$postSetupPath = Join-Path $outputsDir "post-deployment-summary.json"
$postSetup | ConvertTo-Json -Depth 20 | Set-Content -Path $postSetupPath -Encoding UTF8

Write-Host ""
Write-Host "Post-deployment setup complete."
Write-Host "Summary: $postSetupPath"
