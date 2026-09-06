function Invoke-OpenAITranslation {
    <#
    .SYNOPSIS
        Calls the OpenAI Chat Completions API with retry and exponential backoff.
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
        model       = $Provider.Model
        temperature = [double]$Provider.Temperature
        messages    = @(
            @{ role = 'system'; content = $SystemPrompt }
            @{ role = 'user';   content = $UserContent  }
        )
    } | ConvertTo-Json -Depth 5

    $headers = @{
        'Authorization' = "Bearer $plainKey"
        'Content-Type'  = 'application/json'
    }

    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        try {
            $response = Invoke-RestMethod -Uri "$($Provider.BaseUrl)/chat/completions" `
                -Method Post -Headers $headers -Body $body -ErrorAction Stop

            $choice = $response.choices[0]
            return [PSCustomObject]@{
                Content      = $choice.message.content
                InputTokens  = $response.usage.prompt_tokens
                OutputTokens = $response.usage.completion_tokens
                FinishReason = $choice.finish_reason
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
            Write-Warning "OpenAI API call failed (attempt $attempt/$MaxRetries). Retrying in ${delay}s..."
            Start-Sleep -Seconds $delay
        }
    }
}
