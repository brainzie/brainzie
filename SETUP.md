# Brainzie site — setup & publishing (Cloudflare Pages)

The site is a **pure static site** in [`site/`](site/) — hand-written HTML, the
shared CSS/JS in `site/assets/`, the courses (including the committed Blazor
WASM apps), and a single Cloudflare Pages Function for the contact form. Same
model as `emsurge-landingpage`. All operational tooling lives in the
**BrainzieLanding PowerShell module** (`scripts/BrainzieLanding`), following the
same structure as the EOM / BMoney modules.

```
functions/   api/contact.js      ← backend for the contact form (root, per wrangler.toml config mode)
site/                            ← published output (pages_build_output_dir)
  index.html  courses.html  software.html  about.html  contact.html
  brainzie-money.html  product-swim.html  brand-guidelines.html  404.html
  assets/    brainzie.css, lesson.css, lesson.js, form-submit.js, …
  brand/     logos + favicons
  courses/   <slug>/index.html, lessons/…, app/ (committed Blazor WASM output)
apps-src/    Blazor source, one project per course (NOT published)
scripts/     BrainzieLanding/    ← the PowerShell module (psd1/psm1, Public/, Private/)
tools/       templates/lesson.html
wrangler.toml  SETUP.md          (repo root — not published)
```

> **Functions location matters.** Because `wrangler.toml` sets
> `pages_build_output_dir`, the `functions/` directory lives at the **project
> root** (sibling of `wrangler.toml`), and deploys run **without** a positional
> directory — the module does this correctly.

GitHub remains the source of truth (push as usual), but **pushing does not
publish** — publishing is `Publish-BrainzieLanding`. The `build-courses` GitHub
Action still rebuilds the Blazor apps into `site/courses/<slug>/app` when
`apps-src/**` changes.

## The module

```powershell
Import-Module ./scripts/BrainzieLanding/BrainzieLanding.psd1

Initialize-BrainzieLanding        # one-time: Pages project + LEADS KV + Turnstile secret
Initialize-BrainzieZohoMailer …   # one-time: wire the Zoho mailer (see Email below)
Build-BrainzieCourseApp -Course 08  # rebuild one course's Blazor app into site/
Publish-BrainzieLanding           # deploy to production
Publish-BrainzieLanding -Branch preview   # preview URL instead
Publish-BrainzieLanding -BuildCourses     # rebuild all course apps first
```

> ⚠️ **Cloudflare account.** Everything deploys into the Cloudflare account
> that owns the brainzie.co.uk zone — NOT the emsurge account whose
> `CLOUDFLARE_API_TOKEN` may be set in your shell. The module clears that
> variable automatically and uses your `npx wrangler login` identity
> (or pass `-ApiToken` with a brainzie-account token).

---

## One-time setup

### 1. Log in and scaffold
```powershell
npx wrangler login          # browser sign-in to the BRAINZIE Cloudflare account
Import-Module ./scripts/BrainzieLanding/BrainzieLanding.psd1
Initialize-BrainzieLanding
```
Copy the returned KV namespace **id** into `wrangler.toml` → `[[kv_namespaces]] id = "…"`.

### 2. First deploy (to the *.pages.dev URL)
```powershell
Publish-BrainzieLanding
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
3. Secret key: re-run `Initialize-BrainzieLanding` (or
   `npx wrangler pages secret put TURNSTILE_SECRET --project-name brainzie`). Redeploy.

### 5. Email — Zoho Mail API (no SendGrid, no DNS changes)
**Identity model — a dedicated service account, never a person's account.**
`hello@brainzie.co.uk` is a **group** — groups cannot sign in or own OAuth
grants — and personal accounts shouldn't hold unattended credentials. So a
dedicated service user, **`svc-mailer@brainzie.co.uk`** ("Brainzie Website
Mailer"), owns the OAuth grant: you can disable, rotate or audit it in the
Zoho admin console without touching anyone's personal account. The `svc-<function>@`
naming scales — add `svc-backup@`, `svc-reports@`, … later, one identity per
function, each with only the access that function needs.

The service user is made a **member of each group it should send as** (with
the group's *"members can send emails as group"* setting enabled), so the form
sends **FROM hello@ TO hello@**. Mail leaves through Zoho itself, keeping
SPF/DKIM/DMARC inherently right — the same property emsurge gets from
Microsoft Graph `sendMail`.

**Single-mailbox restriction, by construction:** a Zoho **Self Client** refresh
token is minted *by* the signed-in user. Generated as `svc-mailer@`, scoped to
`ZohoMail.messages.CREATE` (send-only), it can only ever act as that mailbox
plus its granted group send-as addresses. (Microsoft app-only tokens are
tenant-wide until an Exchange application access policy narrows them — Zoho
needs no equivalent policy.)

1. Zoho **Admin console → Users**: create `svc-mailer@brainzie.co.uk`
   (display name "Brainzie Website Mailer"; needs a mail license).
2. **Groups → hello@**: add `svc-mailer@` as a member and enable
   *"members can send emails as group"* (or the per-member send-as option).
3. Sign in to Zoho **as svc-mailer@** → https://api-console.zoho.com →
   **ADD CLIENT → Self Client → CREATE** → copy Client ID + Secret.
4. **Generate Code** tab: scope `ZohoMail.messages.CREATE,ZohoMail.accounts.READ`,
   time 10 minutes → copy the code.
5. Immediately run:
   ```powershell
   Initialize-BrainzieZohoMailer -ClientId 1000.XXXX -ClientSecret YYYY -GrantCode 1000.ZZZZ
   ```
   It exchanges the code for a permanent refresh token, verifies the token is
   bound to the service account, checks that `CONTACT_FROM` (hello@) is among
   the From addresses the token may use (it warns if step 2 was missed), fills
   `wrangler.toml`, and uploads the two secrets.
6. `Publish-BrainzieLanding`

> Named the account differently (e.g. `auto@`)? Pass
> `-ExpectedMailbox auto@brainzie.co.uk` in step 5 — nothing else changes.
> If you skip the send-as-group setting, set
> `CONTACT_FROM = "svc-mailer@brainzie.co.uk"` in `wrangler.toml` instead.

> ⚠️ Do **not** enable Cloudflare Email Routing on brainzie.co.uk — its wizard
> replaces the Zoho MX records and would break inbound mail.

Until step 5, read captured leads from KV any time:
```powershell
npx wrangler kv key list --binding LEADS --remote
npx wrangler kv key get "contact:…" --binding LEADS --remote
```

---

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
4. Emails it to `CONTACT_TO` (hello@, the group) via the **Zoho Mail API**,
   sent from `CONTACT_FROM` (directors@). Access token cached in KV; account
   id auto-discovered or pinned via `ZOHO_ACCOUNT_ID`.
5. Returns JSON; the page shows a success or error message inline.

Adding another form = give any `<form>` a `data-form-type="…"` (e.g.
`"Course enquiry"`), named fields, a `.form-status` element, and load
`assets/form-submit.js`. The Function labels the email/KV entry by that type.
