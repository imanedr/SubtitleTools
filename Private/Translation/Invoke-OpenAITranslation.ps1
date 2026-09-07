function Invoke-OpenAITranslation {
    <#
    .SYNOPSIS
        Calls the OpenAI Chat Completions API with retry and exponential backoff.
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

        [int] $MaxRetries = 3,

        # When supplied, the call is attempted over the streaming path first so the
        # caller can report progress while the model is still writing; any streaming
        # failure falls back to the buffered request below.
        [scriptblock] $StreamCallback
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
    }

    if ($StreamCallback) {
        $streamed = Invoke-TranslationStreamAttempt -Uri "$($Provider.BaseUrl)/chat/completions" -Headers $headers -Body $body `
            -Shape 'OpenAI' -ProviderLabel 'OpenAI' -Model $Provider.Model `
            -StreamCallback $StreamCallback -JsonDepth 5
        if ($streamed) { return $streamed }
    }

    $result = Invoke-TranslationApiRequest -Uri "$($Provider.BaseUrl)/chat/completions" -Method Post `
        -Body $body -Headers $headers -ProviderLabel 'OpenAI' -MaxRetries $MaxRetries -JsonDepth 5

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
