<#
.SYNOPSIS
    Internal. Resolves the brainzie repo root from the module location
    (scripts/BrainzieLanding -> repo root), so every function works regardless
    of the caller's current directory.
#>
function Get-BrainzieRepoRoot {
    Resolve-Path (Join-Path $PSScriptRoot '../../..')
}
