function Invoke-OpenRouterTranslation {
    <#
    .SYNOPSIS
        Calls the OpenRouter Chat Completions API with retry and exponential backoff.
    .DESCRIPTION
        OpenRouter's chat endpoint is OpenAI-Chat-Completions-compatible, so the
        request/response shape mirrors Invoke-OpenAITranslation. Additionally sends
        OpenRouter's optional attribution headers (HTTP-Referer, X-Title) so usage
        shows up correctly attributed on https://openrouter.ai.
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

    $plainKey = [System.Net.NetworkCredential]::new('', $ApiKey).Password

    $body = @{
        model       = $Provider.Model
        temperature = [double]$Provider.Temperature
        max_tokens  = $Provider.MaxOutputTokens
        messages    = @(
            @{ role = 'system'; content = $SystemPrompt }
            @{ role = 'user';   content = $UserContent  }
        )
    }

    $headers = @{
        'Authorization' = "Bearer $plainKey"
        'HTTP-Referer'  = 'https://github.com/imanedr/SubtitleTools'
        'X-Title'       = 'SubtitleTools'
    }

    $result = Invoke-TranslationApiRequest -Uri "$($Provider.BaseUrl)/chat/completions" -Method Post `
        -Body $body -Headers $headers -ProviderLabel 'OpenRouter' -MaxRetries $MaxRetries -JsonDepth 5

    if (-not $result.Success) {
        return [PSCustomObject]@{
            Content      = $result.ErrorMessage
            InputTokens  = 0
            OutputTokens = 0
            FinishReason = 'error'
            Model        = $Provider.Model
            RetryCount   = $result.RetryCount
        }
    }

    $response = $result.Response
    $choice   = $response.choices[0]

    return [PSCustomObject]@{
        Content      = $choice.message.content
        InputTokens  = $response.usage.prompt_tokens
        OutputTokens = $response.usage.completion_tokens
        FinishReason = $choice.finish_reason
        Model        = $response.model
        RetryCount   = $result.RetryCount
    }
}
