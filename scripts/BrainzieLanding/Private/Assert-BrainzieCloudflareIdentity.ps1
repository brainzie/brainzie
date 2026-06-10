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
#>
function Assert-BrainzieCloudflareIdentity {
    param([string]$ApiToken = '')

    if ($ApiToken) {
        $env:CLOUDFLARE_API_TOKEN = $ApiToken
        Write-BrainzieInfo 'Using the explicitly provided Cloudflare API token.'
        return
    }
    if ($env:CLOUDFLARE_API_TOKEN) {
        Write-BrainzieWarn 'CLOUDFLARE_API_TOKEN is set in this shell (usually the emsurge token).'
        Write-BrainzieWarn "Clearing it for this session so wrangler uses your 'wrangler login' identity."
        Write-BrainzieWarn "If you haven't logged in: run 'npx wrangler login' first, or pass -ApiToken."
        Remove-Item Env:CLOUDFLARE_API_TOKEN
        if (Test-Path Env:CLOUDFLARE_ACCOUNT_ID) { Remove-Item Env:CLOUDFLARE_ACCOUNT_ID }
    }
}
