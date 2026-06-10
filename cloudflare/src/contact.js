// Cloudflare Worker — POST https://api.brainzie.co.uk/api/contact
//
// Backend for the brainzie.co.uk contact form (the site itself is static, on
// GitHub Pages, so this runs as a standalone Worker; the browser posts here
// cross-origin, hence the CORS handling).
//
//   1. Verifies the Cloudflare Turnstile token (free anti-spam; skipped until
//      TURNSTILE_SECRET is configured).
//   2. Stores a durable backup of every submission in the LEADS KV namespace,
//      so a message is never lost even if email delivery hiccups.
//   3. Emails the submission via the SendGrid API once SENDGRID_API_KEY is set
//      (brainzie mail is on Zoho, so the SendGrid sender must be verified
//      first — see SETUP.md).
//
// The form posts a flat JSON object. Two reserved keys:
//   formType               -> labels the email subject + KV key (default "Contact")
//   cf-turnstile-response  -> the Turnstile token
// Every other key is treated as a form field and included in the email.
//
// Bindings / vars / secrets (see SETUP.md / wrangler.toml):
//   LEADS             KV namespace                 (backup of every submission)
//   TURNSTILE_SECRET  secret                       (skipped if unset)
//   SENDGRID_API_KEY  secret                       (email skipped if unset)
//   CONTACT_TO        e.g. "hello@brainzie.co.uk"  (recipient)
//   CONTACT_FROM      e.g. "noreply@brainzie.co.uk" (a verified SendGrid sender)
//   ALLOWED_ORIGINS   comma-separated origins allowed to post the form

const clean = (s) => String(s == null ? "" : s).replace(/[\r\n]+/g, " ").trim().slice(0, 5000);

// Human-readable labels for known field keys (anything else is title-cased).
const LABELS = {
  name: "Name", email: "Email", phone: "Phone", school: "School / organisation",
  topic: "Topic", message: "Message",
};

const labelFor = (k) =>
  LABELS[k] || k.replace(/([A-Z])/g, " $1").replace(/^./, (c) => c.toUpperCase());

function corsHeaders(env, origin) {
  const allowed = (env.ALLOWED_ORIGINS || "").split(",").map((s) => s.trim()).filter(Boolean);
  const allow = allowed.includes(origin) ? origin : allowed[0] || "";
  return {
    "Access-Control-Allow-Origin": allow,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
}

const json = (obj, status, cors) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...cors },
  });

async function verifyTurnstile(secret, token, ip) {
  if (!secret) return true; // not configured yet → skip (KV still captures everything)
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

async function sendViaSendGrid({ apiKey, from, to, replyTo, subject, text }) {
  const res = await fetch("https://api.sendgrid.com/v3/mail/send", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      personalizations: [{ to: [{ email: to }] }],
      from: { email: from, name: "Brainzie Website" },
      reply_to: { email: replyTo },
      subject: subject.slice(0, 180),
      content: [{ type: "text/plain", value: text }],
    }),
  });
  if (res.ok || res.status === 202) return true;
  console.error("SendGrid failed:", res.status, await res.text().catch(() => ""));
  return false;
}

export default {
  async fetch(request, env) {
    const origin = request.headers.get("Origin") || "";
    const cors = corsHeaders(env, origin);
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    if (url.pathname !== "/api/contact") {
      return json({ ok: false, error: "Not found." }, 404, cors);
    }
    if (request.method !== "POST") {
      return json({ ok: false, error: "Method not allowed." }, 405, cors);
    }

    let payload;
    try {
      payload = await request.json();
    } catch {
      return json({ ok: false, error: "Invalid request." }, 400, cors);
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
      return json({ ok: false, error: "Name, email and message are required." }, 400, cors);
    }
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      return json({ ok: false, error: "Please enter a valid email address." }, 400, cors);
    }

    const ip = request.headers.get("CF-Connecting-IP") || "";
    const ok = await verifyTurnstile(env.TURNSTILE_SECRET, token, ip);
    if (!ok) {
      return json({ ok: false, error: "Anti-spam check failed. Please try again." }, 400, cors);
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

    // 2) Email via SendGrid (once SENDGRID_API_KEY is configured)
    if (env.SENDGRID_API_KEY && env.CONTACT_TO && env.CONTACT_FROM) {
      try {
        const subject = `[${formType}] ${name}${fields.school ? " — " + fields.school : ""}`;
        const sent = await sendViaSendGrid({
          apiKey: env.SENDGRID_API_KEY,
          from: env.CONTACT_FROM,
          to: env.CONTACT_TO,
          replyTo: email,
          subject,
          text,
        });
        if (sent) delivered = true;
      } catch (e) {
        console.error("SendGrid error:", e);
      }
    }

    if (!delivered) {
      return json(
        { ok: false, error: "We couldn't deliver your message. Please email hello@brainzie.co.uk." },
        500,
        cors
      );
    }

    return json({ ok: true }, 200, cors);
  },
};
