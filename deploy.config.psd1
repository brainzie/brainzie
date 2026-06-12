@{
    # PUBLIC deploy configuration for the Brainzie site — safe to commit; NEVER put secrets here.
    # Secrets (Turnstile/Zoho keys) live as Cloudflare Pages secrets, uploaded by the
    # Initialize-* functions; this repo uses your 'npx wrangler login' identity to deploy.

    # The Brainzie Cloudflare account id. When set, deploys pin CLOUDFLARE_ACCOUNT_ID to it so
    # a multi-account wrangler identity can never deploy this site into the wrong account
    # (empty skips the pinning, with a warning).
    CloudflareAccountId = ''

    # Informational — the production host. Custom domains for this project are managed in the
    # Cloudflare dashboard (see SETUP.md); the deploy does not attach them.
    CustomDomain        = 'brainzie.co.uk'
}
