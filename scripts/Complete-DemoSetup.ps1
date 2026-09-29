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

