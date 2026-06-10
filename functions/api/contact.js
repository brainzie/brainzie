// Cloudflare Pages Function — POST /api/contact
//
// Backend for the brainzie.co.uk contact form (same-origin: the site and this
// Function are served by the same Cloudflare Pages project):
//   1. Verifies the Cloudflare Turnstile token (free anti-spam; skipped until
//      TURNSTILE_SECRET is configured).
//   2. Stores a durable backup of every submission in the LEADS KV namespace,
//      so a message is never lost even if email delivery hiccups.
//   3. Emails the submission via the Zoho Mail API. hello@brainzie.co.uk is a
//      GROUP (it cannot sign in or own OAuth grants); the only user is
//      directors@brainzie.co.uk, so mail is sent FROM directors@ TO hello@
//      (the group receives fine). Sending from the real mailbox keeps
//      SPF/DKIM/DMARC inherently correct — NO DNS changes needed. The OAuth
//      refresh token is a Zoho "Self Client" grant minted BY directors@ with
//      only the ZohoMail.messages.CREATE (+ accounts.READ) scopes, so it can
//      only ever act as that one mailbox — the Zoho analogue of emsurge's
//      Exchange application access policy, enforced by construction.
//
// The form posts a flat JSON object. Two reserved keys:
//   formType               -> labels the email subject + KV key (default "Contact")
//   cf-turnstile-response  -> the Turnstile token
// Every other key is treated as a form field and included in the email.
//
// Bindings / vars / secrets (see SETUP.md / wrangler.toml; configured by the
// BrainzieLanding PowerShell module — Initialize-BrainzieZohoMailer):
//   LEADS               KV namespace                  (backup + Zoho token cache)
//   TURNSTILE_SECRET    secret                        (skipped if unset)
//   ZOHO_CLIENT_ID      var                           (Self Client id)
//   ZOHO_CLIENT_SECRET  secret                        (email skipped if unset)
//   ZOHO_REFRESH_TOKEN  secret                        (email skipped if unset)
//   ZOHO_ACCOUNTS_BASE  var, e.g. https://accounts.zoho.com (.eu/.in per DC)
//   ZOHO_MAIL_BASE      var, e.g. https://mail.zoho.com
//   ZOHO_ACCOUNT_ID     var, optional                 (auto-discovered if empty)
//   CONTACT_TO          "hello@brainzie.co.uk"        (recipient — the group)
//   CONTACT_FROM        "directors@brainzie.co.uk"    (the USER mailbox the app sends as)

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });

const clean = (s) => String(s == null ? "" : s).replace(/[\r\n]+/g, " ").trim().slice(0, 5000);

// Human-readable labels for known field keys (anything else is title-cased).
const LABELS = {
  name: "Name", email: "Email", phone: "Phone", school: "School / organisation",
  topic: "Topic", message: "Message",
};

const labelFor = (k) =>
  LABELS[k] || k.replace(/([A-Z])/g, " $1").replace(/^./, (c) => c.toUpperCase());

async function verifyTurnstile(secret, token, ip) {
  if (!secret) return true; // not configured (e.g. local dev) → skip
  if (!token) return false;
  const body = new FormData();
  body.append("secret", secret);
  body.append("response", token);
  if (ip) body.append("remoteip", ip);
  const r = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
    method: "POST",
    body,
  });
  const data = await r.json().catch(() => ({ success: false }));
  return data.success === true;
}

// --- Zoho Mail -------------------------------------------------------------

