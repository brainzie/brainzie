---
name: new-course
description: Create a new course in the Brainzie site (brainzie.co.uk repo) — its folder and summary page, its listing on the courses and home pages, and (only if it needs interactive lessons) a Blazor WebAssembly project. Use when the user wants to add/start a new course or cohort, e.g. "new course", "add the data-structures course", "start course 09". For adding lessons to an existing course, use the new-lesson skill instead.
---

# Create a new Brainzie course

Courses live at `courses/<NN>-<slug>/index.html` (the summary page). Interactive
lessons sit under `courses/<NN>-<slug>/lessons/`. If a course needs live demos, it
gets ONE Blazor WebAssembly project, `apps-src/Course<NN>/`, published to
`courses/<NN>-<slug>/app/`. Use an existing course as a model: summary pages like
`courses/07-software-advanced/index.html`, and the Blazor app `apps-src/Course08/`.

## Steps

1. **Gather inputs.** Next number `<NN>` (two digits, next after the highest existing), a kebab-case `<slug>`, the programme it belongs to (e.g. "STEMming for you" enrichment, or "Professional Software Development"), title, dates, format, status (is it currently running?), an overview paragraph, and the session/lesson outline. Decide whether it needs **interactive Blazor lessons** (most non-software courses do not).

2. **Create the summary page.** Copy an existing course's `index.html` (same programme is closest) to `courses/<NN>-<slug>/index.html`. Keep the depth-2 relative paths (`../../assets/...`, `../../brand/...`, `../../index.html`, etc. — the page is two levels deep). Update: `<title>`, meta description, crumbs, eyebrow, `<h1>`, lead, the `.factbar` (Edition/Dates/Format/Partner), the Overview, and the `.sessions` list. If it will have interactive lessons, add an "Interactive lessons" `<h2>` + `<ol class="sessions">` section (see Course 08).

3. **List it on `courses.html`.** Add a `<a class="course" href="courses/<NN>-<slug>/index.html">…</a>` card to the correct programme's `.timeline`, in chronological order. If the course is **currently running**, also update the top "Running now" card to point at it (and give the relevant card a `<span class="pill live">● Currently running</span>`).

4. **Optionally surface on the home page** (`index.html`): the "Recently delivered" timeline and, if currently running, the "Running now" card near the top. Keep the stats strip accurate.

5. **If the course needs interactive Blazor lessons, scaffold its app:**
   - `dotnet new blazorwasm -o apps-src/Course<NN> -n Course<NN>` then `dotnet sln apps-src/Brainzie.Courses.slnx add apps-src/Course<NN>/Course<NN>.csproj`.
   - Mirror `apps-src/Course08` conventions:
     - `Course<NN>.csproj`: add `<WasmBuildNative>false</WasmBuildNative>` and `<CompressionEnabled>false</CompressionEnabled>` (fast publish, no emscripten on CI, trimmed output).
     - `wwwroot/index.html`: set `<base href="/courses/<NN>-<slug>/app/" />`, drop Bootstrap, point to a minimal `css/app.css` (chromeless — the pages are embedded in iframes).
     - `App.razor`: NO `<Router>`. Select the page from the URL **fragment** (`#/<NN>/lesson-…/demo`) — GitHub Pages serves a single site-wide 404, so a sub-folder SPA cannot deep-link by path. Copy Course08's `App.razor` switch and `MainLayout.razor` (chromeless), `_Imports.razor`, and a `Pages/Catalog.razor`.
     - Delete the template's sample pages (Counter/Weather, etc.).
   - Register the course in `tools/build-course.ps1`: add `'<NN>' = '<NN>-<slug>'` to the `$slugs` map.
   - Build: `pwsh tools/build-course.ps1 -Course <NN>`. The `build-courses` GitHub Action will also pick it up automatically on push.

6. **Verify locally.** Serve the repo root (`python -m http.server 8123 --directory F:\src\brainzie`) and check: the new course page renders with styling, it's linked from `courses.html` (and home), no broken links, and — if applicable — the Blazor app boots. Use the preview tools if available.

7. **Commit & deploy.** Stage `courses/<NN>-<slug>/**`, the edited `courses.html`/`index.html`, and any `apps-src/**`; commit and push to `main`. Pages redeploys from `main`; if `apps-src/**` changed, the Action rebuilds and commits the app output (`git pull` after to sync).

## Then add lessons
Use the **new-lesson** skill to add each lesson to the new course.

## Guardrails
- Match the brainzie design system; copy an existing course page rather than building markup from scratch.
- Only create a Blazor project if the course genuinely needs interactive demos — otherwise keep it to static HTML pages.
- Deployment model: legacy GitHub Pages from `main`, custom domain brainzie.co.uk; `.nojekyll` serves `_framework`; `.gitattributes` keeps the SRI-hashed WASM bytes byte-exact. Don't change Pages settings.
