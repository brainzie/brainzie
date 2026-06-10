#requires -Version 7
<#
.SYNOPSIS
  Deploy the brainzie.co.uk contact-form Worker to Cloudflare.

.DESCRIPTION
  The brainzie site itself stays on GitHub Pages; this deploys only the
  api.brainzie.co.uk Worker that receives contact-form submissions.

  IMPORTANT — account: the Worker must deploy into the Cloudflare account that
  owns the brainzie.co.uk zone. If your shell has CLOUDFLARE_API_TOKEN set for
  another account (e.g. emsurge), this script refuses to use it unless you pass
  a brainzie token explicitly, and otherwise falls back to your `wrangler login`
  browser identity.

  First time? Read SETUP.md and run with -Setup to scaffold the KV namespace
  and secrets.

.PARAMETER Setup
  Run the one-time resource scaffolding (KV namespace + secret prompts) first.

.PARAMETER ApiToken
  A Cloudflare API token for the BRAINZIE account (Workers Scripts:Edit,
  Workers KV Storage:Edit, Zone:Read + Workers Routes:Edit on brainzie.co.uk).
  If omitted, wrangler uses your `wrangler login` OAuth identity.

.EXAMPLE
  ./deploy.ps1 -Setup       # first time: create KV + secrets, then deploy
  ./deploy.ps1              # deploy
#>
param(
  [switch]$Setup,
  [string]$ApiToken
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
  throw "Node.js / npx not found. Install Node 18+ (https://nodejs.org)."
}

# --- Account guard: never deploy brainzie infra with a foreign token ---------
if ($ApiToken) {
  $env:CLOUDFLARE_API_TOKEN = $ApiToken
} elseif ($env:CLOUDFLARE_API_TOKEN) {
  Write-Warning "CLOUDFLARE_API_TOKEN is set in this shell (often the emsurge token)."
  Write-Warning "Clearing it for this session so wrangler uses your 'wrangler login' identity."
  Write-Warning "If you haven't logged in: run 'npx wrangler login' first, or pass -ApiToken."
  Remove-Item Env:CLOUDFLARE_API_TOKEN
}

function Invoke-Wrangler {
  param([Parameter(ValueFromRemainingArguments)] [string[]]$Args)
  Write-Host "› wrangler $($Args -join ' ')" -ForegroundColor DarkGray
  & npx --yes wrangler@latest @Args
  if ($LASTEXITCODE -ne 0) { throw "wrangler exited with code $LASTEXITCODE" }
}

if ($Setup) {
  Write-Host "=== One-time setup ===" -ForegroundColor Cyan

  Write-Host "1) Creating KV namespace 'LEADS' (backup of every submission)…"
  Write-Host "   Copy the returned id into wrangler.toml (kv_namespaces.id) before deploying." -ForegroundColor Yellow
  try { Invoke-Wrangler kv namespace create LEADS } catch { Write-Warning $_ }

  Write-Host "2) Turnstile secret (paste the Turnstile SECRET key; Ctrl+C to skip for now)…"
  try { Invoke-Wrangler secret put TURNSTILE_SECRET } catch { Write-Warning $_ }

  Write-Host "3) SendGrid API key (paste it; Ctrl+C to skip — submissions still land in KV)…"
  try { Invoke-Wrangler secret put SENDGRID_API_KEY } catch { Write-Warning $_ }

  Write-Host "Setup attempted. Finish wrangler.toml (KV id) and SETUP.md manual steps, then run ./deploy.ps1." -ForegroundColor Green
  return
}

if ((Get-Content wrangler.toml -Raw) -match 'REPLACE_WITH_KV_NAMESPACE_ID') {
  throw "wrangler.toml still has the KV placeholder. Run ./deploy.ps1 -Setup and paste the namespace id first."
}

Write-Host "=== Deploying brainzie-contact Worker ===" -ForegroundColor Cyan
Invoke-Wrangler deploy
Write-Host "Done. The form endpoint is live at https://api.brainzie.co.uk/api/contact" -ForegroundColor Green
Write-Host "Read captured leads any time: npx wrangler kv key list --binding LEADS --remote" -ForegroundColor DarkGray
