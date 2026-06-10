<#
.SYNOPSIS
  Builds (publishes) the Blazor WebAssembly app for ONE course and copies the
  static output into that course's site/courses/<slug>/app folder, ready to
  commit and publish.

.DESCRIPTION
  The build unit is a single course — rebuilding one course never touches
  another course's output. Each course that needs interactivity has:
    apps-src/Course<NN>/Course<NN>.csproj   <- Blazor source
    site/courses/<slug>/app/                <- published static output (committed)

  Blazor WASM publishes to plain static files, so the live site (Cloudflare
  Pages) needs no .NET at all. The output is trimmed: .br/.gz pre-compressed
  copies are dropped (the host serves plain files with its own compression).

.PARAMETER Course
  The two-digit course number, e.g. '08'. Must exist in the course registry
  (Private/Get-BrainzieCourseSlugs.ps1).

.EXAMPLE
  Import-Module ./scripts/BrainzieLanding/BrainzieLanding.psd1
  Build-BrainzieCourseApp -Course 08
#>
function Build-BrainzieCourseApp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Course
    )

    $slugs = Get-BrainzieCourseSlugs
    if (-not $slugs.ContainsKey($Course)) {
        throw "Unknown course '$Course'. Known courses: $($slugs.Keys -join ', '). Register new ones in scripts/BrainzieLanding/Private/Get-BrainzieCourseSlugs.ps1."
    }

    $repoRoot = Get-BrainzieRepoRoot
    $slug     = $slugs[$Course]
    $project  = Join-Path $repoRoot "apps-src/Course$Course/Course$Course.csproj"
    $appDir   = Join-Path $repoRoot "site/courses/$slug/app"
    $tempDir  = Join-Path $repoRoot "apps-src/_publish/Course$Course"

    if (-not (Test-Path $project)) { throw "Project not found: $project" }
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw 'dotnet SDK not found on PATH.' }

    Write-BrainzieStep "Publishing Course $Course ($slug)"

    if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }

    dotnet publish $project -c Release -o $tempDir
    if ($LASTEXITCODE -ne 0) { throw 'dotnet publish failed.' }

    # Replace the committed app folder with the fresh static output (wwwroot).
    $publishedWwwroot = Join-Path $tempDir 'wwwroot'
    if (-not (Test-Path $publishedWwwroot)) { throw "Expected wwwroot not found at $publishedWwwroot" }

    if (Test-Path $appDir) { Remove-Item -Recurse -Force $appDir }
    New-Item -ItemType Directory -Force -Path $appDir | Out-Null
    Copy-Item -Recurse -Force (Join-Path $publishedWwwroot '*') $appDir

    # Trim: drop pre-compressed copies — pure committed-repo bloat.
    Get-ChildItem -Path $appDir -Recurse -Include *.br, *.gz -File | Remove-Item -Force

    Remove-Item -Recurse -Force $tempDir

    Write-BrainzieOk "Output: site/courses/$slug/app"
}
