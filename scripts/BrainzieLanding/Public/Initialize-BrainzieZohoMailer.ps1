<#
.SYNOPSIS
  One-time wiring of the Zoho Mail "Self Client" that lets the website contact
  form send email unattended. The Zoho analogue of emsurge's
  setup-graph-mailer.ps1 + setup-exchange-access-policy.ps1 in one step.

.DESCRIPTION
  IDENTITY MODEL — a dedicated service account, never a person's account:
    * hello@brainzie.co.uk is a GROUP — groups cannot sign in or own OAuth
      grants.
    * A dedicated service user (default: svc-mailer@brainzie.co.uk, display
      name "Brainzie Website Mailer") owns the OAuth grant. Disable, rotate or
      audit it in the Zoho admin console without touching anyone's personal
      account. One service identity per function (svc-<function>@) keeps
      permissions least-privilege as more automation is added.
    * The service user is made a member of each group it should send AS, with
      the group's "members can send emails as group" setting enabled. Then
      CONTACT_FROM can be the group address (hello@) and enquiries appear to
      come from the group itself.

  Single-mailbox restriction, by construction: a Self Client refresh token is
  minted BY the signed-in Zoho user, so it can only ever act as that user's
  mailbox (plus any group send-as addresses granted to it) — no tenant-wide
  surface to scope down, unlike Microsoft Graph app-only. Keep the scope to
  ZohoMail.messages.CREATE (+ accounts.READ) so the token can send mail but
  never read it.

  MANUAL STEPS FIRST (Zoho admin console — ~5 minutes):
    1. Admin console -> Users -> add the service user (svc-mailer@brainzie.co.uk,
       display name "Brainzie Website Mailer"; needs a mail license).
    2. Groups -> hello@ -> add svc-mailer@ as a member and enable
       "members can send emails as group" (or the per-member send-as option).
    3. Sign in to Zoho AS the service user and open https://api-console.zoho.com
       (if it redirects to api-console.zoho.eu, pass
       -AccountsBase https://accounts.zoho.eu and update wrangler.toml).
    4. ADD CLIENT -> "Self Client" -> CREATE. Copy the Client ID and Client Secret.
    5. "Generate Code" tab ->
         Scope:       ZohoMail.messages.CREATE,ZohoMail.accounts.READ
         Time:        10 minutes
         Description: brainzie website mailer
       -> CREATE -> copy the code (it expires quickly — run this straight away).

  The function exchanges the code for a permanent refresh token, verifies the
  token is bound to the service account, lists the From addresses the token
  may use (hello@ should appear once step 2 is done — if it doesn't, fix the
  group setting or set CONTACT_FROM to the service address), writes
  ZOHO_CLIENT_ID + ZOHO_ACCOUNT_ID into wrangler.toml, and uploads
  ZOHO_CLIENT_SECRET + ZOHO_REFRESH_TOKEN as Cloudflare Pages secrets.
  After it succeeds, redeploy:  Publish-BrainzieLanding

.PARAMETER ExpectedMailbox
  The service account the grant should be bound to. Default
  svc-mailer@brainzie.co.uk — pass your own (e.g. auto@brainzie.co.uk) if you
  named the account differently. Mismatch is a warning, not a failure.

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
        [string]$ExpectedMailbox = 'svc-mailer@brainzie.co.uk',
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

    # --- 2. Verify: the token must be bound to the SERVICE account ---
    Write-BrainzieStep 'Verifying mailbox binding'
    $accounts = Invoke-RestMethod -Uri "$MailBase/api/accounts" -Headers @{ Authorization = "Zoho-oauthtoken $($tok.access_token)" }
    $primary = $accounts.data | Select-Object -First 1
    $primaryAddress = $primary.primaryEmailAddress
    $accountId = "$($primary.accountId)"
    Write-BrainzieOk "Token is bound to: $primaryAddress (accountId $accountId)"
    if ($primaryAddress -ne $ExpectedMailbox) {
        Write-BrainzieWarn "Expected the service account $ExpectedMailbox but the token belongs to $primaryAddress."
        Write-BrainzieWarn 'If that is a PERSONAL account, stop: sign in to Zoho AS the service user, regenerate the grant code, and re-run.'
    }

    # List the From addresses this token may use. CONTACT_FROM in wrangler.toml
    # must be one of them; group addresses (hello@) appear once the group's
    # "send emails as group" setting covers the service user.
    $contactFrom = ''
    $toml = Get-Content (Join-Path $repoRoot 'wrangler.toml') -Raw
    if ($toml -match 'CONTACT_FROM\s*=\s*"([^"]+)"') { $contactFrom = $Matches[1] }
    try {
        $sendAs = @($primary.sendMailDetails | ForEach-Object { $_.fromAddress }) | Where-Object { $_ }
        if ($sendAs) {
            Write-BrainzieInfo "Available From addresses: $($sendAs -join ', ')"
            if ($contactFrom -and ($sendAs -notcontains $contactFrom)) {
                Write-BrainzieWarn "wrangler.toml CONTACT_FROM is '$contactFrom' but the token cannot send as it."
                Write-BrainzieWarn "Either enable 'send emails as group' for $primaryAddress on that group, or set CONTACT_FROM to one of the addresses above (e.g. $primaryAddress)."
            } else {
                Write-BrainzieOk "CONTACT_FROM '$contactFrom' is sendable by this token."
            }
        }
    } catch { Write-BrainzieInfo 'Could not list send-as addresses (fine — the primary address always works).' }

    # --- 3. Write the non-secret ids into wrangler.toml ---
    $tomlPath = Join-Path $repoRoot 'wrangler.toml'
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
    Write-BrainzieOk "Submissions will be emailed to hello@brainzie.co.uk, sent by the $primaryAddress service identity."
}
