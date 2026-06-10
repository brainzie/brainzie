# Brainzie site — setup & publishing (Cloudflare Pages)

The site is a **pure static site** in [`site/`](site/) — hand-written HTML, the
shared CSS/JS in `site/assets/`, the courses (including the committed Blazor
WASM apps), and a single Cloudflare Pages Function for the contact form. Same
model as `emsurge-landingpage`.

```
functions/   api/contact.js      ← backend for the contact form (root, per wrangler.toml config mode)
site/                            ← published output (pages_build_output_dir)
  index.html  courses.html  software.html  about.html  contact.html
  brainzie-money.html  product-swim.html  brand-guidelines.html  404.html
  assets/    brainzie.css, lesson.css, lesson.js, form-submit.js, …
  brand/     logos + favicons
  courses/   <slug>/index.html, lessons/…, app/ (committed Blazor WASM output)
apps-src/    Blazor source, one project per course (NOT published)
tools/       build-course.ps1, templates/        (NOT published)
wrangler.toml  deploy.ps1  setup-zoho-mailer.ps1  SETUP.md   (repo root — not published)
```

> **Functions location matters.** Because `wrangler.toml` sets
> `pages_build_output_dir`, the `functions/` directory lives at the **project
> root** (sibling of `wrangler.toml`), and deploys run **without** a positional
> directory (`wrangler pages deploy`, not `wrangler pages deploy site`).

GitHub remains the source of truth (push as usual), but **pushing does not
publish** — publishing is `./deploy.ps1`. The `build-courses` GitHub Action
still rebuilds the Blazor apps into `site/courses/<slug>/app` when
`apps-src/**` changes; run `./deploy.ps1` (or `-BuildCourses` locally) to ship.

> ⚠️ **Cloudflare account.** Everything here deploys into the Cloudflare
> account that owns the brainzie.co.uk zone — NOT the emsurge account whose
> `CLOUDFLARE_API_TOKEN` may be set in your shell. `deploy.ps1` and
> `setup-zoho-mailer.ps1` clear that variable automatically and use your
> `npx wrangler login` identity.

---

## One-time setup

### 1. Log in and scaffold
```powershell
npx wrangler login          # browser sign-in to the BRAINZIE Cloudflare account
./deploy.ps1 -Setup         # Pages project + LEADS KV namespace + Turnstile secret prompt
```
Copy the returned KV namespace **id** into `wrangler.toml` → `[[kv_namespaces]] id = "…"`.

### 2. First deploy (to the *.pages.dev URL)
```powershell
./deploy.ps1
```
Verify everything at `https://brainzie.pages.dev` — pages, lessons, Blazor
demos, and the contact form (submissions land in the LEADS KV even before
email is configured).

### 3. Custom domain cut-over (from GitHub Pages)
Cloudflare dashboard → **Workers & Pages** → `brainzie` → **Custom domains** →
add `brainzie.co.uk` (and `www.brainzie.co.uk`). Because the zone is already in
this account, Cloudflare updates the DNS records for you (they currently point
at GitHub Pages). Then:
1. **Push** the migrated repo to GitHub (`git push origin main`) — safe now;
   GitHub Pages no longer serves the domain.
2. Disable GitHub Pages on the repo (Settings → Pages), or
   `gh api -X DELETE repos/brainzie/brainzie/pages`.

### 4. Turnstile (free anti-spam) — recommended
1. Dashboard → **Turnstile** → **Add widget** → hostnames `brainzie.co.uk` (+ `localhost`).
2. Paste the **Site key** into `site/contact.html` → `data-turnstile-sitekey="…"`.
3. Secret key: `npx wrangler pages secret put TURNSTILE_SECRET --project-name brainzie`
   (or via `./deploy.ps1 -Setup`). Redeploy.

### 5. Email — Zoho Mail API (no SendGrid, no DNS changes)
The form sends **from the hello@brainzie.co.uk mailbox itself** via the Zoho
Mail API, so SPF/DKIM/DMARC are inherently right — the same property emsurge
gets from Microsoft Graph `sendMail`.

**Single-mailbox restriction, by construction:** a Zoho **Self Client** refresh
token is minted *by* the signed-in user. Generate it while signed in as
`hello@brainzie.co.uk`, scoped to `ZohoMail.messages.CREATE` (send-only), and
the token can only ever act as that one mailbox. (Microsoft app-only tokens are
tenant-wide until an Exchange application access policy narrows them — Zoho
needs no equivalent policy.)

1. Sign in to Zoho **as hello@brainzie.co.uk** → https://api-console.zoho.com →
   **ADD CLIENT → Self Client → CREATE** → copy Client ID + Secret.
2. **Generate Code** tab: scope `ZohoMail.messages.CREATE,ZohoMail.accounts.READ`,
   time 10 minutes → copy the code.
3. Immediately run:
   ```powershell
   ./setup-zoho-mailer.ps1 -ClientId 1000.XXXX -ClientSecret YYYY -GrantCode 1000.ZZZZ
   ```
   It exchanges the code for a permanent refresh token, verifies the token is
   bound to hello@, fills `wrangler.toml`, and uploads the two secrets.
4. `./deploy.ps1`

> ⚠️ Do **not** enable Cloudflare Email Routing on brainzie.co.uk — its wizard
> replaces the Zoho MX records and would break inbound mail to hello@.

Until step 5, read captured leads from KV any time:
```powershell
npx wrangler kv key list --binding LEADS --remote
npx wrangler kv key get "contact:…" --binding LEADS --remote
```

---

## Deploy (after one-time setup)

```powershell
./deploy.ps1                  # publish to production
./deploy.ps1 -Branch preview  # publish a preview URL (not the live domain)
./deploy.ps1 -BuildCourses    # rebuild the Blazor course apps first (needs .NET SDK)
```

## Local development

Full site + working contact Function (simulated KV, no Cloudflare account needed):
```powershell
npx wrangler pages dev        # http://localhost:8788
```
Static pages only: `python -m http.server 8123 --directory site` (the form
posts same-origin, so it needs `wrangler pages dev` to actually submit).

## How the contact form works

`site/contact.html` → `POST /api/contact` → `functions/api/contact.js`:
1. Verifies the Turnstile token (skipped if `TURNSTILE_SECRET` unset).
2. Validates name / email / message.
3. Writes the submission to **KV** (`LEADS`) — a lead is never lost.
4. Emails it to `CONTACT_TO` via the **Zoho Mail API** (access token cached in
   KV; account id auto-discovered or pinned via `ZOHO_ACCOUNT_ID`).
5. Returns JSON; the page shows a success or error message inline.

Adding another form = give any `<form>` a `data-form-type="…"` (e.g.
`"Course enquiry"`), named fields, a `.form-status` element, and load
`assets/form-submit.js`. The Function labels the email/KV entry by that type.
