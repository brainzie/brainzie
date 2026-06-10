<#
.SYNOPSIS
    Internal. Runs wrangler (via npx) from the repo root and throws on failure.

.DESCRIPTION
    The repo root matters: wrangler.toml lives there and Pages "config mode"
    reads pages_build_output_dir ("site") plus the root functions/ directory
    from it. Never pass a positional directory to `pages deploy` — that
    switches wrangler to classic mode and the Functions stop compiling.
#>
function Invoke-BrainzieWrangler {
    param([Parameter(ValueFromRemainingArguments)] [string[]]$WranglerArgs)

    if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
        throw 'Node.js / npx not found. Install Node 18+ (https://nodejs.org).'
    }
    Push-Location (Get-BrainzieRepoRoot)
    try {
        Write-Host "› wrangler $($WranglerArgs -join ' ')" -ForegroundColor DarkGray
        & npx --yes wrangler@latest @WranglerArgs
        if ($LASTEXITCODE -ne 0) { throw "wrangler exited with code $LASTEXITCODE" }
    }
    finally { Pop-Location }
}
