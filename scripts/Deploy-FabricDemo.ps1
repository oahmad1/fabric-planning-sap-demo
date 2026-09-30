param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceName,

    [string]$CapacityId,
    [string]$LakehouseName = "SAPPlanningLakehouse",
    [string]$WarehouseName = "SAPPlanningWarehouse",
    [string]$NotebookName = "Load SAP Planning Demo",
    [string]$OntologyName = "SAP_Planning_Ontology",
    [switch]$CreateWarehouse,
    [switch]$CreateOntology,
    [switch]$CompleteSetup,
    [switch]$WaitForNotebook,
    [switch]$CreateSqlDatabase,
    [switch]$AttemptPreviewAutomation
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$outputsDir = Join-Path $repoRoot "outputs"
New-Item -ItemType Directory -Force -Path $outputsDir | Out-Null

$CapacityNameHint = $null
if (-not [string]::IsNullOrWhiteSpace($CapacityId) -and $CapacityId -match "/capacities/([^/]+)$") {
    $CapacityNameHint = $Matches[1]
    Write-Host "Extracted Fabric capacity resource name from Azure resource ID: $CapacityNameHint"
}
elseif (-not [string]::IsNullOrWhiteSpace($CapacityId) -and $CapacityId -notmatch "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$") {
    $CapacityNameHint = $CapacityId
}

function Test-CommandExists {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found on PATH."
    }
}

function ConvertTo-TempJsonFile {
    param([object]$Body)
    $tempRoot = $env:TEMP
    if ([string]::IsNullOrWhiteSpace($tempRoot)) {
        $tempRoot = $env:TMPDIR
    }
    if ([string]::IsNullOrWhiteSpace($tempRoot)) {
        $tempRoot = [System.IO.Path]::GetTempPath()
    }
    if ([string]::IsNullOrWhiteSpace($tempRoot)) {
        $tempRoot = "/tmp"
    }
    $file = Join-Path $tempRoot ("fabric-demo-" + [guid]::NewGuid().ToString() + ".json")
    $Body | ConvertTo-Json -Depth 50 | Set-Content -Path $file -Encoding UTF8
    return $file
}

function Invoke-FabricRest {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("get", "post", "patch", "delete")]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Url,

        [object]$Body
    )

    $args = @(
        "rest",
        "--method", $Method,
        "--resource", "https://api.fabric.microsoft.com",
        "--url", $Url,
        "--output", "json"
    )

    $tempFile = $null
    if ($null -ne $Body) {
        $tempFile = ConvertTo-TempJsonFile -Body $Body
        $args += @("--body", "@$tempFile")
    }

    try {
        $result = az @args
        if ($LASTEXITCODE -ne 0) {
            throw "az rest failed for $Method $Url"
        }
        if ([string]::IsNullOrWhiteSpace($result)) {
            return $null
        }
        return $result | ConvertFrom-Json
    }
    finally {
        if ($tempFile -and (Test-Path $tempFile)) {
            Remove-Item $tempFile -Force
        }
    }
}

