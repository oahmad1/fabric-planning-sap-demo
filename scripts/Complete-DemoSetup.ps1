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

function New-SemanticModelDefinition {
    $workspaceId = $summary.workspaceId
    $lakehouseId = $summary.lakehouseId
    $oneLakeUrl = "https://onelake.dfs.fabric.microsoft.com/$workspaceId/$lakehouseId"

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

expression DL_Lakehouse =
	let
		Source = AzureStorage.DataLake("$oneLakeUrl", [HierarchicalNavigation=true])
	in
		Source
"@

    $planMeasures = @(
        "`tmeasure 'Available Qty' = SUM('gold_plan_vs_actual'[available_qty])`n`t`tformatString: #,##0",
        "`tmeasure 'Planned Demand Qty' = SUM('gold_plan_vs_actual'[planned_demand_qty])`n`t`tformatString: #,##0",
        "`tmeasure 'Reorder Qty' = SUM('gold_plan_vs_actual'[reorder_qty])`n`t`tformatString: #,##0",
        "`tmeasure 'Working Capital Impact' = SUM('gold_plan_vs_actual'[working_capital_impact])`n`t`tformatString: `$#,##0",
        "`tmeasure 'Projected Inventory After Plan' = SUM('gold_plan_vs_actual'[projected_inventory_after_plan])`n`t`tformatString: #,##0",
        "`tmeasure 'High Risk Count' = COUNTROWS(FILTER('gold_plan_vs_actual', 'gold_plan_vs_actual'[stockout_risk_after_plan] = `"High`"))`n`t`tformatString: #,##0"
    )

    $tables = @(
        @{
            Path = "definition/tables/gold_date.tmdl"
            Content = New-TmdlTablePart -TableName "gold_date" -Columns @(
                New-Column "date" "dateTime" -IsKey
                New-Column "year" "int64"
                New-Column "quarter" "int64"
                New-Column "month_number" "int64"
                New-Column "month_name" "string"
                New-Column "year_month" "string"
            )
        }
        @{
            Path = "definition/tables/gold_plan_vs_actual.tmdl"
            Content = New-TmdlTablePart -TableName "gold_plan_vs_actual" -Measures $planMeasures -Columns @(
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
            Content = New-TmdlTablePart -TableName "gold_inventory_position" -Columns @(
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
            Content = New-TmdlTablePart -TableName "gold_supplier_performance" -Columns @(
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
            Content = New-TmdlTablePart -TableName "gold_replenishment_plan" -Columns @(
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
	fromColumn: gold_plan_vs_actual.forecast_month_start
	toColumn: gold_date.date

relationship 'Inventory Position to Date'
	fromColumn: gold_inventory_position.forecast_month_start
	toColumn: gold_date.date
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
        Write-Host "Updating semantic model '$modelName' with planning date metadata..."
        $updateUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/semanticModels/$($existing.id)/updateDefinition"
        $updateResult = Invoke-FabricApi -Method POST -Url $updateUrl -Body @{ definition = New-SemanticModelDefinition } -AllowFailure
        if ($updateResult.StatusCode -notin @(200, 202)) {
            Write-Warning "Semantic model update was not accepted: $($updateResult.RawContent)"
        }
        return $existing
    }

    Write-Host "Creating semantic model '$modelName' over gold lakehouse tables..."
    $body = @{
        displayName = $modelName
        description = "Direct Lake semantic model over SAP-style inventory planning gold tables."
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
    $postSetup.nextSteps += "Run this script with -CreateSqlDatabase to attempt Fabric SQL database creation, or create PlanningWriteback manually in the Fabric portal."
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
