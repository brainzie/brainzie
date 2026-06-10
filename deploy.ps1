#requires -Version 7
<#
.SYNOPSIS
  Deploy the Brainzie site to Cloudflare Pages.

.DESCRIPTION
  Publishes the static site in ./site (including the /api/contact Pages
  Function in ./functions) to Cloudflare Pages — same model as
  emsurge-landingpage. No build step for the site itself; the Blazor course
  apps are pre-built into site/courses/<slug>/app by tools/build-course.ps1.

  IMPORTANT — account: deploy into the Cloudflare account that owns the
  brainzie.co.uk zone. If this shell has CLOUDFLARE_API_TOKEN set for another
  account (e.g. emsurge), the script clears it for the session and uses your
  `wrangler login` identity instead (or pass -ApiToken with a brainzie token).

  First time? Read SETUP.md and run with -Setup to scaffold the Cloudflare
  resources (Pages project, KV namespace, secrets).

.PARAMETER Branch
  Deploy branch. "production" publishes live; anything else creates a preview.

.PARAMETER Setup
  Run the one-time resource scaffolding before deploying.

.PARAMETER BuildCourses
  Rebuild every course's Blazor app into site/courses/<slug>/app first
  (requires the .NET SDK).

.PARAMETER ApiToken
  A Cloudflare API token for the BRAINZIE account. If omitted, wrangler uses
  your `wrangler login` OAuth identity.

.EXAMPLE
  ./deploy.ps1 -Setup            # first time: project + KV + secrets
  ./deploy.ps1                   # publish to production
  ./deploy.ps1 -Branch preview   # publish a preview URL
  ./deploy.ps1 -BuildCourses     # rebuild Blazor course apps, then publish
#>
param(
  [string]$ProjectName = "brainzie",
  [string]$Branch = "production",
  [switch]$Setup,
  [switch]$BuildCourses,
  [string]$ApiToken
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# --- Sanity checks ---
if (-not (Test-Path "./site/index.html")) { throw "Can't find ./site/index.html — run this from the repo root." }
if (-not (Get-Command npx -ErrorAction SilentlyContinue)) { throw "Node.js / npx not found. Install Node 18+ (https://nodejs.org)." }

# --- Account guard: never deploy brainzie infra with a foreign token ---------
if ($ApiToken) {
  $env:CLOUDFLARE_API_TOKEN = $ApiToken
} elseif ($env:CLOUDFLARE_API_TOKEN) {
  Write-Warning "CLOUDFLARE_API_TOKEN is set in this shell (often the emsurge token)."
  Write-Warning "Clearing it for this session so wrangler uses your 'wrangler login' identity."
  Write-Warning "If you haven't logged in: run 'npx wrangler login' first, or pass -ApiToken."
  Remove-Item Env:CLOUDFLARE_API_TOKEN
  if ($env:CLOUDFLARE_ACCOUNT_ID) { Remove-Item Env:CLOUDFLARE_ACCOUNT_ID }
}

function Invoke-Wrangler {
  param([Parameter(ValueFromRemainingArguments)] [string[]]$Args)
  Write-Host "› wrangler $($Args -join ' ')" -ForegroundColor DarkGray
  & npx --yes wrangler@latest @Args
  if ($LASTEXITCODE -ne 0) { throw "wrangler exited with code $LASTEXITCODE" }
}

if ($Setup) {
  Write-Host "=== One-time setup ===" -ForegroundColor Cyan
  Write-Host "1) Creating Pages project (ignore error if it already exists)…"
  try { Invoke-Wrangler pages project create $ProjectName --production-branch production } catch { Write-Warning $_ }

  Write-Host "2) Creating KV namespace 'LEADS' (backup of every form submission)…"
  Write-Host "   Copy the returned id into wrangler.toml (kv_namespaces.id), then re-run without -Setup." -ForegroundColor Yellow
  try { Invoke-Wrangler kv namespace create LEADS } catch { Write-Warning $_ }

  Write-Host "3) Turnstile secret (paste the Turnstile SECRET key; Ctrl+C to skip for now)…"
  try { Invoke-Wrangler pages secret put TURNSTILE_SECRET --project-name $ProjectName } catch { Write-Warning $_ }

  Write-Host "Setup attempted. For email, run ./setup-zoho-mailer.ps1 (see SETUP.md), then ./deploy.ps1." -ForegroundColor Green
  return
}

if ((Get-Content wrangler.toml -Raw) -match 'REPLACE_WITH_KV_NAMESPACE_ID') {
  throw "wrangler.toml still has the KV placeholder. Run ./deploy.ps1 -Setup and paste the namespace id first."
}

if ($BuildCourses) {
  Write-Host "=== Rebuilding course apps ===" -ForegroundColor Cyan
  Get-ChildItem -Directory apps-src -Filter 'Course*' | ForEach-Object {
    $n = $_.Name -replace '^Course', ''
    pwsh tools/build-course.ps1 -Course $n
    if ($LASTEXITCODE -ne 0) { throw "build-course $n failed" }
  }
}

# --- Deploy ---
# Config mode: wrangler reads pages_build_output_dir ("site") and the root
# functions/ directory from wrangler.toml. Do NOT pass a positional directory —
# that switches to classic mode and the Functions stop compiling.
Write-Host "=== Deploying '$ProjectName' (branch: $Branch) ===" -ForegroundColor Cyan
Invoke-Wrangler pages deploy --project-name $ProjectName --branch $Branch
Write-Host "Done. Custom domains are configured in the Cloudflare dashboard (see SETUP.md)." -ForegroundColor Green
