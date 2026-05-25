class TranslationProvider {
    [string]   $Name               # 'OpenAI' | 'Anthropic' | 'Google'
    [string]   $Model
    [string]   $ApiKeyEncrypted    # DPAPI-encrypted base64 API key (CurrentUser scope)
    [string]   $BaseUrl            # Allows custom/proxy endpoints
    [int]      $MaxTokensPerBatch
    [int]      $RateLimitRpm       # Requests per minute (0 = unlimited)
    [decimal]  $Temperature
    [string[]] $SupportedLanguages # Empty means all languages supported

    TranslationProvider() {
        $this.Temperature        = 0.3
        $this.MaxTokensPerBatch  = 4000
        $this.RateLimitRpm       = 60
        $this.SupportedLanguages = @()
    }

    [string] ToString() {
        return '[TranslationProvider] {0} Model={1}' -f $this.Name, $this.Model
    }
}
