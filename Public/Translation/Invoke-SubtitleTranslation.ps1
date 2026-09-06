function Invoke-SubtitleTranslation {
    <#
    .SYNOPSIS
        Translates a subtitle file using an AI provider API.
    .DESCRIPTION
        Supports OpenAI (GPT-4o), Anthropic (Claude), Google (Gemini), and OpenRouter
        (a unified gateway to many hosted models).
        Batches entries to respect token limits. Caches results by content hash.
        ASS override tags are stripped before translation and reinserted after.

        When -PrimeWithContext is specified (or when a Session without ContentContext
        is used), the function first sends a sample of entries to the AI for content
        analysis (type, tone, register, domain terms, speaker patterns). This context
        is then used to build a rich, content-aware system prompt for every subsequent
        batch. Priming runs once per session â€” reuse the same session across episodes
        of a series to avoid repeated API calls.

        API keys are stored encrypted at rest via Windows DPAPI (CurrentUser scope) -
        no SecretManagement vault or external module is required. Configure a
        provider first:
        Set-TranslationProvider -Name Anthropic -Model 'claude-sonnet-4-6' -ApiKeyPlainText 'sk-ant-...'

    .PARAMETER InputObject
        A SubtitleFile object to translate.
    .PARAMETER Path
        Path to a subtitle file to load and translate.
    .PARAMETER ProviderName
        The AI provider to use: OpenAI, Anthropic, Google, or OpenRouter.
    .PARAMETER SourceLanguage
        BCP-47 language code of the source (e.g., 'en'). Optional â€” providers can auto-detect.
    .PARAMETER TargetLanguage
        BCP-47 language code of the target language (e.g., 'fa', 'fr', 'zh').
    .PARAMETER Session
        A session object from New-TranslationSession (includes glossary, cache, and ContentContext).
    .PARAMETER GlossaryPath
        Path to a JSON glossary file { "source": "target" }. Injected into the system prompt.
    .PARAMETER ResumeFrom
        Path to a checkpoint file to resume an interrupted batch translation.
    .PARAMETER OutputPath
        If specified, saves the translated file to this path.
    .PARAMETER LogPath
        Path to a log file for operation results.
    .PARAMETER PrimeWithContext
        Run a content analysis pass on a sample of entries before translating.
        Produces a richer, content-aware system prompt. Results are stored in the
        session so priming runs only once per series.
    .PARAMETER PrimingSampleSize
        Number of entries to send for content analysis. Default: 20.
    .PARAMETER ContentType
        Override the content type instead of inferring it from priming
        (film|series|documentary|animation|news|sports|educational|other).
    .PARAMETER ContentTitle
        Title of the content. Used in the system prompt for context.
    .PARAMETER TargetAudience
        Override the target audience (general|children|adult|professional|academic).
    .PARAMETER ToneHint
        Override the dominant tone (dramatic|comedic|action|romantic|neutral|tense|documentary|mixed).
    .PARAMETER SystemPromptPath
        Path to a custom system prompt template file. Placeholders {{BATCH_SIZE}},
        {{SOURCE}}, and {{TARGET}} are substituted before sending.
    .PARAMETER ProgressParentId
        Id of a caller's Write-Progress bar to nest this function's progress under
        (via -ParentId). This function's own bar uses -Id 2 and the priming phase
        uses -Id 3. Omit for a standalone call, which renders a top-level bar
        exactly as before. Used by Invoke-BackTranslation to nest translation
        progress beneath its own bar.
    .PARAMETER WhatIf
        Estimate token usage without calling the API.
    .EXAMPLE
        Set-TranslationProvider -Name Anthropic -Model 'claude-sonnet-4-6' -ApiKeyPlainText $key
        Invoke-SubtitleTranslation -Path 'movie.srt' -TargetLanguage 'fa' -ProviderName Anthropic -PrimeWithContext
    .EXAMPLE
        $session = New-TranslationSession -ProviderName OpenAI -GlossaryPath './glossary.json'
        Import-SubtitleFile 'ep01.srt' | Invoke-SubtitleTranslation -TargetLanguage 'fa' -Session $session -PrimeWithContext
        # Second episode reuses ContentContext from $session â€” no extra API call
        Import-SubtitleFile 'ep02.srt' | Invoke-SubtitleTranslation -TargetLanguage 'fa' -Session $session
    .EXAMPLE
        Invoke-SubtitleTranslation -Path 'anime.ass' -ProviderName Anthropic -TargetLanguage 'en' `
            -ContentType animation -ContentTitle 'Attack on Titan' -ToneHint dramatic
    #>
    [CmdletBinding(DefaultParameterSetName = 'Object', SupportsShouldProcess)]
    [OutputType('SubtitleFile')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Object')]
        [SubtitleFile] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string] $Path,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [Parameter(ParameterSetName = 'Object')]
        [ValidateSet('OpenAI', 'Anthropic', 'Google', 'OpenRouter')]
        [string] $ProviderName,

        [string] $SourceLanguage = '',

        [Parameter(Mandatory)]
        [string] $TargetLanguage,

        [hashtable] $Session,

        [string] $GlossaryPath,

        [string] $ResumeFrom,

        [string] $OutputPath,

        [string] $LogPath,

        [switch] $PrimeWithContext,

        [int] $PrimingSampleSize = 20,

        [ValidateSet('film','series','documentary','animation','news','sports','educational','other')]
        [string] $ContentType,

        [string] $ContentTitle,

        [ValidateSet('general','children','adult','professional','academic')]
        [string] $TargetAudience,

        [ValidateSet('dramatic','comedic','action','romantic','neutral','tense','documentary','mixed')]
        [string] $ToneHint,

        [string] $SystemPromptPath,

        [int] $ProgressParentId
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $InputObject = Import-SubtitleFile -Path $Path
        }

        # Resolve session
        if (-not $Session) {
            if (-not $ProviderName) {
                throw 'Specify -ProviderName or pass a -Session from New-TranslationSession.'
            }
            $Session = New-TranslationSession -ProviderName $ProviderName -GlossaryPath $GlossaryPath -CheckpointPath $ResumeFrom
        }

        $provider = $Session.Provider

        # Decrypt API key from DPAPI-protected store
        if ([string]::IsNullOrEmpty($provider.ApiKeyEncrypted)) {
            throw "No API key stored for provider '$($provider.Name)'. Run: Set-TranslationProvider -Name $($provider.Name) -ApiKeyPlainText 'your-key'"
        }
        try {
            $plainKey     = Unprotect-ApiKey -EncryptedBase64 $provider.ApiKeyEncrypted
            $apiKeySecure = ConvertTo-SecureString $plainKey -AsPlainText -Force
        } catch {
            throw "Failed to decrypt API key for '$($provider.Name)'. It may have been encrypted by a different Windows user: $_"
        }

        # Activity label, progress nesting, and the overall clock all need to exist
        # before priming runs: priming makes a real API call that can take many
        # seconds, and both its progress bar and the ETA/rate math below need to
        # account for that time.
        $activity = "Translating to '$TargetLanguage' via $($provider.Name) ($($provider.Model))"

        $progressParams = @{ Id = 2 }
        if ($PSBoundParameters.ContainsKey('ProgressParentId')) {
            $progressParams['ParentId'] = $ProgressParentId
        }

        # Compact-formats a token count for progress/log text, e.g. 12400 -> '12.4k'.
        $formatCount = {
            param([long] $Count)
            if ($Count -ge 1000) { '{0:N1}k' -f ($Count / 1000) } else { [string] $Count }
        }

        $overallStart = [datetime]::UtcNow

        # --- Priming phase ---
        # Run if: -PrimeWithContext is set AND session has no context yet
        if ($PrimeWithContext -and (-not $Session.ContentContext)) {
            Write-Verbose 'Starting translation priming (content analysis)...'
            Write-Progress @progressParams -Activity $activity `
                -Status "Phase 0 | Priming translation context ($PrimingSampleSize sample entries)..." `
                -PercentComplete 0

            $primedCtx = Invoke-TranslationPriming `
                -InputObject   $InputObject `
                -Session       $Session `
                -ApiKey        $apiKeySecure `
                -SourceLanguage $SourceLanguage `
                -TargetLanguage $TargetLanguage `
                -SampleSize    $PrimingSampleSize

            $Session.ContentContext = $primedCtx
        }

        # Apply manual overrides on top of primed (or null) context
        if ($ContentType -or $ContentTitle -or $TargetAudience -or $ToneHint) {
            if (-not $Session.ContentContext) {
                $Session.ContentContext = [PSCustomObject]@{
                    ContentType         = 'unknown'
                    ContentTitle        = 'UNKNOWN'
                    DominantTone        = 'neutral'
                    Register            = 'mixed'
                    TargetAudience      = 'general'
                    Pacing              = 'moderate'
                    DomainTerms         = 'NONE'
                    SpeakerPatterns     = ''
                    CulturalNotes       = 'NONE'
                    TranslationWarnings = 'NONE'
                    RawAnalysis         = ''
                }
            }
            if ($ContentType)    { $Session.ContentContext.ContentType    = $ContentType    }
            if ($ContentTitle)   { $Session.ContentContext.ContentTitle   = $ContentTitle   }
            if ($TargetAudience) { $Session.ContentContext.TargetAudience = $TargetAudience }
            if ($ToneHint)       { $Session.ContentContext.DominantTone   = $ToneHint       }
        }

        # Build translated file as a copy
        $translated          = [SubtitleFile]::new()
        $translated.Format   = $InputObject.Format
        $translated.Encoding = 'UTF-8'
        $translated.Header   = $InputObject.Header
        $translated.Path     = $OutputPath

        $translatedEntries = [System.Collections.Generic.List[SubtitleEntry]]::new()

        $charsPerToken = 4
        $maxChars      = $provider.MaxTokensPerBatch * $charsPerToken
        $allEntries    = $InputObject.Entries
        $totalEntries  = $allEntries.Count
        $doneEntries   = 0

        # Running totals across all batches (a batch that is entirely cache hits
        # makes zero API calls and contributes zeros here, not a failure).
        $totalInputTokens  = 0
        $totalOutputTokens = 0
        $totalRetries      = 0

        $translateBatch = {
            param($batchEntries, $prov, $key, $src, $tgt, $glossary, $cache, $contentCtx, $promptPath, $logPath)

            $texts = $batchEntries | ForEach-Object { $_.Lines -join '<NL>' }

            $toTranslate  = [System.Collections.Generic.List[int]]::new()
            $batchResult  = @{}
            $inputTokens  = 0
            $outputTokens = 0
            $retryCount   = 0

            for ($idx = 0; $idx -lt $texts.Count; $idx++) {
                $hash = ([System.Security.Cryptography.MD5]::Create().ComputeHash(
                    [System.Text.Encoding]::UTF8.GetBytes($texts[$idx])
                ) | ForEach-Object { $_.ToString('x2') }) -join ''

                if ($cache.ContainsKey($hash)) {
                    $batchResult[$idx] = $cache[$hash]
                } else {
                    $toTranslate.Add($idx)
                }
            }

            if ($toTranslate.Count -gt 0) {
                $n        = $toTranslate.Count
                $srcTexts = $toTranslate | ForEach-Object { $texts[$_] }

                $systemPrompt = Build-TranslationSystemPrompt `
                    -BatchSize      $n `
                    -SourceLanguage $src `
                    -TargetLanguage $tgt `
                    -ContentContext $contentCtx `
                    -Glossary       $glossary `
                    -SystemPromptPath $(if ($promptPath) { $promptPath } else { '' })

                # Numbered format: "1|text\n2|text\n..." — immune to pipe chars in translated text
                $userContent = (0..($srcTexts.Count - 1) | ForEach-Object { "$($_ + 1)|$($srcTexts[$_])" }) -join "`n"

                $adapterResult = Invoke-TranslationProviderAdapter -SystemPrompt $systemPrompt -UserContent $userContent -Provider $prov -ApiKey $key

                $inputTokens  = $adapterResult.InputTokens
                $outputTokens = $adapterResult.OutputTokens
                $retryCount   = $adapterResult.RetryCount

                if ($adapterResult.FinishReason -eq 'error') {
                    throw "API call failed: $($adapterResult.Content)"
                }

                # Parse "N|translation" lines — split on first pipe only so translated text can contain pipes
                $responseMap = @{}
                foreach ($line in ($adapterResult.Content -split '\r?\n')) {
                    if ($line -match '^(\d+)\|(.*)$') {
                        $responseMap[[int]$Matches[1]] = $Matches[2].Trim()
                    }
                }

                $missing = 0
                for ($r = 0; $r -lt $toTranslate.Count; $r++) {
                    $origIdx     = $toTranslate[$r]
                    $oneBasedIdx = $r + 1
                    $hash        = ([System.Security.Cryptography.MD5]::Create().ComputeHash(
                        [System.Text.Encoding]::UTF8.GetBytes($texts[$origIdx])
                    ) | ForEach-Object { $_.ToString('x2') }) -join ''

                    $xlat = if ($responseMap.ContainsKey($oneBasedIdx)) {
                        $responseMap[$oneBasedIdx]
                    } else {
                        $missing++
                        $texts[$origIdx]    # fall back to source text
                    }

                    $batchResult[$origIdx] = $xlat
                    $cache[$hash]          = $xlat
                }

                if ($missing -gt 0) {
                    Write-SubtitleLog -Message "$missing entr$(if ($missing -eq 1) {'y'} else {'ies'}) missing from translation response. Source text used as fallback." `
                        -Level Warning -LogPath $logPath
                }
            }

            return @{
                Results      = $batchResult
                InputTokens  = $inputTokens
                OutputTokens = $outputTokens
                RetryCount   = $retryCount
            }
        }

        # Writes the current cache to the session checkpoint (no-op if none is
        # configured). Reused both on a mid-run failure and on normal completion
        # so a failed batch never discards the progress already cached.
        $saveCheckpoint = {
            param($sess)
            if ($sess.CheckpointPath) {
                $sess.Cache | ConvertTo-Json -Depth 3 | Set-Content $sess.CheckpointPath -Encoding UTF8
            }
        }

        # Rate-limit tracking
        $rpmWindowStart = [datetime]::UtcNow
        $rpmCount       = 0

        $pendingBatch = [System.Collections.Generic.List[SubtitleEntry]]::new()
        $batchChars   = 0
        $batchNum     = 0

        foreach ($entry in $allEntries) {
            $entryText  = $entry.Lines -join '<NL>'
            $entryChars = $entryText.Length

            if ($batchChars + $entryChars -gt $maxChars -and $pendingBatch.Count -gt 0) {
                if ($PSCmdlet.ShouldProcess("$($pendingBatch.Count) entries", 'Translate')) {
                    $batchNum++

                    # Rate limiting
                    $rpmCount++
                    if ($provider.RateLimitRpm -gt 0 -and $rpmCount -ge $provider.RateLimitRpm) {
                        $rpmElapsed = ([datetime]::UtcNow - $rpmWindowStart).TotalSeconds
                        if ($rpmElapsed -lt 60) {
                            $wait = [int](60 - $rpmElapsed) + 1
                            Write-Verbose "Rate limit reached. Waiting ${wait}s..."
                            Write-Progress @progressParams -Activity $activity `
                                -Status "Batch $batchNum | Rate limit — waiting ${wait}s..." `
                                -PercentComplete ([int](($doneEntries / $totalEntries) * 100))
                            Start-Sleep -Seconds $wait
                        }
                        $rpmWindowStart = [datetime]::UtcNow
                        $rpmCount       = 0
                    }

                    Write-Progress @progressParams -Activity $activity `
                        -Status "Batch $batchNum | Calling API ($($pendingBatch.Count) entries) | Done: $doneEntries/$totalEntries..." `
                        -PercentComplete ([int](($doneEntries / $totalEntries) * 100))

                    $batchStart = [datetime]::UtcNow
                    try {
                        $batchOutcome = & $translateBatch $pendingBatch $provider $apiKeySecure `
                            $SourceLanguage $TargetLanguage $Session.Glossary $Session.Cache `
                            $Session.ContentContext $SystemPromptPath $LogPath
                    } catch {
                        & $saveCheckpoint $Session
                        throw
                    }
                    $batchElapsed = [int]([datetime]::UtcNow - $batchStart).TotalSeconds

                    $totalInputTokens  += $batchOutcome.InputTokens
                    $totalOutputTokens += $batchOutcome.OutputTokens
                    $totalRetries      += $batchOutcome.RetryCount

                    for ($r = 0; $r -lt $pendingBatch.Count; $r++) {
                        $srcEntry = $pendingBatch[$r]
                        $newLines = ($batchOutcome.Results[$r] -replace '<NL>', "`n") -split "`n"
                        $newEntry = New-SubtitleEntryCopy -Source $srcEntry -Lines $newLines
                        $translatedEntries.Add($newEntry)
                    }

                    $doneEntries += $pendingBatch.Count

                    $totalElapsed = ([datetime]::UtcNow - $overallStart).TotalSeconds
                    $rate         = if ($totalElapsed -gt 0) { [int]($doneEntries / $totalElapsed * 60) } else { 0 }
                    $remaining    = $totalEntries - $doneEntries
                    $etaSec       = if ($rate -gt 0) { [int]($remaining / ($rate / 60)) } else { 0 }
                    $etaStr       = if ($etaSec -gt 60) { '{0}m {1}s' -f [int]($etaSec / 60), ($etaSec % 60) } else { "${etaSec}s" }
                    $tokStr       = "$(& $formatCount $totalInputTokens)/$(& $formatCount $totalOutputTokens) tok"

                    Write-Progress @progressParams -Activity $activity `
                        -Status "Batch $batchNum done in ${batchElapsed}s | $doneEntries/$totalEntries entries | ~$rate/min | ETA $etaStr | $tokStr" `
                        -PercentComplete ([int](($doneEntries / $totalEntries) * 100))

                    Write-SubtitleLog -Message "Batch $batchNum`: $($pendingBatch.Count) entries in ${batchElapsed}s." -LogPath $LogPath
                }

                $pendingBatch.Clear()
                $batchChars = 0
            }

            $pendingBatch.Add($entry)
            $batchChars += $entryChars
        }

        # Final batch
        if ($pendingBatch.Count -gt 0 -and $PSCmdlet.ShouldProcess("$($pendingBatch.Count) entries", 'Translate')) {
            $batchNum++

            Write-Progress @progressParams -Activity $activity `
                -Status "Batch $batchNum (final) | Calling API ($($pendingBatch.Count) entries) | Done: $doneEntries/$totalEntries..." `
                -PercentComplete 99

            $batchStart = [datetime]::UtcNow
            try {
                $batchOutcome = & $translateBatch $pendingBatch $provider $apiKeySecure `
                    $SourceLanguage $TargetLanguage $Session.Glossary $Session.Cache `
                    $Session.ContentContext $SystemPromptPath $LogPath
            } catch {
                & $saveCheckpoint $Session
                throw
            }
            $batchElapsed = [int]([datetime]::UtcNow - $batchStart).TotalSeconds

            $totalInputTokens  += $batchOutcome.InputTokens
            $totalOutputTokens += $batchOutcome.OutputTokens
            $totalRetries      += $batchOutcome.RetryCount

            for ($r = 0; $r -lt $pendingBatch.Count; $r++) {
                $srcEntry = $pendingBatch[$r]
                $newLines = ($batchOutcome.Results[$r] -replace '<NL>', "`n") -split "`n"
                $newEntry = New-SubtitleEntryCopy -Source $srcEntry -Lines $newLines
                $translatedEntries.Add($newEntry)
            }

            $doneEntries += $pendingBatch.Count

            Write-SubtitleLog -Message "Batch $batchNum (final): $($pendingBatch.Count) entries in ${batchElapsed}s." -LogPath $LogPath
        }

        Write-Progress @progressParams -Activity $activity -Completed

        # Save checkpoint
        & $saveCheckpoint $Session

        $translated.Entries = $translatedEntries.ToArray()

        $tokenSummary = "$(& $formatCount $totalInputTokens)/$(& $formatCount $totalOutputTokens) tok"
        $retrySuffix  = if ($totalRetries -gt 0) { " Retries: $totalRetries." } else { '' }
        Write-SubtitleLog -Message "Translation complete. $($translated.Entries.Count) entries. Provider: $($provider.Name) / $($provider.Model). Tokens: $tokenSummary.$retrySuffix" `
            -LogPath $LogPath

        if ($OutputPath -and $PSCmdlet.ShouldProcess($OutputPath, 'Save translated subtitle')) {
            Export-SubtitleFile -InputObject $translated -Path $OutputPath
        }

        return $translated
    }
}
