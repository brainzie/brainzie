<#
.SYNOPSIS
  One-time wiring of the Zoho Mail "Self Client" that lets the website contact
  form send email. The Zoho analogue of emsurge's setup-graph-mailer.ps1 +
  setup-exchange-access-policy.ps1 in one step.

.DESCRIPTION
  IMPORTANT — hello@brainzie.co.uk is a GROUP, not a user. Groups cannot sign
  in or own OAuth grants, so the Self Client grant code must be generated while
  signed in as the real user, directors@brainzie.co.uk. The refresh token is
  then bound to the directors@ mailbox and the form sends FROM directors@ TO
  hello@ (groups receive mail fine — they just can't authenticate).

  Single-mailbox restriction, by construction: a Self Client refresh token is
  minted BY the signed-in Zoho user, so it can only ever act as that mailbox —
  there is no tenant-wide surface to scope down (unlike Microsoft Graph
  app-only, which needs an Exchange application access policy on top). Keep the
  scope to ZohoMail.messages.CREATE (+ accounts.READ) so the token can send
  mail but never read it.

  Optional upgrade: if you enable "send emails as group" for directors@ in the
  hello@ group settings (Zoho Mail admin), the verification step below will
  list hello@ as an available From address and you can flip CONTACT_FROM in
  wrangler.toml to hello@brainzie.co.uk.

  MANUAL STEP FIRST (Zoho has no CLI for this — ~2 minutes):
    1. Sign in to Zoho as directors@brainzie.co.uk and open
       https://api-console.zoho.com (if your account lives on the EU DC it
       redirects to api-console.zoho.eu — then pass
       -AccountsBase https://accounts.zoho.eu and update wrangler.toml).
    2. ADD CLIENT -> "Self Client" -> CREATE. Copy the Client ID and Client Secret.
    3. "Generate Code" tab ->
         Scope:       ZohoMail.messages.CREATE,ZohoMail.accounts.READ
         Time:        10 minutes
         Description: brainzie website mailer
       -> CREATE -> copy the code (it expires quickly — run this straight away).

  The function exchanges the code for a permanent refresh token, verifies the
  token is bound to directors@, lists the From addresses the token may use,
  writes ZOHO_CLIENT_ID + ZOHO_ACCOUNT_ID into wrangler.toml, and uploads
  ZOHO_CLIENT_SECRET + ZOHO_REFRESH_TOKEN as Cloudflare Pages secrets.
  After it succeeds, redeploy:  Publish-BrainzieLanding

.EXAMPLE
  Import-Module ./scripts/BrainzieLanding/BrainzieLanding.psd1
  Initialize-BrainzieZohoMailer -ClientId 1000.XXXX -ClientSecret YYYY -GrantCode 1000.ZZZZ
#>
function Initialize-BrainzieZohoMailer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$ClientSecret,
        [Parameter(Mandatory)][string]$GrantCode,
        [string]$AccountsBase = 'https://accounts.zoho.com',
        [string]$MailBase = 'https://mail.zoho.com',
        [string]$ExpectedMailbox = 'directors@brainzie.co.uk',
        [string]$PagesProject = 'brainzie',
        [string]$ApiToken = ''
    )

    Assert-BrainzieCloudflareIdentity -ApiToken $ApiToken
    $repoRoot = Get-BrainzieRepoRoot

    # --- 1. Exchange the grant code for a refresh token ---
    Write-BrainzieStep 'Exchanging the grant code for a refresh token'
    $tok = Invoke-RestMethod -Method Post -Uri "$AccountsBase/oauth/v2/token" -Body @{
        grant_type    = 'authorization_code'
        code          = $GrantCode
        client_id     = $ClientId
        client_secret = $ClientSecret
    }
    if (-not ($tok.PSObject.Properties.Name -contains 'refresh_token') -or -not $tok.refresh_token) {
        throw "No refresh token returned: $($tok | ConvertTo-Json -Compress). Grant codes expire in minutes — generate a fresh one. If the error mentions the data centre, regenerate on the right console (e.g. api-console.zoho.eu) and pass -AccountsBase accordingly."
    }
    Write-BrainzieOk 'Refresh token obtained.'

    # --- 2. Verify: the token must be bound to the expected USER mailbox ---
    Write-BrainzieStep 'Verifying mailbox binding'
    $accounts = Invoke-RestMethod -Uri "$MailBase/api/accounts" -Headers @{ Authorization = "Zoho-oauthtoken $($tok.access_token)" }
    $primary = $accounts.data | Select-Object -First 1
    $primaryAddress = $primary.primaryEmailAddress
    $accountId = "$($primary.accountId)"
    Write-BrainzieOk "Token is bound to: $primaryAddress (accountId $accountId)"
    if ($primaryAddress -ne $ExpectedMailbox) {
        Write-BrainzieWarn "Expected $ExpectedMailbox but the token belongs to $primaryAddress."
        Write-BrainzieWarn "The mailer will send as $primaryAddress. If that's wrong, sign in to Zoho AS $ExpectedMailbox, regenerate the grant code, and re-run."
    }

    # List the From addresses this token may use (CONTACT_FROM must be one of
    # them; hello@ appears here only if "send as group" is enabled for the user).
    try {
        $sendAs = @($primary.sendMailDetails | ForEach-Object { $_.fromAddress }) | Where-Object { $_ }
        if ($sendAs) {
            Write-BrainzieInfo "Available From addresses: $($sendAs -join ', ')"
            Write-BrainzieInfo 'CONTACT_FROM in wrangler.toml must be one of these.'
        }
    } catch { Write-BrainzieInfo 'Could not list send-as addresses (fine — the primary address always works).' }

    # --- 3. Write the non-secret ids into wrangler.toml ---
    $tomlPath = Join-Path $repoRoot 'wrangler.toml'
    $toml = Get-Content $tomlPath -Raw
    $toml = $toml -replace 'ZOHO_CLIENT_ID\s*=\s*"[^"]*"', "ZOHO_CLIENT_ID     = `"$ClientId`""
    $toml = $toml -replace 'ZOHO_ACCOUNT_ID\s*=\s*"[^"]*"', "ZOHO_ACCOUNT_ID    = `"$accountId`""
    [IO.File]::WriteAllText($tomlPath, $toml, (New-Object Text.UTF8Encoding $false))
    Write-BrainzieOk 'wrangler.toml updated (ZOHO_CLIENT_ID, ZOHO_ACCOUNT_ID).'

    # --- 4. Upload the secrets to Cloudflare Pages ---
    Write-BrainzieStep "Uploading secrets to Pages project '$PagesProject'"
    Push-Location $repoRoot
    try {
        $ClientSecret      | npx --yes wrangler@latest pages secret put ZOHO_CLIENT_SECRET --project-name $PagesProject
        $tok.refresh_token | npx --yes wrangler@latest pages secret put ZOHO_REFRESH_TOKEN --project-name $PagesProject
    }
    finally { Pop-Location }

    Write-BrainzieStep 'Done'
    Write-BrainzieOk 'Now redeploy:  Publish-BrainzieLanding'
    Write-BrainzieOk "The form will email hello@brainzie.co.uk (the group), sent from $primaryAddress via the Zoho Mail API."
}
