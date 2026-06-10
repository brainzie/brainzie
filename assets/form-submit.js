/* Shared client-side handler for Brainzie forms.
   Attaches to any <form data-form-type="…">, serialises all named fields,
   includes the Turnstile token (when configured), and POSTs JSON to the
   contact Worker on api.brainzie.co.uk (the site itself is static).
   Expects a .form-status element and a submit button inside the form. */
(function () {
  // Local development: `npx wrangler dev` serves the Worker on :8787.
  var API_BASE =
    location.hostname === "localhost" || location.hostname === "127.0.0.1"
      ? "http://localhost:8787"
      : "https://api.brainzie.co.uk";

  // Render Turnstile only when a site key is configured (data-turnstile-sitekey).
  // Until then the form still works — the Worker skips verification too.
  function mountTurnstile(form) {
    var sitekey = form.getAttribute("data-turnstile-sitekey");
    if (!sitekey) return;
    var slot = form.querySelector(".turnstile-slot");
    if (!slot) return;
    slot.innerHTML = '<div class="cf-turnstile" data-sitekey="' + sitekey + '"></div>';
    if (!document.querySelector('script[src*="challenges.cloudflare.com/turnstile"]')) {
      var s = document.createElement("script");
      s.src = "https://challenges.cloudflare.com/turnstile/v0/api.js";
      s.async = true;
      s.defer = true;
      document.head.appendChild(s);
    }
  }

  function init(form) {
    var statusEl = form.querySelector(".form-status");
    var btn = form.querySelector('button[type="submit"]');
    var btnLabel = btn ? btn.textContent : "Send";

    mountTurnstile(form);

    function setStatus(kind, msg) {
      if (!statusEl) return;
      statusEl.className = "form-status " + kind;
      statusEl.textContent = msg;
    }

    form.addEventListener("submit", async function (e) {
      e.preventDefault();

      var payload = { formType: form.getAttribute("data-form-type") || "Contact" };
      var missing = false;
      form.querySelectorAll("[name]").forEach(function (el) {
        if (!el.name || el.name === "cf-turnstile-response") return;
        payload[el.name] = (el.value || "").trim();
        if (el.required && !payload[el.name]) missing = true;
      });

      if (missing || !payload.name || !payload.email || !payload.message) {
        setStatus("err", "Please complete all required fields.");
        return;
      }

      var tokenEl = form.querySelector('[name="cf-turnstile-response"]');
      payload["cf-turnstile-response"] = tokenEl ? tokenEl.value : "";

      if (btn) { btn.disabled = true; btn.textContent = "Sending…"; }
      try {
        var res = await fetch(API_BASE + "/api/contact", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        });
        var data = await res.json().catch(function () { return {}; });
        if (res.ok && data.ok) {
          setStatus("ok", "Thanks — your message is on its way. We'll get back to you soon.");
          form.reset();
          if (window.turnstile) window.turnstile.reset();
        } else {
          setStatus("err", (data && data.error) || "Something went wrong. Please email hello@brainzie.co.uk.");
        }
      } catch (err) {
        setStatus("err", "We couldn't reach the server. Please email hello@brainzie.co.uk.");
      } finally {
        if (btn) { btn.disabled = false; btn.textContent = btnLabel; }
      }
    });
  }

  document.querySelectorAll("form[data-form-type]").forEach(init);
})();