function Resolve-FabricCapacityId {
    param(
        [string]$Value,
        [string]$NameHint
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    if ($Value -match "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$") {
        return $Value
    }

    $lookupName = if ([string]::IsNullOrWhiteSpace($NameHint)) { $Value } else { $NameHint }
    Write-Host "Resolving Fabric capacity GUID for '$lookupName'..."
    $response = Invoke-FabricRest -Method get -Url "https://api.fabric.microsoft.com/v1/capacities"
    $capacities = @($response.value)
    $match = $capacities |
        Where-Object { $_.displayName -ieq $lookupName -or $_.id -ieq $lookupName } |
        Select-Object -First 1

    if (-not $match) {
        $available = ($capacities | ForEach-Object { "$($_.displayName) [$($_.id)] - $($_.state)" }) -join "; "
        throw "Could not resolve Fabric capacity '$lookupName' to a GUID. Available capacities for this user: $available"
    }

    Write-Host "Resolved Fabric capacity GUID: $($match.id) ($($match.displayName), $($match.state))"
    return $match.id
}

function Get-FabricWorkspaceByName {
    param([string]$Name)
    $response = Invoke-FabricRest -Method get -Url "https://api.fabric.microsoft.com/v1/workspaces"
    return @($response.value) | Where-Object { $_.displayName -eq $Name } | Select-Object -First 1
}

function Get-FabricItemByName {
    param(
        [string]$WorkspaceId,
        [string]$Type,
        [string]$Name
    )
    $url = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items?type=$Type"
    $response = Invoke-FabricRest -Method get -Url $url
    return @($response.value) | Where-Object { $_.displayName -eq $Name } | Select-Object -First 1
}

function New-OrGetWorkspace {
    $workspace = Get-FabricWorkspaceByName -Name $WorkspaceName
    if ($workspace) {
        Write-Host "Workspace exists: $WorkspaceName ($($workspace.id))"
        return $workspace
    }

    $body = @{
        displayName = $WorkspaceName
        description = "Demo workspace for SAP-style inventory planning in Microsoft Fabric."
    }
    if (-not [string]::IsNullOrWhiteSpace($CapacityId)) {
        $body.capacityId = $CapacityId
    }

    Write-Host "Creating workspace: $WorkspaceName"
    return Invoke-FabricRest -Method post -Url "https://api.fabric.microsoft.com/v1/workspaces" -Body $body
}

function New-OrGetLakehouse {
    param([string]$WorkspaceId)
    $item = Get-FabricItemByName -WorkspaceId $WorkspaceId -Type "Lakehouse" -Name $LakehouseName
    if ($item) {
        Write-Host "Lakehouse exists: $LakehouseName ($($item.id))"
        return $item
    }

    Write-Host "Creating lakehouse: $LakehouseName"
    return Invoke-FabricRest -Method post `
        -Url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/lakehouses" `
        -Body @{
            displayName = $LakehouseName
            description = "Lakehouse for dummy SAP-style planning actuals and curated inventory planning tables."
            creationPayload = @{
                enableSchemas = $true
            }
        }
}

function New-OrGetWarehouse {
    param([string]$WorkspaceId)
    $item = Get-FabricItemByName -WorkspaceId $WorkspaceId -Type "Warehouse" -Name $WarehouseName
    if ($item) {
        Write-Host "Warehouse exists: $WarehouseName ($($item.id))"
        return $item
    }

    Write-Host "Creating warehouse: $WarehouseName"
    return Invoke-FabricRest -Method post `
        -Url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/warehouses" `
        -Body @{
            displayName = $WarehouseName
            description = "Warehouse shell for curated SAP planning views and downstream reporting."
        }
}

function New-OrGetOntology {
    param([string]$WorkspaceId)
    $item = Get-FabricItemByName -WorkspaceId $WorkspaceId -Type "Ontology" -Name $OntologyName
    if ($item) {
        Write-Host "Ontology exists: $OntologyName ($($item.id))"
        return $item
    }

    Write-Host "Creating ontology shell: $OntologyName"
    return Invoke-FabricRest -Method post `
        -Url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/ontologies" `
        -Body @{
            displayName = $OntologyName
            description = "Ontology shell for Product, Plant, Supplier, Demand, Supply, Inventory Risk, and Planning Scenario."
        }
}

function New-OrGetNotebook {
    param([string]$WorkspaceId)
    $notebookPath = Join-Path $repoRoot "notebooks\Load-SAP-Planning-Demo.ipynb"
    if (-not (Test-Path $notebookPath)) {
        throw "Notebook file not found: $notebookPath"
    }

    $definition = @{
        format = "ipynb"
        parts = @(
            @{
                path = "notebook-content.ipynb"
                payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-Content $notebookPath -Raw)))
                payloadType = "InlineBase64"
            }
        )
    }

    $item = Get-FabricItemByName -WorkspaceId $WorkspaceId -Type "Notebook" -Name $NotebookName
    if ($item) {
        Write-Host "Notebook exists: $NotebookName ($($item.id))"
        Write-Host "Updating notebook definition so redeploys use the latest demo content."
        Invoke-FabricRest -Method post `
            -Url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/notebooks/$($item.id)/updateDefinition" `
            -Body @{ definition = $definition } | Out-Null
        return $item
    }

    Write-Host "Creating notebook: $NotebookName"
    return Invoke-FabricRest -Method post `
        -Url "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/notebooks" `
        -Body @{
            displayName = $NotebookName
            description = "Loads dummy SAP-style actuals and planning scenario tables into the demo lakehouse."
            definition = $definition
        }
}

