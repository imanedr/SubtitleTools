function Get-TranslationProvider {
    <#
    .SYNOPSIS
        Lists saved translation providers and their configuration.
    .PARAMETER Name
        Filter by provider name (OpenAI, Anthropic, Google, OpenRouter).
    .EXAMPLE
        Get-TranslationProvider
    .EXAMPLE
        Get-TranslationProvider -Name Google
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [ValidateSet('OpenAI', 'Anthropic', 'Google', 'OpenRouter')]
        [string] $Name
    )

    $providers = $script:ConfiguredProviders.Values

    if ($Name) {
        $providers = $providers | Where-Object { $_.Name -eq $Name }
    }

    foreach ($provider in $providers) {
        [PSCustomObject]@{
            Name              = $provider.Name
            Model             = $provider.Model
            HasApiKey         = -not [string]::IsNullOrEmpty($provider.ApiKeyEncrypted)
            BaseUrl           = $provider.BaseUrl
            RateLimitRpm      = $provider.RateLimitRpm
            MaxTokensPerBatch  = $provider.MaxTokensPerBatch
            MaxEntriesPerBatch = $provider.MaxEntriesPerBatch
            MaxOutputTokens    = $provider.MaxOutputTokens
            Temperature       = $provider.Temperature
            IsDefault         = ($provider.Name -eq $script:DefaultProvider)
        }
    }
}
