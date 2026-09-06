function Invoke-AnthropicTranslation {
    <#
    .SYNOPSIS
        Calls the Anthropic Messages API with retry and exponential backoff.
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
        max_tokens  = $Provider.MaxOutputTokens
        system      = $SystemPrompt
        messages    = @(
            @{ role = 'user'; content = $UserContent }
        )
        temperature = [double]$Provider.Temperature
    }

    $headers = @{
        'x-api-key'         = $plainKey
        'anthropic-version' = '2023-06-01'
    }

    $result = Invoke-TranslationApiRequest -Uri "$($Provider.BaseUrl)/messages" -Method Post `
        -Body $body -Headers $headers -ProviderLabel 'Anthropic' -MaxRetries $MaxRetries -JsonDepth 5

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

    # The content array can contain non-text blocks (e.g. 'thinking') - select the
    # first block that actually is text rather than assuming index 0.
    $textBlock = $null
    foreach ($block in $response.content) {
        if ($block.type -eq 'text') {
            $textBlock = $block
            break
        }
    }

    if (-not $textBlock) {
        return [PSCustomObject]@{
            Content      = 'Anthropic response contained no text content block.'
            InputTokens  = $response.usage.input_tokens
            OutputTokens = $response.usage.output_tokens
            FinishReason = 'error'
            Model        = $response.model
            RetryCount   = $result.RetryCount
        }
    }

    return [PSCustomObject]@{
        Content      = $textBlock.text
        InputTokens  = $response.usage.input_tokens
        OutputTokens = $response.usage.output_tokens
        FinishReason = $response.stop_reason
        Model        = $response.model
        RetryCount   = $result.RetryCount
    }
}
