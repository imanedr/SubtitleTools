function Invoke-TranslationPriming {
    <#
    .SYNOPSIS
        Analyzes a subtitle file sample and returns structured content context for translation.
    .DESCRIPTION
        Sends a representative sample of entries to the AI provider and asks it to analyze
        the content: type, tone, register, domain terminology, speaker patterns, and cultural
        notes. The result is stored in Session.ContentContext and used by
        Build-TranslationSystemPrompt to produce a richer, content-aware system prompt.

        This runs once per session — subsequent calls reuse Session.ContentContext.
    .OUTPUTS
        PSCustomObject with labeled fields from the AI analysis.
    #>
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [SubtitleFile] $InputObject,

        [Parameter(Mandatory)]
        [hashtable] $Session,

        [Parameter(Mandatory)]
        [SecureString] $ApiKey,

        [string] $SourceLanguage = '',

        [string] $TargetLanguage = '',

        [int] $SampleSize = 20
    )

    # Collect evenly-spaced sample entries
    $entries     = $InputObject.Entries
    $total       = $entries.Count
    $effectiveN  = [Math]::Min($SampleSize, $total)
    $step        = if ($total -le $effectiveN) { 1 } else { [int]($total / $effectiveN) }

    $sampleLines = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $total -and $sampleLines.Count -lt $effectiveN; $i += $step) {
        $text = $entries[$i].Lines -join ' '
        if ($text.Trim()) {
            $sampleLines.Add("[$($i + 1)] $text")
        }
    }

    $srcLabel = if ($SourceLanguage) { $SourceLanguage } else { 'auto-detect' }
    $tgtLabel = if ($TargetLanguage) { $TargetLanguage } else { 'unknown'      }

    $systemPrompt = @"
You are a professional subtitle analyst. Analyze the subtitle sample below and return ONLY the labeled fields — no prose, no preamble.

Source language: $srcLabel
Target language: $tgtLabel

Required output (one per line, exactly as shown):
CONTENT_TYPE: <film|series|documentary|animation|news|sports|educational|other>
CONTENT_TITLE: <title if inferable, else UNKNOWN>
DOMINANT_TONE: <dramatic|comedic|action|romantic|neutral|tense|documentary|mixed>
REGISTER: <formal|informal|colloquial|technical|mixed>
TARGET_AUDIENCE: <general|children|adult|professional|academic>
PACING: <fast|moderate|slow> (how quickly dialogue moves)
DOMAIN_TERMS: <comma-separated list of domain-specific or recurring terms to translate consistently, or NONE>
SPEAKER_PATTERNS: <description of how many speakers, any named characters, group vs solo dialogue>
CULTURAL_NOTES: <idioms, references, humor that need localization care, or NONE>
TRANSLATION_WARNINGS: <any structural challenges (e.g., wordplay, acrostics, number puns), or NONE>
"@

    $userContent = "Subtitle sample ($($sampleLines.Count) entries):`n`n" + ($sampleLines -join "`n")

    $provider = $Session.Provider

    Write-Verbose "Running translation priming analysis ($($sampleLines.Count) sample entries)..."

    # Use higher temperature for creative analysis
    $analysisProv          = [TranslationProvider]::new()
    $analysisProv.Name     = $provider.Name
    $analysisProv.Model    = $provider.Model
    $analysisProv.BaseUrl  = $provider.BaseUrl
    $analysisProv.MaxTokensPerBatch = $provider.MaxTokensPerBatch
    $analysisProv.RateLimitRpm      = $provider.RateLimitRpm
    $analysisProv.Temperature       = 0.7

    $adapterResult = switch ($provider.Name) {
        'Anthropic' { Invoke-AnthropicTranslation -SystemPrompt $systemPrompt -UserContent $userContent -Provider $analysisProv -ApiKey $ApiKey }
        'OpenAI'    { Invoke-OpenAITranslation    -SystemPrompt $systemPrompt -UserContent $userContent -Provider $analysisProv -ApiKey $ApiKey }
        'Google'    { Invoke-GoogleTranslation    -SystemPrompt $systemPrompt -UserContent $userContent -Provider $analysisProv -ApiKey $ApiKey }
    }

    if ($adapterResult.FinishReason -eq 'error') {
        Write-Warning "Translation priming failed: $($adapterResult.Content). Proceeding without content context."
        return $null
    }

    # Parse labeled lines into a hashtable
    $ctx = @{}
    foreach ($line in ($adapterResult.Content -split "`n")) {
        if ($line -match '^([A-Z_]+):\s*(.+)$') {
            $ctx[$Matches[1]] = $Matches[2].Trim()
        }
    }

    $result = [PSCustomObject]@{
        ContentType          = $ctx['CONTENT_TYPE']          ?? 'unknown'
        ContentTitle         = $ctx['CONTENT_TITLE']         ?? 'UNKNOWN'
        DominantTone         = $ctx['DOMINANT_TONE']         ?? 'neutral'
        Register             = $ctx['REGISTER']              ?? 'mixed'
        TargetAudience       = $ctx['TARGET_AUDIENCE']       ?? 'general'
        Pacing               = $ctx['PACING']                ?? 'moderate'
        DomainTerms          = $ctx['DOMAIN_TERMS']          ?? 'NONE'
        SpeakerPatterns      = $ctx['SPEAKER_PATTERNS']      ?? ''
        CulturalNotes        = $ctx['CULTURAL_NOTES']        ?? 'NONE'
        TranslationWarnings  = $ctx['TRANSLATION_WARNINGS']  ?? 'NONE'
        RawAnalysis          = $adapterResult.Content
    }

    Write-Verbose "Priming complete. Content: $($result.ContentType) / Tone: $($result.DominantTone) / Register: $($result.Register)"

    return $result
}
