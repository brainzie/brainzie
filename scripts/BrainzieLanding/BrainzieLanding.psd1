@{
    ModuleVersion     = '1.0.0'
    GUID              = '7c2f49e3-58b1-4f12-9a44-d3c0a4be6f21'
    Author            = 'Brainzie'
    Description       = 'Deployment and management tooling for the Brainzie site (Cloudflare Pages + Zoho mailer + Blazor course apps).'
    PowerShellVersion = '7.0'

    RootModule        = 'BrainzieLanding.psm1'

    # Only public functions are exported — private helpers are not listed here
    FunctionsToExport = @(
        'Initialize-BrainzieLanding',
        'Initialize-BrainzieZohoMailer',
        'Build-BrainzieCourseApp',
        'Publish-BrainzieLanding'
    )

    PrivateData = @{
        PSData = @{
            Tags = @('Cloudflare', 'Pages', 'Blazor', 'Deployment', 'Brainzie', 'Zoho')
        }
    }
}
