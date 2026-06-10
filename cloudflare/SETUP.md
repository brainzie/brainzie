# Brainzie contact form — Cloudflare Worker setup

The brainzie.co.uk **site stays on GitHub Pages**. Only the contact-form
backend runs on Cloudflare, as a Worker at **`https://api.brainzie.co.uk/api/contact`**
(the brainzie.co.uk DNS zone is already on Cloudflare, so the custom domain is
created automatically on first deploy — no risk to the existing site).

```
cloudflare/
  src/contact.js   ← the Worker (Turnstile → KV backup → SendGrid email)
  wrangler.toml    ← Worker config (custom domain, KV binding, vars)
  deploy.ps1       ← deploy script with an account guard
assets/form-submit.js   ← client script; posts any <form data-form-type="…">
contact.html            ← the form
```

How a submission flows:
1. `contact.html` → `POST https://api.brainzie.co.uk/api/contact` (CORS-allowed origins in `wrangler.toml`).
2. Worker verifies the **Turnstile** token (skipped until `TURNSTILE_SECRET` is set).
3. Worker writes the submission to the **LEADS KV namespace** — a lead is never lost.
4. Worker emails it to `CONTACT_TO` via **SendGrid** (skipped until `SENDGRID_API_KEY` is set).

So the form is useful from the moment the Worker deploys: even with no
Turnstile and no SendGrid, every message is captured in KV.

---

## One-time setup (≈10 minutes)

> ⚠️ **Account matters.** Deploy with the Cloudflare account that owns the
> brainzie.co.uk zone — NOT the emsurge token that may be in your shell env.
> `deploy.ps1` guards against this automatically. If you've never logged in on
> this machine: `npx wrangler login` (opens the browser) first.

### 1. KV namespace + secrets
```powershell
cd F:\src\brainzie\cloudflare
./deploy.ps1 -Setup
```
- Paste the returned KV namespace **id** into `wrangler.toml` → `[[kv_namespaces]] id = "…"`.
- Skip the secret prompts with Ctrl+C if you don't have the keys yet.

### 2. Deploy
```powershell
./deploy.ps1
```
This publishes the Worker **and** creates the `api.brainzie.co.uk` custom
domain on the zone. The form on brainzie.co.uk/contact.html starts working
immediately (submissions land in KV).

### 3. Turnstile (free anti-spam) — recommended
1. Cloudflare dashboard → **Turnstile** → **Add widget** → hostnames `brainzie.co.uk` (+ `localhost` for testing).
2. Paste the **Site key** into `contact.html` → `data-turnstile-sitekey="…"`, commit & push.
3. Set the **Secret key**: `npx wrangler secret put TURNSTILE_SECRET` (from `cloudflare/`).

### 4. Email delivery — SendGrid (optional but recommended)
Brainzie mail is on **Zoho** (`include:zohomail.com` SPF), so unlike emsurge,
SendGrid is not yet authorised for the domain:
1. Create a (free-tier) SendGrid account, then **Sender Authentication**: either
   verify the single sender `noreply@brainzie.co.uk`, or authenticate the domain
   (SendGrid gives you 3 CNAMEs to add in Cloudflare DNS — additive, does NOT
   touch the Zoho MX/SPF records, inbound mail is unaffected).
2. Create an API key with **Mail Send** permission.
3. `npx wrangler secret put SENDGRID_API_KEY` (from `cloudflare/`).

> ⚠️ Do **not** enable Cloudflare Email Routing on brainzie.co.uk — its wizard
> replaces the Zoho MX records and would break inbound mail to hello@.

Until step 4, read captured leads from KV any time:
```powershell
cd F:\src\brainzie\cloudflare
npx wrangler kv key list --binding LEADS --remote
npx wrangler kv key get "contact:…" --binding LEADS --remote
```

---

## Local development

Run the Worker locally (simulated KV, no Cloudflare account needed):
```powershell
cd F:\src\brainzie\cloudflare
npx wrangler dev   # serves http://localhost:8787
```
Serve the site (e.g. `python -m http.server 8123 --directory F:\src\brainzie`) and
open `http://localhost:8123/contact.html` — `form-submit.js` automatically posts
to `localhost:8787` when the page is served from localhost.

## Adding more forms later
Same pattern as the emsurge site: give any new `<form>` a `data-form-type="…"`
attribute (e.g. `"Course enquiry"`), include named fields plus a `.form-status`
element, and load `assets/form-submit.js`. The Worker labels the email/KV entry
by that type — no backend changes needed.
