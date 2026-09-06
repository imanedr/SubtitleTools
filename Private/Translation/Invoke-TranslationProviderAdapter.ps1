function Invoke-TranslationProviderAdapter {
    <#
    .SYNOPSIS
        Dispatches a translation API call to the adapter for the given provider.
    .DESCRIPTION
        Single source of truth for provider dispatch, replacing what used to be a
        `switch ($prov.Name)` duplicated in Invoke-SubtitleTranslation.ps1 and
        Invoke-TranslationPriming.ps1. Adding a new provider means adding one case
        here rather than touching every call site.
    .PARAMETER SystemPrompt
        The system prompt to send.
    .PARAMETER UserContent
        The user content to send.
    .PARAMETER Provider
        A TranslationProvider instance describing which provider/model/endpoint to
        call. Note: callers may pass a provider object distinct from the session's
        configured provider (e.g. Invoke-TranslationPriming builds its own copy
        with a different temperature for content analysis) - this function only
        cares about its .Name.
    .PARAMETER ApiKey
        The decrypted API key as a SecureString.
    .PARAMETER MaxRetries
        Forwarded to the underlying adapter's retry loop.
    .OUTPUTS
        PSCustomObject: Content, InputTokens, OutputTokens, FinishReason, Model, RetryCount
    #>
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string] $SystemPrompt,

        [Parameter(Mandatory)]
        [string] $UserContent,

        [Parameter(Mandatory)]
        [TranslationProvider] $Provider,

        [Parameter(Mandatory)]
        [SecureString] $ApiKey,

        [int] $MaxRetries = 3
    )

    switch ($Provider.Name) {
        'Anthropic' {
            return Invoke-AnthropicTranslation -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Provider $Provider -ApiKey $ApiKey -MaxRetries $MaxRetries
        }
        'OpenAI' {
            return Invoke-OpenAITranslation -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Provider $Provider -ApiKey $ApiKey -MaxRetries $MaxRetries
        }
        'Google' {
            return Invoke-GoogleTranslation -SystemPrompt $SystemPrompt -UserContent $UserContent `
                -Provider $Provider -ApiKey $ApiKey -MaxRetries $MaxRetries
        }
        default {
            throw "Invoke-TranslationProviderAdapter: unknown translation provider '$($Provider.Name)'. Supported providers: Anthropic, OpenAI, Google."
        }
    }
}
