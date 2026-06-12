@{
    # PUBLIC deploy configuration for the Brainzie site — safe to commit; NEVER put secrets here.
    # Secrets (Turnstile/Zoho keys) live as Cloudflare Pages secrets, uploaded by the
    # Initialize-* functions; this repo uses your 'npx wrangler login' identity to deploy.

    # The Brainzie Cloudflare account id — public configuration, and this committed file is
    # the ONLY place it lives (never a secret store or a required env var). Deploys pin
    # CLOUDFLARE_ACCOUNT_ID to it so a multi-account wrangler identity can never deploy this
    # site into the wrong account, and refuse to run while it is empty.
    # Initialize-BrainzieLanding pins and commits it for you.
    CloudflareAccountId = ''

    # Informational — the production host. Custom domains for this project are managed in the
    # Cloudflare dashboard (see SETUP.md); the deploy does not attach them.
    CustomDomain        = 'brainzie.co.uk'
}
