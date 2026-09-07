function Invoke-GoogleTranslation {
    <#
    .SYNOPSIS
        Calls the Google Gemini generateContent API with retry and exponential backoff.
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
        systemInstruction = @{
            parts = @(@{ text = $SystemPrompt })
        }
        contents          = @(
            @{
                role  = 'user'
                parts = @(@{ text = $UserContent })
            }
        )
        generationConfig  = @{
            temperature     = [double]$Provider.Temperature
            maxOutputTokens = $Provider.MaxOutputTokens
        }
    }

    # Auth via header, not '?key=' query string - a plaintext key in the URI can
    # leak into exception messages, verbose transcripts, and captured error bodies.
    $headers = @{
        'x-goog-api-key' = $plainKey
    }

    $uri = '{0}/models/{1}:generateContent' -f $Provider.BaseUrl, $Provider.Model

    if ($StreamCallback) {
        # Gemini streams from a different method name entirely, and needs alt=sse to
        # emit server-sent events rather than a JSON array.
        $streamUri = '{0}/models/{1}:streamGenerateContent?alt=sse' -f $Provider.BaseUrl, $Provider.Model
        $streamed  = Invoke-TranslationStreamAttempt -Uri $streamUri -Headers $headers -Body $body `
            -Shape 'Google' -ProviderLabel 'Google' -Model $Provider.Model `
            -StreamCallback $StreamCallback -JsonDepth 8
        if ($streamed) { return $streamed }
    }

    $result = Invoke-TranslationApiRequest -Uri $uri -Method Post `
        -Body $body -Headers $headers -ProviderLabel 'Google' -MaxRetries $MaxRetries -JsonDepth 8

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

    # A safety-filtered prompt yields a 200 OK with NO candidates at all (the block
    # reason lives in promptFeedback.blockReason instead). Calling .ToLower() on the
    # missing finishReason previously threw *inside* the try, so the generic catch
    # swallowed it as a retryable failure and eventually returned a raw .NET
    # exception string as if it were translated text. Surface it as a clear,
    # non-retryable error instead.
    if (-not $response.candidates -or $response.candidates.Count -eq 0) {
        $blockReason = $response.promptFeedback.blockReason
        $reasonText  = if ($blockReason) { $blockReason } else { 'unknown reason' }

        return [PSCustomObject]@{
            Content      = "Google Gemini blocked the request (no candidates returned): $reasonText"
            InputTokens  = $response.usageMetadata.promptTokenCount
            OutputTokens = 0
            FinishReason = 'error'
            Model        = $Provider.Model
            RetryCount   = $result.RetryCount
        }
    }

    $candidate = $response.candidates[0]
    $text      = $candidate.content.parts[0].text
    $inTok     = $response.usageMetadata.promptTokenCount
    $outTok    = $response.usageMetadata.candidatesTokenCount
    $finish    = $candidate.finishReason

    # Defensive: finishReason can still be null/absent even when candidates exist.
    $finishLower = if ($finish) { $finish.ToLower() } else { 'unknown' }

    return [PSCustomObject]@{
        Content      = $text
        InputTokens  = $inTok
        OutputTokens = $outTok
        FinishReason = $finishLower
        Model        = $Provider.Model
        RetryCount   = $result.RetryCount
    }
}
