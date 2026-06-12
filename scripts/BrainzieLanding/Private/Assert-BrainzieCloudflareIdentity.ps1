<#
.SYNOPSIS
    Internal. Guards against deploying brainzie infrastructure with a foreign
    Cloudflare token.

.DESCRIPTION
    This machine usually has CLOUDFLARE_API_TOKEN set for the EMSURGE account,
    which cannot see the brainzie.co.uk zone. Unless the caller passed an
    explicit -ApiToken (assumed to be a brainzie-account token), clear the
    environment variables for this session so wrangler falls back to the
    `npx wrangler login` browser identity.

    It then pins CLOUDFLARE_ACCOUNT_ID from the COMMITTED deploy.config.psd1 —
    the ONLY place the account id lives (public configuration, never a secret
    store or a required env var) — and refuses to run while it is unpinned.
    Initialize-BrainzieLanding pins and commits the id.
#>
function Assert-BrainzieCloudflareIdentity {
    param([string]$ApiToken = '')

    if ($ApiToken) {
        $env:CLOUDFLARE_API_TOKEN = $ApiToken
        Write-BrainzieInfo 'Using the explicitly provided Cloudflare API token.'
    }
    elseif ($env:CLOUDFLARE_API_TOKEN) {
        Write-BrainzieWarn 'CLOUDFLARE_API_TOKEN is set in this shell (usually the emsurge token).'
        Write-BrainzieWarn "Clearing it for this session so wrangler uses your 'wrangler login' identity."
        Write-BrainzieWarn "If you haven't logged in: run 'npx wrangler login' first, or pass -ApiToken."
        Remove-Item Env:CLOUDFLARE_API_TOKEN
        if (Test-Path Env:CLOUDFLARE_ACCOUNT_ID) { Remove-Item Env:CLOUDFLARE_ACCOUNT_ID }
    }

    # Pin the target account from the COMMITTED deploy.config.psd1 so a multi-account identity
    # (or a stale machine-wide env var) can never deploy this site into the wrong account.
    $config = Import-PowerShellDataFile -Path (Join-Path (Get-BrainzieRepoRoot) 'deploy.config.psd1')
    if ($config.CloudflareAccountId) {
        if ($env:CLOUDFLARE_ACCOUNT_ID -and $env:CLOUDFLARE_ACCOUNT_ID -ne $config.CloudflareAccountId) {
            throw "Cloudflare account mismatch: deploy.config.psd1 pins '$($config.CloudflareAccountId)' but the shell has CLOUDFLARE_ACCOUNT_ID='$($env:CLOUDFLARE_ACCOUNT_ID)'. Refusing to deploy into the wrong account."
        }
        $env:CLOUDFLARE_ACCOUNT_ID = $config.CloudflareAccountId
    }
    else {
        throw 'deploy.config.psd1 has no CloudflareAccountId pinned. The Brainzie account id lives ONLY in the committed deploy.config.psd1 (it is public configuration, never a secret). Run Initialize-BrainzieLanding to pin and commit it.'
    }
}
