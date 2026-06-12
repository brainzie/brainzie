<#
.SYNOPSIS
  One-time scaffolding of the Cloudflare resources for the Brainzie site:
  the Pages project, the LEADS KV namespace, and (optionally) the Turnstile
  secret. Idempotent — safe to re-run.

.DESCRIPTION
  Run AFTER `npx wrangler login` with the BRAINZIE Cloudflare account (the one
  that owns the brainzie.co.uk zone). The function refuses the foreign emsurge
  CLOUDFLARE_API_TOKEN that is usually set in this shell.

  First it pins the Brainzie Cloudflare account id into the COMMITTED
  deploy.config.psd1 (the ONLY place it lives — public configuration, never a
  secret store or a required env var) and commits that file, so every deploy
  fails fast into the RIGHT account.

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

    # --- Public deploy config: pin the Brainzie Cloudflare account id ---------
    # The account id is PUBLIC configuration, not a secret: the committed
    # deploy.config.psd1 is its ONLY home (never a secret store or a required env
    # var). Deploys refuse to run while it is empty, so pin + commit it first.
    $repoRoot = Get-BrainzieRepoRoot
    $cfgPath  = Join-Path $repoRoot 'deploy.config.psd1'
    $config   = Import-PowerShellDataFile -Path $cfgPath
    if (-not $config.CloudflareAccountId) {
        Write-BrainzieStep 'Pinning the Brainzie Cloudflare account id (deploy.config.psd1)'
        # Deliberately NOT the bare CLOUDFLARE_ACCOUNT_ID env var — on this machine
        # that usually belongs to the emsurge account (see Assert-BrainzieCloudflareIdentity).
        $acct = [Environment]::GetEnvironmentVariable('BRAINZIE_CLOUDFLARE_ACCOUNT_ID')
        if (-not $acct) {
            Write-BrainzieInfo 'Account ID: Cloudflare dashboard -> Workers & Pages -> right sidebar "Account ID" (the BRAINZIE account).'
            $acct = Read-Host 'Paste the Brainzie Cloudflare account id'
        }
        if (-not $acct) { throw 'No account id provided — deploys refuse to run until CloudflareAccountId is pinned in deploy.config.psd1. Re-run Initialize-BrainzieLanding.' }
        $raw     = Get-Content -LiteralPath $cfgPath -Raw
        $updated = $raw -replace "CloudflareAccountId\s*=\s*'[^']*'", "CloudflareAccountId = '$acct'"
        if ($updated -eq $raw) { throw "Could not find the CloudflareAccountId entry in $cfgPath to update — fix the file by hand." }
        Set-Content -LiteralPath $cfgPath -Value $updated -NoNewline
        # Pathspec commit: only deploy.config.psd1, never unrelated work in progress.
        git -C $repoRoot commit -m 'Deploy: pin the Brainzie Cloudflare account id in deploy.config.psd1' -- $cfgPath | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-BrainzieOk "Pinned + committed the Brainzie Cloudflare account id: $acct" }
        else { Write-BrainzieWarn 'Pinned the account id in deploy.config.psd1 but the git commit failed — commit that file manually.' }
    }
    else { Write-BrainzieOk "Brainzie Cloudflare account pinned: $($config.CloudflareAccountId)" }

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
