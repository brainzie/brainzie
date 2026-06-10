<#
.SYNOPSIS
  One-time scaffolding of the Cloudflare resources for the Brainzie site:
  the Pages project, the LEADS KV namespace, and (optionally) the Turnstile
  secret. Idempotent — safe to re-run.

.DESCRIPTION
  Run AFTER `npx wrangler login` with the BRAINZIE Cloudflare account (the one
  that owns the brainzie.co.uk zone). The function refuses the foreign emsurge
  CLOUDFLARE_API_TOKEN that is usually set in this shell.

  After it succeeds:
    1. Paste the printed KV namespace id into wrangler.toml -> [[kv_namespaces]] id.
    2. (Email) Initialize-BrainzieZohoMailer …
    3. Publish-BrainzieLanding

.PARAMETER ProjectName
  Cloudflare Pages project name. Default: brainzie.

.PARAMETER SkipTurnstileSecret
  Don't prompt for the Turnstile secret (you can set it later by re-running,
  or directly: npx wrangler pages secret put TURNSTILE_SECRET --project-name brainzie).

.EXAMPLE
  Import-Module ./scripts/BrainzieLanding/BrainzieLanding.psd1
  Initialize-BrainzieLanding
#>
function Initialize-BrainzieLanding {
    [CmdletBinding()]
    param(
        [string]$ProjectName = 'brainzie',
        [switch]$SkipTurnstileSecret,
        [string]$ApiToken = ''
    )

    Assert-BrainzieCloudflareIdentity -ApiToken $ApiToken

    Write-BrainzieStep "Creating Pages project '$ProjectName' (ignore error if it already exists)"
    try { Invoke-BrainzieWrangler pages project create $ProjectName --production-branch production }
    catch { Write-BrainzieWarn "$_" }

    Write-BrainzieStep "Creating KV namespace 'LEADS' (backup of every form submission)"
    Write-BrainzieWarn 'Copy the returned id into wrangler.toml ([[kv_namespaces]] id), then run Publish-BrainzieLanding.'
    try { Invoke-BrainzieWrangler kv namespace create LEADS }
    catch { Write-BrainzieWarn "$_" }

    if (-not $SkipTurnstileSecret) {
        Write-BrainzieStep 'Turnstile secret (paste the Turnstile SECRET key; Ctrl+C to skip for now)'
        try { Invoke-BrainzieWrangler pages secret put TURNSTILE_SECRET --project-name $ProjectName }
        catch { Write-BrainzieWarn "$_" }
    }

    Write-BrainzieStep 'Done'
    Write-BrainzieOk 'Next: finish wrangler.toml (KV id), then Initialize-BrainzieZohoMailer (email) and Publish-BrainzieLanding.'
}
