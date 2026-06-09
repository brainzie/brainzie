---
name: new-lesson
description: Create or update an interactive lesson inside a Brainzie course (the brainzie.co.uk repo). Use when the user wants to add, draft, build, or edit a lesson — e.g. "new lesson for course 08", "add lesson 12", "update the loops lesson". Produces a self-paced HTML stepper page following the standard Brainzie lesson structure, optionally with live Blazor WebAssembly demos/exercises, and wires it into the course and deployment.
---

# Create / update a Brainzie lesson

A lesson is a self-contained HTML page that presents one step at a time (a stepper
with Previous/Next), styled by `assets/lesson.css`. Interactivity that needs real
code runs as a Blazor WebAssembly demo/exercise embedded via `<iframe>`. Everything
else is plain HTML — **never show JavaScript to students** (the courses teach C#/Blazor).

See the worked example: `courses/08-software-mixed/lessons/lesson-11-button/index.html`
and the Blazor app under `apps-src/Course08/`.

## Standard lesson structure (default for every lesson except a course's first)

Each item below is one step in the stepper. Confirm/collect the content for each:

1. **Title** — catchy, tied to the goal (the page `<h1>`).
2. **Goal** — terse statement of what students will have achieved (the page lead + step 1, with 2–4 concrete success criteria).
3. **Homework review** — show-of-hands checklist for last lesson's homework, plus space for questions.
4. **Recap** — fast-fire recall questions on earlier topics.
5. **Fast-fire group exercises** — "Spot the error(s)" (show code, students shout the bug) and/or "What does it do?" (students predict behaviour). Always give the answer.
6. **Main content** — the explanation, supported by code blocks. Split into multiple steps if long.
7. **Exercises** — a choose-your-level list ordered by increasing difficulty (easy → medium → hard) so every student finds something both achievable and challenging.
8. **Homework** — usually a subset of the exercises above, sometimes plus 1–2 extras.

A course's **first** lesson is typically an intro and may deviate; ask the user if unsure.

## Steps

1. **Gather inputs.** Course (slug, e.g. `08-software-mixed`), lesson number, topic, title, goal, and the content for each section above. Ask for whatever is missing rather than inventing pedagogy.

2. **Pick the lesson number and folder.** Lessons are numbered by their position in the course. Folder: `courses/<course-slug>/lessons/lesson-<NN>-<topic>/index.html` (NN zero-padded, topic kebab-case). If renumbering an existing lesson, rename the folder, its routes/fragments, and any component names together (see "Renumbering" below).

3. **Create the page from the template.** Copy `tools/templates/lesson.html` to the new folder as `index.html`. Replace every `{{TOKEN}}` (PAGE_TITLE, META_DESC, EYEBROW, COURSE_LABEL, LESSON_NUMBER, LESSON_TITLE, LESSON_GOAL) and fill each step's `<!-- FILL -->` content. Duplicate the Main content `<section class="step">` for as many content steps as needed — the stepper counts steps automatically. Escape `<` `>` `&` as `&lt; &gt; &amp;` inside `<pre><code>`.
   - The stepper, full-screen toggle (glowing ⛶ button), top-and-bottom Previous/Next, browser-history step navigation, and Copy buttons are all provided by `assets/lesson.js` (linked at the foot of the template). Don't re-implement them; just keep the markup contract (`.lesson-progress` with `.fs-title`+`.fs-btn`, `#steps` of `.step`, a bottom `.lesson-nav` with `.prev`/`.next`, and `class="lesson-shell"` on the wrapping `<section>`).
   - **Be explicit about every action.** Students do not infer steps. Whenever code is introduced, state plainly which file to **create** or **open**, where it lives, and what to type — e.g. "Add a new Razor Component named `MyButton.razor`" or "create the scoped stylesheet `MyButton.razor.css` next to it". Label code-block headers with intent ("`MyButton.razor` — create this file"). Never leave file creation implied.

4. **Add a live demo/exercise ONLY if the lesson needs real interactivity** (otherwise keep it pure HTML — see the "Blazor only where required" rule). To add one:
   - In `apps-src/Course<NN>/`, add a component under `Demos/Lesson<NN><Topic>/` or `Exercises/Lesson<NN><Topic>/`, named uniquely (e.g. `Lesson12LoopsDemo.razor`).
   - Register its namespace in `apps-src/Course<NN>/_Imports.razor`, add a `case "<NN>/lesson-<NN>-<topic>/demo":` (and/or `/exercise`) to `apps-src/Course<NN>/App.razor`, and a link in `Pages/Catalog.razor`.
   - Embed in the lesson with the `.tryit` block (already stubbed, commented, in the template):
     `<iframe src="../../app/#/<NN>/lesson-<NN>-<topic>/demo" ...>`. The `../../app/` path and `#fragment` routing are required — see the lessons-platform conventions in the project memory and `apps-src/Course<NN>/App.razor` for why.
   - Rebuild: `pwsh tools/build-course.ps1 -Course <NN>` (publishes to `courses/<slug>/app`).

5. **Link the lesson from the course summary.** In `courses/<course-slug>/index.html`, add a row to the "Interactive lessons" `<ol class="sessions">` (create that section if missing — see Course 08 for the pattern):
   `<li><span class="s-n"><NN></span><div><h4><a href="lessons/lesson-<NN>-<topic>/index.html">Title</a></h4><p>One-line summary.</p></div></li>`

6. **Verify locally.** Serve the repo root over HTTP (e.g. `python -m http.server 8123 --directory F:\src\brainzie`) and open the lesson. Check: stepper Next/Previous works, code Copy buttons work, any iframes boot the Blazor app, and there are no broken links. Use the preview tools if available.

7. **Commit & deploy.** Stage the lesson, the course index, and any `apps-src/**` + `courses/<slug>/app/**` changes; commit and push to `main`. GitHub Pages (legacy, from `main`) redeploys automatically. If you changed `apps-src/**`, the `build-courses` Action rebuilds and commits the app output too — `git pull` afterwards to sync.

## Renumbering an existing lesson

Move the lesson folder, and update **together**: the fragment routes in the lesson's `<iframe src>`, the `case` labels in `App.razor`, the component folder/file/usings names, `Catalog.razor` links, the `<span class="s-n">` and `href` in the course index, and the page title/crumb/`{{LESSON_NUMBER}}`. Rebuild the Course app and verify.

## Guardrails
- Pure HTML for narrative; Blazor only for genuinely interactive demos.
- No JavaScript shown as lesson content (the stepper's own `assets/lesson.js` is page mechanics, not taught).
- Spell out file creation/opening explicitly in every step that introduces code — never leave it implied.
- Match the brainzie design system (use existing classes from `assets/brainzie.css` and `assets/lesson.css`; don't invent new colours).
- To add a brand-new course instead, use the `new-course` skill first.
