<#
.SYNOPSIS
    Internal. The module's console-logging helpers (colour-coded progress output),
    shared by every public function.
#>
function Write-BrainzieStep([string]$Message) { Write-Host "`n=== $Message ===" -ForegroundColor Cyan }
function Write-BrainzieInfo([string]$Message) { Write-Host "    $Message" -ForegroundColor DarkGray }
function Write-BrainzieOk([string]$Message)   { Write-Host "    $Message" -ForegroundColor Green }
function Write-BrainzieWarn([string]$Message) { Write-Host "    $Message" -ForegroundColor Yellow }
