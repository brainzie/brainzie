<#
.SYNOPSIS
    Builds (publishes) the Blazor WebAssembly app for ONE course and copies the
    static output into that course's `app/` folder, ready to commit and deploy.

.DESCRIPTION
    The deployment unit is a single course. Editing or rebuilding one course
    never touches another course's output.

    Each course that needs interactivity has:
      apps-src/Course<NN>/Course<NN>.csproj   ← Blazor source
      site/courses/<slug>/app/                 ← published static output (committed)

    Blazor WASM publishes to plain static files, so the live site (Cloudflare
    Pages) needs no .NET at all.

.EXAMPLE
    pwsh tools/build-course.ps1 -Course 08
#>
param(
    [Parameter(Mandatory = $true)]
    [string] $Course
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

# --- Course registry: number -> folder slug ------------------------------
$slugs = @{
    '08' = '08-software-mixed'
}

if (-not $slugs.ContainsKey($Course)) {
    throw "Unknown course '$Course'. Known courses: $($slugs.Keys -join ', ')"
}

$slug    = $slugs[$Course]
$project = Join-Path $repoRoot "apps-src/Course$Course/Course$Course.csproj"
$appDir  = Join-Path $repoRoot "site/courses/$slug/app"
$tempDir = Join-Path $repoRoot "apps-src/_publish/Course$Course"

if (-not (Test-Path $project)) { throw "Project not found: $project" }

Write-Host "Publishing Course $Course ($slug)..." -ForegroundColor Cyan

# Clean previous temp output
if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }

dotnet publish $project -c Release -o $tempDir
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed." }

# Replace the committed app folder with the fresh static output (wwwroot).
$publishedWwwroot = Join-Path $tempDir 'wwwroot'
if (-not (Test-Path $publishedWwwroot)) { throw "Expected wwwroot not found at $publishedWwwroot" }

if (Test-Path $appDir) { Remove-Item -Recurse -Force $appDir }
New-Item -ItemType Directory -Force -Path $appDir | Out-Null
Copy-Item -Recurse -Force (Join-Path $publishedWwwroot '*') $appDir

# Trim: drop pre-compressed copies. GitHub Pages serves plain files with its
# own gzip and never uses these, so they are pure committed-repo bloat.
Get-ChildItem -Path $appDir -Recurse -Include *.br, *.gz -File | Remove-Item -Force

# Tidy the temp publish output.
Remove-Item -Recurse -Force $tempDir

Write-Host "Done. Output: site/courses/$slug/app" -ForegroundColor Green
