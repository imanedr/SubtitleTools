function Build-TranslationSystemPrompt {
    <#
    .SYNOPSIS
        Builds a rich, content-aware system prompt for subtitle translation.
    .DESCRIPTION
        Assembles a structured ~350-token system prompt in 9 sections:
          1. Role
          2. Content context (from priming, if available)
          3. Technical constraints (line width, reading speed, entry count)
          4. Speaker and dialogue handling
          5. Special elements (HTML tags, ASS overrides, numbers)
          6. Domain terminology consistency
          7. Glossary enforcement
          8. Output format contract
          9. Final instruction

        If ContentContext is null, produces a solid general-purpose prompt.
        If SystemPromptPath points to a valid file, loads that file instead
        and substitutes {{BATCH_SIZE}}, {{SOURCE}}, {{TARGET}} placeholders.
    .OUTPUTS
        [string] — the assembled system prompt
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [int] $BatchSize,

        [string] $SourceLanguage = '',

        [Parameter(Mandatory)]
        [string] $TargetLanguage,

        [PSCustomObject] $ContentContext,

        [hashtable] $Glossary = @{},

        [int] $MaxCharsPerLine   = 42,
        [int] $MaxLinesPerEntry  = 2,
        [int] $ReadingSpeedCps   = 17,

        [string] $SystemPromptPath = ''
    )

    # --- Custom prompt file override ---
    if ($SystemPromptPath -and (Test-Path $SystemPromptPath)) {
        $raw = Get-Content $SystemPromptPath -Raw
        $raw = $raw -replace '\{\{BATCH_SIZE\}\}', $BatchSize
        $raw = $raw -replace '\{\{SOURCE\}\}',     $(if ($SourceLanguage) { $SourceLanguage } else { 'auto-detect' })
        $raw = $raw -replace '\{\{TARGET\}\}',     $TargetLanguage
        return $raw.TrimEnd()
    }

    $src = if ($SourceLanguage) { $SourceLanguage } else { 'auto-detect' }

    $sb = [System.Text.StringBuilder]::new(1024)

    # --- 1. Role ---
    $null = $sb.AppendLine("You are an expert subtitle translator and localization specialist.")
    $null = $sb.AppendLine("Translate exactly $BatchSize subtitle entries from $src to $TargetLanguage.")
    $null = $sb.AppendLine()

    # --- 2. Content context ---
    if ($ContentContext) {
        $null = $sb.AppendLine('## Content Context')
        $null = $sb.AppendLine("Type    : $($ContentContext.ContentType)")
        if ($ContentContext.ContentTitle -and $ContentContext.ContentTitle -ne 'UNKNOWN') {
            $null = $sb.AppendLine("Title   : $($ContentContext.ContentTitle)")
        }
        $null = $sb.AppendLine("Tone    : $($ContentContext.DominantTone)")
        $null = $sb.AppendLine("Register: $($ContentContext.Register)")
        $null = $sb.AppendLine("Audience: $($ContentContext.TargetAudience)")
        $null = $sb.AppendLine("Pacing  : $($ContentContext.Pacing)")
        if ($ContentContext.SpeakerPatterns) {
            $null = $sb.AppendLine("Speakers: $($ContentContext.SpeakerPatterns)")
        }
        if ($ContentContext.CulturalNotes -and $ContentContext.CulturalNotes -ne 'NONE') {
            $null = $sb.AppendLine("Cultural: $($ContentContext.CulturalNotes)")
        }
        if ($ContentContext.TranslationWarnings -and $ContentContext.TranslationWarnings -ne 'NONE') {
            $null = $sb.AppendLine("Warnings: $($ContentContext.TranslationWarnings)")
        }
        $null = $sb.AppendLine()
    }

    # --- 3. Technical constraints ---
    $null = $sb.AppendLine('## Technical Constraints')
    $null = $sb.AppendLine("- Max $MaxCharsPerLine characters per subtitle line")
    $null = $sb.AppendLine("- Max $MaxLinesPerEntry lines per entry")
    $null = $sb.AppendLine("- Target reading speed: ~$ReadingSpeedCps characters/second (match entry duration)")
    $null = $sb.AppendLine("- Preserve timing rhythm — short entries must stay concise, fast entries can compress")
    $null = $sb.AppendLine()

    # --- 4. Speaker and dialogue handling ---
    $null = $sb.AppendLine('## Dialogue Handling')
    $null = $sb.AppendLine('- Keep each speaker turn as its own entry — never merge separate speakers')
    $null = $sb.AppendLine('- Preserve interruptions, trailing dashes (–), and ellipses (…) as continuity cues')
    $null = $sb.AppendLine('- Retain character names, honorifics, and forms of address exactly as established')
    $null = $sb.AppendLine('- Match the register of the original: casual dialogue must stay casual, formal must stay formal')
    $null = $sb.AppendLine('- Use equivalent target-language slang or colloquialisms when a direct translation would sound unnatural')
    if ($ContentContext -and $ContentContext.DominantTone -in @('comedic', 'action', 'dramatic')) {
        $null = $sb.AppendLine("- Maintain the $($ContentContext.DominantTone) register — do not flatten emotional peaks")
    }
    $null = $sb.AppendLine()

    # --- 4b. Cross-block sentences ---
    $null = $sb.AppendLine('## Cross-Block Sentences')
    $null = $sb.AppendLine('- When a sentence spans multiple consecutive entries, translate the complete sentence first,')
    $null = $sb.AppendLine('  then redistribute the translated text across those same entries')
    $null = $sb.AppendLine('- Mirror the original split point when redistributing — if the source broke mid-clause, break')
    $null = $sb.AppendLine('  at the equivalent conceptual point in the translation, as long as it sounds natural')
    $null = $sb.AppendLine('- Process entries strictly in order — do not skip, summarize, or reorder any block')
    $null = $sb.AppendLine()

    # --- 5. Special elements ---
    $null = $sb.AppendLine('## Special Elements — Preserve Exactly')
    $null = $sb.AppendLine('- HTML tags: <i>, <b>, <u>, <font color="...">, </i> etc. — copy verbatim, do not translate')
    $null = $sb.AppendLine('- ASS override tags: {\an8}, {\pos(x,y)}, {\fad(...)}, {\c&H...&} etc. — copy verbatim')
    $null = $sb.AppendLine('- Numbers, timestamps, codes, URLs, brand names — copy verbatim unless localization is standard')
    $null = $sb.AppendLine('- Line breaks within an entry are encoded as <NL> — preserve position when natural in target language')
    $null = $sb.AppendLine()

    # --- 6. Domain terminology ---
    if ($ContentContext -and $ContentContext.DomainTerms -and $ContentContext.DomainTerms -ne 'NONE') {
        $null = $sb.AppendLine('## Domain Terminology')
        $null = $sb.AppendLine("Translate these recurring terms consistently throughout: $($ContentContext.DomainTerms)")
        $null = $sb.AppendLine()
    }

    # --- 7. Glossary ---
    if ($Glossary -and $Glossary.Count -gt 0) {
        $null = $sb.AppendLine('## Mandatory Glossary (enforce exactly — do not paraphrase)')
        foreach ($term in ($Glossary.Keys | Sort-Object)) {
            $null = $sb.AppendLine("  $term → $($Glossary[$term])")
        }
        $null = $sb.AppendLine()
    }

    # --- 8. Output format contract ---
    $null = $sb.AppendLine('## Output Format — Strict Contract')
    $null = $sb.AppendLine("- Return EXACTLY $BatchSize translations, one per line")
    $null = $sb.AppendLine('- Each line MUST begin with the entry number followed by a pipe: 1|translation text')
    $null = $sb.AppendLine('- Example output: 1|First line<NL>second line')
    $null = $sb.AppendLine('                  2|Single line entry')
    $null = $sb.AppendLine('- Preserve line breaks within each entry using <NL>')
    $null = $sb.AppendLine('- No extra labels, explanations, or blank lines between entries')
    $null = $sb.AppendLine('- If an entry has no translatable text (e.g., sound effects in brackets), copy it verbatim')
    $null = $sb.AppendLine('- If a term cannot be translated, transliterate it phonetically')
    $null = $sb.AppendLine()

    # --- 9. Final instruction ---
    $null = $sb.AppendLine('Translate now. Source entries follow, one per line in the format N|text:')

    return $sb.ToString().TrimEnd()
}
