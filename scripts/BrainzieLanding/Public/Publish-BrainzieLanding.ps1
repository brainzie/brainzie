<#
.SYNOPSIS
  Deploys the Brainzie site (static site in ./site + the /api/contact Pages
  Function in ./functions) to Cloudflare Pages.

.DESCRIPTION
  Same model as emsurge-landingpage: no build step for the site itself; the
  Blazor course apps are pre-built into site/courses/<slug>/app (use
  -BuildCourses or Build-BrainzieCourseApp). Pushing to GitHub does NOT
  publish — this function does.

  Deploys in wrangler "config mode": wrangler.toml at the repo root supplies
  pages_build_output_dir ("site") and the root functions/ directory. Never
  pass a positional directory — that silently drops the Functions.

  Account guard: refuses the foreign emsurge CLOUDFLARE_API_TOKEN and uses
  your `npx wrangler login` identity (or an explicit -ApiToken for the
  brainzie account).

.PARAMETER Branch
  Deploy branch. 'production' publishes live; anything else creates a preview URL.

.PARAMETER BuildCourses
  Rebuild every registered course's Blazor app into site/courses/<slug>/app
  first (requires the .NET SDK).

.EXAMPLE
  Import-Module ./scripts/BrainzieLanding/BrainzieLanding.psd1
  Publish-BrainzieLanding
.EXAMPLE
  Publish-BrainzieLanding -Branch preview
.EXAMPLE
  Publish-BrainzieLanding -BuildCourses
#>
function Publish-BrainzieLanding {
    [CmdletBinding()]
    param(
        [string]$ProjectName = 'brainzie',
        [string]$Branch = 'production',
        [switch]$BuildCourses,
        [string]$ApiToken = ''
    )

    $repoRoot = Get-BrainzieRepoRoot

    Write-BrainzieStep 'Preflight'
    if (-not (Test-Path (Join-Path $repoRoot 'site/index.html'))) { throw "Can't find site/index.html under $repoRoot." }
    if ((Get-Content (Join-Path $repoRoot 'wrangler.toml') -Raw) -match 'REPLACE_WITH_KV_NAMESPACE_ID') {
        throw 'wrangler.toml still has the KV placeholder. Run Initialize-BrainzieLanding and paste the namespace id first.'
    }
    Assert-BrainzieCloudflareIdentity -ApiToken $ApiToken
    Write-BrainzieOk 'Preflight passed.'

    if ($BuildCourses) {
        foreach ($course in (Get-BrainzieCourseSlugs).Keys | Sort-Object) {
            Build-BrainzieCourseApp -Course $course
        }
    }

    Write-BrainzieStep "Deploying '$ProjectName' (branch: $Branch)"
    Invoke-BrainzieWrangler pages deploy --project-name $ProjectName --branch $Branch

    Write-BrainzieStep 'Done'
    Write-BrainzieOk "Origin: https://$ProjectName.pages.dev"
    Write-BrainzieInfo 'Custom domains are configured in the Cloudflare dashboard (see SETUP.md).'
    Write-BrainzieInfo 'Read captured leads: npx wrangler kv key list --binding LEADS --remote'
}
