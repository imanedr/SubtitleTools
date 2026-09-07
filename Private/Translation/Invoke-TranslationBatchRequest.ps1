function Test-TranslationTruncated {
    <#
    .SYNOPSIS
        Tells whether a provider stopped generating because it hit the output cap.
    .DESCRIPTION
        Each provider spells the same condition differently:
          OpenAI / OpenRouter : finish_reason = 'length'
          Anthropic           : stop_reason   = 'max_tokens'
          Google Gemini       : finishReason  = 'MAX_TOKENS'
        A truncated response is NOT an API error - it is a 200 OK carrying a partial
        answer - so it has to be detected explicitly or the missing tail is silently
        mistaken for "the model chose not to translate these".
    .OUTPUTS
        [bool]
    #>
    [OutputType([bool])]
    param(
        [AllowNull()]
        [string] $FinishReason
    )

    if (-not $FinishReason) { return $false }

    return @('length', 'max_tokens', 'max_output_tokens', 'maxtokens') -contains $FinishReason.ToLower()
}

function Invoke-TranslationBatchRequest {
    <#
    .SYNOPSIS
        Translates one batch of subtitle texts, splitting and retrying any entries the
        model failed to return.
    .DESCRIPTION
        Sends $Texts as a numbered "1|text" block, parses the numbered response back,
        and - this is the point of the function - recovers the entries that did not
        come back instead of accepting a hole.

        Two failure modes produce holes, and both are common enough to design around:

        1. Output truncation. The model hits its output-token cap partway through and
           the response simply stops. On a reasoning model the thinking tokens are
           billed against that same cap, so a budget that looks generous for the visible
           answer can be exhausted before the answer even starts. The provider reports
           this via finish_reason/stop_reason (see Test-TranslationTruncated), but a
           truncated response is a 200 OK, so nothing throws.
        2. Numbering drift. On a long numbered list a model can skip, duplicate, or
           renumber lines, leaving specific indices unmatched.

        In both cases the fix is the same and is cheap: re-ask for only the entries that
        are still missing, in two halves, recursively. Halving guarantees termination
        (each level strictly shrinks) and converges fast - a batch truncated at 25%
        resolves within two levels. Falling back to untranslated source text is the last
        resort, only after -MaxSplitDepth levels have failed, and the caller is told how
        many entries that happened to.
    .PARAMETER Texts
        Source texts for this batch, in order.
    .PARAMETER Provider
        The TranslationProvider to call.
    .PARAMETER ApiKey
        Decrypted API key.
    .PARAMETER SourceLanguage
        BCP-47 source code, or '' to let the provider auto-detect.
    .PARAMETER TargetLanguage
        BCP-47 target code.
    .PARAMETER Glossary
        Glossary hashtable injected into the system prompt.
    .PARAMETER ContentContext
        Priming context object, or $null.
    .PARAMETER SystemPromptPath
        Optional custom system prompt template.
    .PARAMETER MaxSplitDepth
        How many levels of halving to attempt before giving up on the stragglers.
        Default 3, i.e. up to a 1/8-size retry.
    .PARAMETER Depth
        Internal recursion depth. Callers leave this at 0.
    .PARAMETER OnProgress
        Optional scriptblock invoked with a single status string whenever a retry
        round starts, so a long self-healing batch does not look frozen.
    .OUTPUTS
        Hashtable: Translations (string[]; an entry never resolved is left empty -
        note that PowerShell coerces $null to '' on assignment into a [string[]],
        so "unresolved" is tested with [string]::IsNullOrEmpty, never -eq $null),
        InputTokens, OutputTokens, RetryCount, ApiCalls, Truncated, Unresolved
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Texts,

        [Parameter(Mandatory)]
        [TranslationProvider] $Provider,

        [Parameter(Mandatory)]
        [SecureString] $ApiKey,

        [string] $SourceLanguage = '',

        [Parameter(Mandatory)]
        [string] $TargetLanguage,

        [hashtable] $Glossary = @{},

        [PSCustomObject] $ContentContext,

        [string] $SystemPromptPath = '',

        [int] $MaxSplitDepth = 3,

        [int] $Depth = 0,

        [scriptblock] $OnProgress
    )

    $n = $Texts.Count

    $result = @{
        Translations = New-Object 'string[]' $n
        InputTokens  = 0
        OutputTokens = 0
        RetryCount   = 0
        ApiCalls     = 0
        Truncated    = $false
        Unresolved   = 0
    }

    if ($n -eq 0) { return $result }

    $systemPrompt = Build-TranslationSystemPrompt `
        -BatchSize        $n `
        -SourceLanguage   $SourceLanguage `
        -TargetLanguage   $TargetLanguage `
        -ContentContext   $ContentContext `
        -Glossary         $Glossary `
        -SystemPromptPath $SystemPromptPath

    # Numbered format: "1|text\n2|text\n..." - split on the first pipe only, so
    # translated text is free to contain pipes.
    $userContent = (0..($n - 1) | ForEach-Object { "$($_ + 1)|$($Texts[$_])" }) -join "`n"

    $adapterResult = Invoke-TranslationProviderAdapter `
        -SystemPrompt $systemPrompt -UserContent $userContent `
        -Provider $Provider -ApiKey $ApiKey

    $result.ApiCalls     = 1
    $result.InputTokens  = [int]$adapterResult.InputTokens
    $result.OutputTokens = [int]$adapterResult.OutputTokens
    $result.RetryCount   = [int]$adapterResult.RetryCount

    if ($adapterResult.FinishReason -eq 'error') {
        throw "API call failed: $($adapterResult.Content)"
    }

    $wasTruncated     = Test-TranslationTruncated -FinishReason $adapterResult.FinishReason
    $result.Truncated = $wasTruncated

    foreach ($line in ($adapterResult.Content -split '\r?\n')) {
        if ($line -match '^\s*(\d+)\s*\|(.*)$') {
            $num  = [int]$Matches[1]
            $text = $Matches[2].Trim()
            # An in-range number with empty text is a dropped entry, not a translation -
            # leave the slot null so the retry pass picks it up.
            if ($num -ge 1 -and $num -le $n -and $text) {
                $result.Translations[$num - 1] = $text
            }
        }
    }

    # A truncated response's LAST parsed line is itself suspect: generation stopped
    # mid-token, so that line can be a half-written sentence. Discard it and let the
    # retry produce it properly.
    if ($wasTruncated) {
        for ($i = $n - 1; $i -ge 0; $i--) {
            if (-not [string]::IsNullOrEmpty($result.Translations[$i])) {
                $result.Translations[$i] = $null
                break
            }
        }
    }

    $missing = @(0..($n - 1) | Where-Object { [string]::IsNullOrEmpty($result.Translations[$_]) })

    if ($missing.Count -eq 0) { return $result }

    if ($Depth -ge $MaxSplitDepth -or $n -eq 1) {
        $result.Unresolved = $missing.Count
        return $result
    }

    $reason = if ($wasTruncated) {
        "response truncated at the provider's output-token cap"
    } else {
        'entries missing from the response'
    }
    $status = "Recovering $($missing.Count) of $n entries ($reason) - retrying in smaller batches..."
    Write-Verbose "Invoke-TranslationBatchRequest (depth $Depth): $status"
    if ($OnProgress) { & $OnProgress $status }

    # Re-ask for only the missing entries, halved. Each half is strictly smaller than
    # $missing, and $missing is at most $n, so the recursion always terminates.
    $half   = [Math]::Max(1, [int][Math]::Ceiling($missing.Count / 2))
    $chunks = @()
    for ($i = 0; $i -lt $missing.Count; $i += $half) {
        $chunks += , @($missing[$i..([Math]::Min($i + $half - 1, $missing.Count - 1))])
    }

    foreach ($chunk in $chunks) {
        $subTexts = @($chunk | ForEach-Object { $Texts[$_] })

        $sub = Invoke-TranslationBatchRequest `
            -Texts            $subTexts `
            -Provider         $Provider `
            -ApiKey           $ApiKey `
            -SourceLanguage   $SourceLanguage `
            -TargetLanguage   $TargetLanguage `
            -Glossary         $Glossary `
            -ContentContext   $ContentContext `
            -SystemPromptPath $SystemPromptPath `
            -MaxSplitDepth    $MaxSplitDepth `
            -Depth            ($Depth + 1) `
            -OnProgress       $OnProgress

        for ($j = 0; $j -lt $chunk.Count; $j++) {
            $result.Translations[$chunk[$j]] = $sub.Translations[$j]
        }

        $result.InputTokens  += $sub.InputTokens
        $result.OutputTokens += $sub.OutputTokens
        $result.RetryCount   += $sub.RetryCount
        $result.ApiCalls     += $sub.ApiCalls
        if ($sub.Truncated) { $result.Truncated = $true }
    }

    $result.Unresolved = @(0..($n - 1) | Where-Object { [string]::IsNullOrEmpty($result.Translations[$_]) }).Count

    return $result
}
