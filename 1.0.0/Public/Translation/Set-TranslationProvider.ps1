function Set-TranslationProvider {
    <#
    .SYNOPSIS
        Activates a saved provider, or saves and activates a new/updated provider config.
    .DESCRIPTION
        Calling with only -Name activates an already-saved provider as the default.
        Passing additional parameters creates or updates that provider's saved config.
        API keys are encrypted with Windows DPAPI (CurrentUser) and stored in:
          %APPDATA%\SubtitleTools\providers.json
        No vault or password is required.
    .PARAMETER Name
        Provider name: OpenAI, Anthropic, or Google.
    .PARAMETER Model
        Model ID. Defaults to the recommended model for each provider.
    .PARAMETER ApiKeyPlainText
        API key as plain text (encrypted before saving).
    .PARAMETER ApiKey
        API key as SecureString (encrypted before saving).
    .PARAMETER BaseUrl
        Custom API endpoint (for proxies or alternative endpoints).
    .PARAMETER RateLimitRpm
        Maximum requests per minute.
    .PARAMETER MaxTokensPerBatch
        Maximum tokens per API call.
    .PARAMETER Temperature
        Sampling temperature (0.0-1.0).
    .EXAMPLE
        # First-time setup
        Set-TranslationProvider -Name Google -ApiKeyPlainText 'AIza...'
    .EXAMPLE
        # Switch to a previously saved provider
        Set-TranslationProvider -Name Anthropic
    .EXAMPLE
        # Update just the model for an existing provider
        Set-TranslationProvider -Name Google -Model 'gemini-1.5-pro'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('OpenAI', 'Anthropic', 'Google')]
        [string] $Name,

        [string]      $Model,
        [string]      $ApiKeyPlainText,
        [SecureString] $ApiKey,
        [string]      $BaseUrl,
        [int]         $RateLimitRpm,
        [int]         $MaxTokensPerBatch,
        [decimal]     $Temperature
    )

    $isUpdate = $PSBoundParameters.Count -gt 1  # more than just -Name

    if ($isUpdate) {
        # Load existing saved config, or seed from defaults for a new provider
        if ($script:ConfiguredProviders.ContainsKey($Name)) {
            $provider = $script:ConfiguredProviders[$Name]
        } else {
            $d = $script:ProviderDefaults.$Name
            if (-not $d) { throw "No defaults found for provider '$Name'." }
            $provider                    = [TranslationProvider]::new()
            $provider.Name               = $Name
            $provider.Model              = $d.Model
            $provider.BaseUrl            = $d.BaseUrl
            $provider.RateLimitRpm       = $d.RateLimitRpm
            $provider.MaxTokensPerBatch  = $d.MaxTokensPerBatch
            $provider.Temperature        = $d.Temperature
        }

        # Apply only the params that were explicitly supplied
        if ($PSBoundParameters.ContainsKey('Model'))             { $provider.Model             = $Model }
        if ($PSBoundParameters.ContainsKey('BaseUrl'))           { $provider.BaseUrl           = $BaseUrl }
        if ($PSBoundParameters.ContainsKey('RateLimitRpm'))      { $provider.RateLimitRpm      = $RateLimitRpm }
        if ($PSBoundParameters.ContainsKey('MaxTokensPerBatch')) { $provider.MaxTokensPerBatch = $MaxTokensPerBatch }
        if ($PSBoundParameters.ContainsKey('Temperature'))       { $provider.Temperature       = $Temperature }

        # Encrypt and store API key if supplied
        $plainKey = $null
        if ($ApiKeyPlainText) {
            $plainKey = $ApiKeyPlainText
        } elseif ($ApiKey) {
            $plainKey = [System.Net.NetworkCredential]::new('', $ApiKey).Password
        }
        if ($plainKey) {
            $provider.ApiKeyEncrypted = Protect-ApiKey -PlainText $plainKey
            Write-Verbose "API key encrypted and saved for '$Name'."
        }

        $script:ConfiguredProviders[$Name] = $provider
    } else {
        # Activate-only: provider must already be saved
        if (-not $script:ConfiguredProviders.ContainsKey($Name)) {
            throw "Provider '$Name' has no saved configuration. Run Set-TranslationProvider -Name $Name -ApiKeyPlainText 'your-key' to set it up first."
        }
    }

    $script:DefaultProvider = $Name
    Save-ProviderStore
    Write-Verbose "Provider '$Name' is now active."
}
