$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

Write-Host "Validating JSON files..."
Get-ChildItem -Path $repoRoot -Recurse -Include *.json,*.ipynb | ForEach-Object {
    Get-Content $_.FullName -Raw | ConvertFrom-Json | Out-Null
    Write-Host "OK $($_.FullName.Substring($repoRoot.Length + 1))"
}

Write-Host "Validating CSV files..."
Get-ChildItem -Path (Join-Path $repoRoot "data") -Recurse -Filter *.csv | ForEach-Object {
    $rows = Import-Csv $_.FullName
    if (@($rows).Count -eq 0) {
        throw "CSV has no data rows: $($_.FullName)"
    }
    Write-Host ("OK {0}: {1} rows" -f $_.FullName.Substring($repoRoot.Length + 1), @($rows).Count)
}

Write-Host "Validating PowerShell scripts..."
Get-ChildItem -Path (Join-Path $repoRoot "scripts") -Filter *.ps1 | ForEach-Object {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        throw ($errors | Out-String)
    }
    Write-Host "OK $($_.FullName.Substring($repoRoot.Length + 1))"
}

Write-Host "Repository validation passed."

