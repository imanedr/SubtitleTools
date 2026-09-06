class TranslationProvider {
    [string]   $Name               # 'OpenAI' | 'Anthropic' | 'Google'
    [string]   $Model
    [string]   $ApiKeyEncrypted    # DPAPI-encrypted base64 API key (CurrentUser scope)
    [string]   $BaseUrl            # Allows custom/proxy endpoints
    [int]      $MaxTokensPerBatch  # Client-side input batching heuristic (chars-per-token budget for packing entries into one call)
    [int]      $MaxOutputTokens    # API output-token cap sent to the provider (e.g. Anthropic max_tokens) - distinct from MaxTokensPerBatch
    [int]      $RateLimitRpm       # Requests per minute (0 = unlimited)
    [decimal]  $Temperature
    [string[]] $SupportedLanguages # Empty means all languages supported

    TranslationProvider() {
        $this.Temperature        = 0.3
        $this.MaxTokensPerBatch  = 4000
        $this.MaxOutputTokens    = 8192
        $this.RateLimitRpm       = 60
        $this.SupportedLanguages = @()
    }

    [string] ToString() {
        return '[TranslationProvider] {0} Model={1}' -f $this.Name, $this.Model
    }
}
