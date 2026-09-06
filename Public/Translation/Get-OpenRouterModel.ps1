function Get-OpenRouterModel {
    <#
    .SYNOPSIS
        Lists models available through the OpenRouter API.
    .DESCRIPTION
        Calls OpenRouter's GET /models endpoint, which is public and requires no
        authentication. If an OpenRouter provider has already been saved via
        Set-TranslationProvider (with an API key), its key is sent opportunistically
        as a bearer token - but decrypting it requires Windows DPAPI, so on
        non-Windows platforms (or if decryption fails for any reason) this degrades
        gracefully to an unauthenticated call rather than failing the whole cmdlet.

        Use this to discover current model IDs (the "vendor/model" slug format
        OpenRouter expects, e.g. 'anthropic/claude-sonnet-5') before configuring
        Set-TranslationProvider -Name OpenRouter.
    .PARAMETER Filter
        Optional wildcard pattern matched against each model's Id and Name
        (case-insensitive). Only matching models are returned.
    .PARAMETER BaseUrl
        Override the OpenRouter API base URL. Defaults to the saved OpenRouter
        provider's BaseUrl if one is configured, otherwise the value from
        Data/ProviderDefaults.json.
    .OUTPUTS
        PSCustomObject: Id, Name, ContextLength, MaxOutputTokens,
        PromptPricePerMTok, CompletionPricePerMTok
    .EXAMPLE
        Get-OpenRouterModel | Sort-Object PromptPricePerMTok | Select-Object -First 10
    .EXAMPLE
        Get-OpenRouterModel -Filter 'anthropic/*' | Format-Table Id, ContextLength, PromptPricePerMTok
    .EXAMPLE
        Get-OpenRouterModel -Filter '*claude*' -BaseUrl 'https://openrouter.ai/api/v1'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [string] $Filter,

        [string] $BaseUrl
    )

    if (-not $BaseUrl) {
        if ($script:ConfiguredProviders.ContainsKey('OpenRouter')) {
            $BaseUrl = $script:ConfiguredProviders['OpenRouter'].BaseUrl
        } elseif ($script:ProviderDefaults.OpenRouter) {
            $BaseUrl = $script:ProviderDefaults.OpenRouter.BaseUrl
        } else {
            throw 'Get-OpenRouterModel: no BaseUrl was supplied and no OpenRouter default is available.'
        }
    }

    $headers = @{}

    if ($script:ConfiguredProviders.ContainsKey('OpenRouter')) {
        $encryptedKey = $script:ConfiguredProviders['OpenRouter'].ApiKeyEncrypted
        if (-not [string]::IsNullOrEmpty($encryptedKey)) {
            try {
                $plainKey            = Unprotect-ApiKey -EncryptedBase64 $encryptedKey
                $headers.Authorization = "Bearer $plainKey"
            } catch {
                # Decryption requires Windows DPAPI - on non-Windows platforms (or
                # any other decryption failure) fall back to the unauthenticated
                # call, since listing models does not require a key.
                Write-Verbose "Get-OpenRouterModel: could not decrypt saved OpenRouter API key, continuing unauthenticated: $_"
            }
        }
    }

    $result = Invoke-TranslationApiRequest -Uri "$BaseUrl/models" -Method Get -Headers $headers -ProviderLabel 'OpenRouter'

    if (-not $result.Success) {
        throw "Get-OpenRouterModel: request failed (status=$($result.StatusCode)): $($result.ErrorMessage)"
    }

    $models = $result.Response.data

    foreach ($model in $models) {
        if ($Filter -and ($model.id -notlike $Filter) -and ($model.name -notlike $Filter)) {
            continue
        }

        $promptPrice     = $null
        $completionPrice = $null

        if ($model.pricing) {
            if (-not [string]::IsNullOrEmpty($model.pricing.prompt)) {
                $promptPrice = [decimal]$model.pricing.prompt * 1000000
            }
            if (-not [string]::IsNullOrEmpty($model.pricing.completion)) {
                $completionPrice = [decimal]$model.pricing.completion * 1000000
            }
        }

        $maxOutputTokens = $null
        if ($model.top_provider -and $null -ne $model.top_provider.max_completion_tokens) {
            $maxOutputTokens = [int]$model.top_provider.max_completion_tokens
        }

        [PSCustomObject]@{
            Id                     = $model.id
            Name                   = $model.name
            ContextLength          = $model.context_length
            MaxOutputTokens        = $maxOutputTokens
            PromptPricePerMTok     = $promptPrice
            CompletionPricePerMTok = $completionPrice
        }
    }
}
