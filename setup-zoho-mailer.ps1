#requires -Version 7
<#
.SYNOPSIS
  One-time wiring of the Zoho Mail "Self Client" that lets the website contact
  form send email AS hello@brainzie.co.uk. The Zoho analogue of emsurge's
  setup-graph-mailer.ps1 + setup-exchange-access-policy.ps1 in one step.

.DESCRIPTION
  Single-mailbox restriction, by construction: a Self Client refresh token is
  minted BY the signed-in Zoho user. Generate the grant code while signed in
  as hello@brainzie.co.uk and the resulting token can only ever act as that
  mailbox — there is no tenant-wide surface to scope down (unlike Microsoft
  Graph app-only, which needs an Exchange application access policy on top).
  Keep the scope to ZohoMail.messages.CREATE (+ accounts.READ) so the token
  can send mail but never read it.

  MANUAL STEP FIRST (Zoho has no CLI for this — ~2 minutes):
    1. Sign in to Zoho as hello@brainzie.co.uk and open https://api-console.zoho.com
       (if your account lives on the EU DC it redirects to api-console.zoho.eu —
       then pass -AccountsBase https://accounts.zoho.eu and update wrangler.toml).
    2. ADD CLIENT → "Self Client" → CREATE. Copy the Client ID and Client Secret.
    3. "Generate Code" tab →
         Scope:       ZohoMail.messages.CREATE,ZohoMail.accounts.READ
         Time:        10 minutes
         Description: brainzie website mailer
       → CREATE → copy the code (it expires quickly — run this script straight away).

  Then run:
    ./setup-zoho-mailer.ps1 -ClientId 1000.XXXX -ClientSecret YYYY -GrantCode 1000.ZZZZ

  The script exchanges the code for a permanent refresh token, verifies it by
  listing the mailbox, writes ZOHO_CLIENT_ID + ZOHO_ACCOUNT_ID into
  wrangler.toml, and uploads ZOHO_CLIENT_SECRET + ZOHO_REFRESH_TOKEN as
  Cloudflare Pages secrets. After it succeeds, redeploy:  ./deploy.ps1
#>
param(
  [Parameter(Mandatory)] [string]$ClientId,
  [Parameter(Mandatory)] [string]$ClientSecret,
  [Parameter(Mandatory)] [string]$GrantCode,
  [string]$AccountsBase = "https://accounts.zoho.com",
  [string]$MailBase = "https://mail.zoho.com",
  [string]$ExpectedMailbox = "hello@brainzie.co.uk",
  [string]$PagesProject = "brainzie"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# --- Account guard (same as deploy.ps1): use the brainzie wrangler identity ---
if ($env:CLOUDFLARE_API_TOKEN) {
  Write-Warning "Clearing CLOUDFLARE_API_TOKEN for this session (it is usually the emsurge token)."
  Remove-Item Env:CLOUDFLARE_API_TOKEN
  if ($env:CLOUDFLARE_ACCOUNT_ID) { Remove-Item Env:CLOUDFLARE_ACCOUNT_ID }
}

# --- 1. Exchange the grant code for a refresh token ---
Write-Host "Exchanging the grant code for a refresh token…" -ForegroundColor Cyan
$tok = Invoke-RestMethod -Method Post -Uri "$AccountsBase/oauth/v2/token" -Body @{
  grant_type    = "authorization_code"
  code          = $GrantCode
  client_id     = $ClientId
  client_secret = $ClientSecret
}
if (-not $tok.refresh_token) {
  throw "No refresh token returned: $($tok | ConvertTo-Json -Compress). Grant codes expire in minutes — generate a fresh one. If the error mentions the data centre, regenerate on the right console (e.g. api-console.zoho.eu) and pass -AccountsBase accordingly."
}
Write-Host "Refresh token obtained." -ForegroundColor Green

# --- 2. Verify: the token must see exactly the expected mailbox ---
Write-Host "Verifying mailbox access…" -ForegroundColor Cyan
$accounts = Invoke-RestMethod -Uri "$MailBase/api/accounts" -Headers @{ Authorization = "Zoho-oauthtoken $($tok.access_token)" }
$primary = $accounts.data | Select-Object -First 1
$primaryAddress = $primary.primaryEmailAddress
$accountId = "$($primary.accountId)"
Write-Host "Token is bound to: $primaryAddress (accountId $accountId)"
if ($primaryAddress -ne $ExpectedMailbox) {
  Write-Warning "Expected $ExpectedMailbox but the token belongs to $primaryAddress."
  Write-Warning "The mailer will send as $primaryAddress. If that's wrong, sign in to Zoho AS $ExpectedMailbox, regenerate the grant code, and re-run."
}

# --- 3. Write the non-secret ids into wrangler.toml ---
$toml = Get-Content ./wrangler.toml -Raw
$toml = $toml -replace 'ZOHO_CLIENT_ID\s*=\s*"[^"]*"', "ZOHO_CLIENT_ID     = `"$ClientId`""
$toml = $toml -replace 'ZOHO_ACCOUNT_ID\s*=\s*"[^"]*"', "ZOHO_ACCOUNT_ID    = `"$accountId`""
[IO.File]::WriteAllText("$PSScriptRoot/wrangler.toml", $toml, (New-Object Text.UTF8Encoding $false))
Write-Host "wrangler.toml updated (ZOHO_CLIENT_ID, ZOHO_ACCOUNT_ID)." -ForegroundColor Green

# --- 4. Upload the secrets to Cloudflare Pages ---
Write-Host "Uploading secrets to Pages project '$PagesProject'…" -ForegroundColor Cyan
$ClientSecret      | npx --yes wrangler@latest pages secret put ZOHO_CLIENT_SECRET --project-name $PagesProject
$tok.refresh_token | npx --yes wrangler@latest pages secret put ZOHO_REFRESH_TOKEN --project-name $PagesProject

Write-Host ""
Write-Host "Done. Now redeploy:  ./deploy.ps1" -ForegroundColor Green
Write-Host "The form will email $ExpectedMailbox, sent from the mailbox itself via the Zoho Mail API." -ForegroundColor Green
