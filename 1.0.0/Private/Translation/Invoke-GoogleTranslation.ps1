function Invoke-GoogleTranslation {
    <#
    .SYNOPSIS
        Calls the Google Gemini generateContent API with retry and exponential backoff.
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
            temperature = [double]$Provider.Temperature
        }
    } | ConvertTo-Json -Depth 8

    $uri = '{0}/models/{1}:generateContent?key={2}' -f $Provider.BaseUrl, $Provider.Model, $plainKey

    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        try {
            $response = Invoke-RestMethod -Uri $uri -Method Post `
                -ContentType 'application/json' -Body $body -ErrorAction Stop

            $text    = $response.candidates[0].content.parts[0].text
            $inTok   = $response.usageMetadata.promptTokenCount
            $outTok  = $response.usageMetadata.candidatesTokenCount
            $finish  = $response.candidates[0].finishReason

            return [PSCustomObject]@{
                Content      = $text
                InputTokens  = $inTok
                OutputTokens = $outTok
                FinishReason = $finish.ToLower()
                Model        = $Provider.Model
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
            Write-Warning "Google API call failed (attempt $attempt/$MaxRetries). Retrying in ${delay}s..."
            Start-Sleep -Seconds $delay
        }
    }
}
