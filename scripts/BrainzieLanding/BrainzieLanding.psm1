#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Write-Host "Loading Brainzie site management functions..."

# Private functions (not exported) — dot-sourced before the public ones.
Get-ChildItem "$PSScriptRoot/Private/*.ps1" | ForEach-Object {
    Write-Host "Loading private function $($_.FullName)" -ForegroundColor Yellow
    . $_.FullName
}

# Public functions (exported via FunctionsToExport in the .psd1).
Get-ChildItem "$PSScriptRoot/Public/*.ps1" | ForEach-Object {
    Write-Host "Loading public function $($_.FullName)" -ForegroundColor Green
    . $_.FullName
}

Write-Host -ForegroundColor Green "Brainzie site management functions loaded."