// Access tokens last ~1 hour; cache in KV so we don't hit Zoho's token-mint
// rate limits on every submission.
async function getZohoAccessToken(env) {
  const CACHE_KEY = "zoho:access-token";
  if (env.LEADS) {
    const cached = await env.LEADS.get(CACHE_KEY).catch(() => null);
    if (cached) return cached;
  }
  const res = await fetch(`${env.ZOHO_ACCOUNTS_BASE}/oauth/v2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      client_id: env.ZOHO_CLIENT_ID,
      client_secret: env.ZOHO_CLIENT_SECRET,
      refresh_token: env.ZOHO_REFRESH_TOKEN,
    }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || !data.access_token) {
    console.error("Zoho token failed:", res.status, data.error || "");
    return null;
  }
  if (env.LEADS) {
    const ttl = Math.max(60, (data.expires_in || 3600) - 120);
    await env.LEADS.put(CACHE_KEY, data.access_token, { expirationTtl: ttl }).catch(() => {});
  }
  return data.access_token;
}

// The send endpoint needs the numeric Zoho Mail account id of CONTACT_FROM.
// Configure ZOHO_ACCOUNT_ID to pin it, or let this discover + cache it.
async function getZohoAccountId(env, accessToken) {
  if (env.ZOHO_ACCOUNT_ID) return env.ZOHO_ACCOUNT_ID;
  const CACHE_KEY = "zoho:account-id";
  if (env.LEADS) {
    const cached = await env.LEADS.get(CACHE_KEY).catch(() => null);
    if (cached) return cached;
  }
  const res = await fetch(`${env.ZOHO_MAIL_BASE}/api/accounts`, {
    headers: { Authorization: `Zoho-oauthtoken ${accessToken}` },
  });
  const data = await res.json().catch(() => ({}));
  const accounts = data && data.data;
  if (!res.ok || !Array.isArray(accounts) || !accounts.length) {
    console.error("Zoho accounts lookup failed:", res.status);
    return null;
  }
  const from = (env.CONTACT_FROM || "").toLowerCase();
  const match =
    accounts.find((a) => (a.primaryEmailAddress || "").toLowerCase() === from) ||
    accounts.find((a) =>
      (a.emailAddress || []).some((e) => (e.mailId || "").toLowerCase() === from)
    ) ||
    accounts[0];
  const id = match && (match.accountId || match.account_id);
  if (!id) return null;
  if (env.LEADS) await env.LEADS.put(CACHE_KEY, String(id)).catch(() => {});
  return String(id);
}

async function sendViaZoho(env, { from, to, replyTo, subject, text }) {
  const accessToken = await getZohoAccessToken(env);
  if (!accessToken) return false;
  const accountId = await getZohoAccountId(env, accessToken);
  if (!accountId) return false;

  const res = await fetch(`${env.ZOHO_MAIL_BASE}/api/accounts/${accountId}/messages`, {
    method: "POST",
    headers: {
      Authorization: `Zoho-oauthtoken ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      fromAddress: from,
      toAddress: to,
      subject: subject.slice(0, 180),
      content: text,
      mailFormat: "plaintext",
      // Replies in the mail client go straight to the person who filled the form.
      replyTo: replyTo,
      askReceipt: "no",
    }),
  });
  const data = await res.json().catch(() => ({}));
  if (res.ok && data.status && data.status.code === 200) return true;
  console.error("Zoho sendMail failed:", res.status, JSON.stringify(data.status || data).slice(0, 300));
  return false;
}

// --- Request handler --------------------------------------------------------

export async function onRequestPost({ request, env }) {
  let payload;
  try {
    payload = await request.json();
  } catch {
    return json({ ok: false, error: "Invalid request." }, 400);
  }

  const token = payload["cf-turnstile-response"];
  const formType = clean(payload.formType) || "Contact";

  // Collect every field except reserved keys.
  const fields = {};
  for (const [k, v] of Object.entries(payload)) {
    if (k === "cf-turnstile-response" || k === "formType") continue;
    const val = Array.isArray(v) ? v.map(clean).filter(Boolean).join(", ") : clean(v);
    if (val) fields[k] = val;
  }

  const name = fields.name || "";
  const email = fields.email || "";

  if (!name || !email || !fields.message) {
    return json({ ok: false, error: "Name, email and message are required." }, 400);
  }
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    return json({ ok: false, error: "Please enter a valid email address." }, 400);
  }

  const ip = request.headers.get("CF-Connecting-IP") || "";
  const ok = await verifyTurnstile(env.TURNSTILE_SECRET, token, ip);
  if (!ok) {
    return json({ ok: false, error: "Anti-spam check failed. Please try again." }, 400);
  }

  const when = new Date().toISOString();

  // Build a readable email body: name/email first, then the rest.
  const order = ["name", "email", "school", "topic"];
  const seen = new Set();
  const linesOut = [];
  for (const k of order) {
    if (fields[k]) { linesOut.push(`${labelFor(k)}: ${fields[k]}`); seen.add(k); }
  }
  for (const [k, v] of Object.entries(fields)) {
    if (seen.has(k)) continue;
    linesOut.push(`${labelFor(k)}: ${v}`);
  }
  const text =
    `New "${formType}" submission from brainzie.co.uk\n\n` +
    linesOut.join("\n") +
    `\n\nTime: ${when}\nIP:   ${ip || "—"}\n`;

  let delivered = false;

  // 1) Durable backup in KV (best-effort)
  if (env.LEADS) {
    try {
      await env.LEADS.put(
        `${formType.toLowerCase().replace(/\s+/g, "-")}:${when}:${crypto.randomUUID()}`,
        JSON.stringify({ formType, ...fields, when, ip })
      );
      delivered = true;
    } catch (e) {
      console.error("KV store failed:", e);
    }
  }

  // 2) Email via Zoho Mail (sends from the hello@ mailbox itself; no DNS involved)
  if (env.ZOHO_CLIENT_SECRET && env.ZOHO_REFRESH_TOKEN && env.ZOHO_CLIENT_ID &&
      env.CONTACT_TO && env.CONTACT_FROM) {
    try {
      const subject = `[${formType}] ${name}${fields.school ? " — " + fields.school : ""}`;
      const sent = await sendViaZoho(env, {
        from: env.CONTACT_FROM,
        to: env.CONTACT_TO,
        replyTo: email,
        subject,
        text,
      });
      if (sent) delivered = true;
    } catch (e) {
      console.error("Zoho error:", e);
    }
  }

  if (!delivered) {
    return json(
      { ok: false, error: "We couldn't deliver your message. Please email hello@brainzie.co.uk." },
      500
    );
  }

  return json({ ok: true });
}

// Only POST is handled; Pages returns 405 for other methods automatically.
