function Invoke-AnthropicTranslation {
    <#
    .SYNOPSIS
        Calls the Anthropic Messages API with retry and exponential backoff.
    .OUTPUTS
        PSCustomObject: Content, InputTokens, OutputTokens, FinishReason, Model
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
        model      = $Provider.Model
        max_tokens = $Provider.MaxOutputTokens
        system     = $SystemPrompt
        messages   = @(
            @{ role = 'user'; content = $UserContent }
        )
        temperature = [double]$Provider.Temperature
    } | ConvertTo-Json -Depth 5

    $headers = @{
        'x-api-key'         = $plainKey
        'anthropic-version' = '2023-06-01'
        'content-type'      = 'application/json'
    }

    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        try {
            $response = Invoke-RestMethod -Uri "$($Provider.BaseUrl)/messages" `
                -Method Post -Headers $headers -Body $body -ErrorAction Stop

            return [PSCustomObject]@{
                Content      = $response.content[0].text
                InputTokens  = $response.usage.input_tokens
                OutputTokens = $response.usage.output_tokens
                FinishReason = $response.stop_reason
                Model        = $response.model
            }
        } catch {
            $attempt++
            if ($attempt -ge $MaxRetries) {
                return [PSCustomObject]@{
                    Content      = $_.Exception.Message
                    InputTokens  = 0
                    OutputTokens = 0
                    FinishReason = 'error'
                    Model        = $Provider.Model
                }
            }
            $delay = [Math]::Pow(2, $attempt)
            Write-Warning "Anthropic API call failed (attempt $attempt/$MaxRetries). Retrying in ${delay}s..."
            Start-Sleep -Seconds $delay
        }
    }
}