Test-CommandExists -Name "az"

Write-Host "Signing into Azure tenant $TenantId if needed..."
$account = az account show --query tenantId -o tsv 2>$null
if ($LASTEXITCODE -ne 0 -or $account -ne $TenantId) {
    az login --tenant $TenantId --allow-no-subscriptions | Out-Null
}

$CapacityId = Resolve-FabricCapacityId -Value $CapacityId -NameHint $CapacityNameHint

$workspace = New-OrGetWorkspace
$workspaceId = $workspace.id

if (-not [string]::IsNullOrWhiteSpace($CapacityId)) {
    Write-Host "Ensuring workspace is assigned to capacity $CapacityId"
    try {
        Invoke-FabricRest -Method post `
            -Url "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/assignToCapacity" `
            -Body @{ capacityId = $CapacityId } | Out-Null
    }
    catch {
        Write-Warning "Capacity assignment failed or was already in progress: $($_.Exception.Message)"
    }
}

$lakehouse = New-OrGetLakehouse -WorkspaceId $workspaceId
$warehouse = $null
if ($CreateWarehouse) {
    $warehouse = New-OrGetWarehouse -WorkspaceId $workspaceId
}
$notebook = New-OrGetNotebook -WorkspaceId $workspaceId
$ontology = $null
if ($CreateOntology) {
    $ontology = New-OrGetOntology -WorkspaceId $workspaceId
}

$summary = [ordered]@{
    tenantId = $TenantId
    workspaceName = $WorkspaceName
    workspaceId = $workspaceId
    lakehouseName = $LakehouseName
    lakehouseId = $lakehouse.id
    warehouseName = if ($warehouse) { $WarehouseName } else { $null }
    warehouseId = if ($warehouse) { $warehouse.id } else { $null }
    notebookName = $NotebookName
    notebookId = $notebook.id
    ontologyName = if ($ontology) { $OntologyName } else { $null }
    ontologyId = if ($ontology) { $ontology.id } else { $null }
    nextSteps = @(
        "The notebook seeds dummy SAP-style data into the lakehouse.",
        "The semantic model is created over the gold planning tables.",
        "Create a Fabric Planning item and configure sheets using docs\\fabric-planning-setup.md.",
        "Optionally create a Data Agent using agents\\data-agent-instructions.md.",
        "Use docs\\demo-script.md and docs\\m365-copilot-questions.md for the sales demo."
    )
}

$summaryPath = Join-Path $outputsDir "deployment-summary.json"
$summary | ConvertTo-Json -Depth 10 | Set-Content -Path $summaryPath -Encoding UTF8

Write-Host ""
Write-Host "Deployment scaffold complete."
Write-Host "Summary: $summaryPath"

if ($CompleteSetup) {
    $completeScript = Join-Path $PSScriptRoot "Complete-DemoSetup.ps1"
    & $completeScript `
        -DeploymentSummaryPath $summaryPath `
        -RunNotebook `
        -WaitForNotebook:$WaitForNotebook `
        -CreateSqlDatabase:$CreateSqlDatabase `
        -AttemptPreviewItems:$AttemptPreviewAutomation
}
