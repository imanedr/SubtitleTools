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
        Set-TranslationProvider -Name Anthropic -Model 'claude-sonnet-5' -ApiKeyPlainText 'sk-ant-...'

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
    .PARAMETER NoStream
        Disable streaming and use a single buffered request per batch. Streaming is on
        by default: it is what makes the progress bar advance line-by-line while a
        batch is still being translated, instead of jumping only once the whole batch
        lands. Use this if a proxy or gateway in front of the provider does not pass
        server-sent events through cleanly. Translation output is identical either way.
    .PARAMETER NoSummary
        Suppress the end-of-run summary block printed to the console (provider, model,
        entry/cache/unresolved counts, batches, API calls, retries, token usage, elapsed
        time). The same data is always available on the returned object's
        .TranslationSummary property regardless of this switch.
    .PARAMETER ProgressParentId
        Id of a caller's Write-Progress bar to nest this function's progress under
        (via -ParentId). This function's own bar uses -Id 2 and the priming phase
        uses -Id 3. Omit for a standalone call, which renders a top-level bar
        exactly as before. Used by Invoke-BackTranslation to nest translation
        progress beneath its own bar.
    .PARAMETER WhatIf
        Estimate token usage without calling the API.
    .EXAMPLE
        Set-TranslationProvider -Name Anthropic -Model 'claude-sonnet-5' -ApiKeyPlainText $key
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

        [switch] $NoStream,

        [switch] $NoSummary,

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

            $primingStart = [datetime]::UtcNow

            # Repaints one status line in place. Padded out to the widest line written
            # so far: without that, a shorter line ("Found: CONTENT_TYPE") leaves the
            # tail of the longer one it overwrote ("... | 213s elapsed") on screen.
            $inlineState = @{ Width = 0 }
            $writeInline = {
                param([string] $Text)
                if ($Text.Length -gt $inlineState.Width) { $inlineState.Width = $Text.Length }
                Write-Host ("`r{0}" -f $Text.PadRight($inlineState.Width)) -NoNewline
            }.GetNewClosure()

            # Live progress for the priming call, reducing the raw stream deltas to one
            # human-readable line: "Thinking...", "Writing: N chars", or the analysis
            # fields as the model names them. Which models reason and which do not is
            # never inferred from the model name - a name-matching list is wrong the day
            # a provider ships a model it has not heard of, and wrong today for models
            # whose thinking this module never asks for. The stream says so directly.
            $primingCallback = $null
            if (-not $NoStream) {
                $primingState = @{
                    LastUpdate = [datetime]::MinValue
                    Fields     = [System.Collections.Generic.List[string]]::new()
                    Connected  = $false
                }
                $primingCallback = {
                    param($accumulated, $counters)

                    $now = [datetime]::UtcNow
                    if (($now - $primingState.LastUpdate).TotalMilliseconds -lt 500) { return }
                    $primingState.LastUpdate = $now

                    if (-not $primingState.Connected) {
                        $primingState.Connected = $true
                        # Worth having when diagnosing "it just sits there": the status
                        # line below only ever moves if the SSE path is genuinely live,
                        # so this is the marker that separates "streaming, and the model
                        # is slow" from "fell back to a buffered request".
                        Write-Verbose 'Priming stream connected.'
                    }

                    $elapsed = [int]($now - $primingStart).TotalSeconds

                    if ($counters.Reasoning) {
                        # ReasoningLength is 0 when the provider returns its thinking as
                        # an opaque blob - the phase is real, there is just nothing to
                        # count - so the char figure is only shown when there is one.
                        $status = if ($counters.ReasoningLength -gt 0) {
                            "Thinking... $($counters.ReasoningLength) reasoning chars | ${elapsed}s elapsed"
                        } else {
                            "Thinking... | ${elapsed}s elapsed"
                        }
                    } elseif ($accumulated) {
                        foreach ($line in ($accumulated -split "`n")) {
                            if ($line -match '^([A-Z_]+):\s*') {
                                $field = $Matches[1]
                                if ($primingState.Fields -notcontains $field) {
                                    $primingState.Fields.Add($field)
                                }
                            }
                        }
                        $status = if ($primingState.Fields.Count -gt 0) {
                            "Found: $($primingState.Fields -join ', ') | ${elapsed}s elapsed"
                        } else {
                            "Writing: $($accumulated.Length) chars | ${elapsed}s elapsed"
                        }
                    } else {
                        return
                    }

                    & $writeInline "  Priming: $status"
                    Write-Progress -Id 3 -ParentId 2 -Activity 'Priming translation context' `
                        -Status $status -PercentComplete 0
                }.GetNewClosure()

                & $writeInline '  Priming: Sending samples for analysis...'
            }

            # Invoke-TranslationPriming raises and completes the -Id 3 bar itself; this
            # function only supplies the callback that keeps it moving in between.
            $primedCtx = Invoke-TranslationPriming `
                -InputObject    $InputObject `
                -Session        $Session `
                -ApiKey         $apiKeySecure `
                -SourceLanguage $SourceLanguage `
                -TargetLanguage $TargetLanguage `
                -SampleSize     $PrimingSampleSize `
                -StreamCallback $primingCallback

            # Close the in-place status line - only if one was ever opened.
            if (-not $NoStream) { Write-Host '' }

            $primingElapsed = [int]([datetime]::UtcNow - $primingStart).TotalSeconds
            if ($primingElapsed -gt 90) {
                Write-Warning "Priming took $($primingElapsed)s. Reasoning models can spend several minutes on content analysis. Consider skipping priming with -PrimeWithContext:`$false or using a non-reasoning model."
            }

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
        # MaxEntriesPerBatch bounds how much the model has to WRITE per call. Without
        # it a short file slips under the character budget as a single batch, and
        # asking for hundreds of translated lines in one response invites truncation
        # and line-numbering drift. 0/unset means the property predates this version.
        $maxEntries    = if ($provider.MaxEntriesPerBatch -gt 0) { $provider.MaxEntriesPerBatch } else { 40 }
        $allEntries    = $InputObject.Entries
        $totalEntries  = $allEntries.Count
        $doneEntries   = 0

        # Running totals across all batches (a batch that is entirely cache hits
        # makes zero API calls and contributes zeros here, not a failure).
        $totalInputTokens  = 0
        $totalOutputTokens = 0
        $totalRetries      = 0
        $totalApiCalls     = 0
        $totalUnresolved   = 0
        $totalCacheHits    = 0
        $truncatedBatches  = 0

        $translateBatch = {
            param($batchEntries, $prov, $key, $src, $tgt, $glossary, $cache, $contentCtx, $promptPath, $logPath, $onProgress, $onLiveProgress)

            $texts = @($batchEntries | ForEach-Object { $_.Lines -join '<NL>' })

            $toTranslate  = [System.Collections.Generic.List[int]]::new()
            $batchResult  = @{}
            $inputTokens  = 0
            $outputTokens = 0
            $retryCount   = 0
            $apiCalls     = 0
            $unresolved   = 0
            $truncated    = $false

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
                $srcTexts = @($toTranslate | ForEach-Object { $texts[$_] })

                # Handles truncated responses and numbering drift by re-asking for the
                # missing entries in progressively smaller batches - see
                # Invoke-TranslationBatchRequest.
                $req = Invoke-TranslationBatchRequest `
                    -Texts            $srcTexts `
                    -Provider         $prov `
                    -ApiKey           $key `
                    -SourceLanguage   $src `
                    -TargetLanguage   $tgt `
                    -Glossary         $glossary `
                    -ContentContext   $contentCtx `
                    -SystemPromptPath $(if ($promptPath) { $promptPath } else { '' }) `
                    -OnProgress       $onProgress `
                    -OnLiveProgress   $onLiveProgress

                $inputTokens  = $req.InputTokens
                $outputTokens = $req.OutputTokens
                $retryCount   = $req.RetryCount
                $apiCalls     = $req.ApiCalls
                $truncated    = [bool] $req.Truncated

                for ($r = 0; $r -lt $toTranslate.Count; $r++) {
                    $origIdx = $toTranslate[$r]
                    $hash    = ([System.Security.Cryptography.MD5]::Create().ComputeHash(
                        [System.Text.Encoding]::UTF8.GetBytes($texts[$origIdx])
                    ) | ForEach-Object { $_.ToString('x2') }) -join ''

                    $xlat = $req.Translations[$r]

                    if ([string]::IsNullOrEmpty($xlat)) {
                        # Last resort after every retry level failed: keep the source
                        # text so timings and entry count stay intact. Deliberately NOT
                        # written to the cache - caching an untranslated fallback would
                        # make it a permanent cache hit, so a resume or a re-run could
                        # never fix it.
                        $unresolved++
                        $batchResult[$origIdx] = $texts[$origIdx]
                    } else {
                        $batchResult[$origIdx] = $xlat
                        $cache[$hash]          = $xlat
                    }
                }

                if ($unresolved -gt 0) {
                    Write-SubtitleLog -Message "$unresolved entr$(if ($unresolved -eq 1) {'y'} else {'ies'}) could not be translated after retrying in smaller batches. Source text used as fallback." `
                        -Level Warning -LogPath $logPath
                }
            }

            return @{
                Results      = $batchResult
                InputTokens  = $inputTokens
                OutputTokens = $outputTokens
                RetryCount   = $retryCount
                ApiCalls     = $apiCalls
                Unresolved   = $unresolved
                Truncated    = $truncated
                CacheHits    = $texts.Count - $toTranslate.Count
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

        # --- Batch plan ---
        # Batches are planned up front rather than accumulated while iterating, so the
        # progress bar can report a real "Batch 3/8" denominator, and so there is one
        # translate code path instead of a main loop plus a duplicated final-batch block.
        $batches      = [System.Collections.Generic.List[object]]::new()
        $pendingBatch = [System.Collections.Generic.List[SubtitleEntry]]::new()
        $batchChars   = 0
        # Reported in the run summary. Counted on the raw text, not on the '<NL>'-joined
        # wire form, so it is the number of characters actually in the subtitle.
        $sourceChars  = 0

        foreach ($entry in $allEntries) {
            $entryChars   = ($entry.Lines -join '<NL>').Length
            $sourceChars += ($entry.Lines -join "`n").Length

            $overflowsChars   = ($batchChars + $entryChars) -gt $maxChars
            $overflowsEntries = $pendingBatch.Count -ge $maxEntries

            if ($pendingBatch.Count -gt 0 -and ($overflowsChars -or $overflowsEntries)) {
                $batches.Add($pendingBatch)
                $pendingBatch = [System.Collections.Generic.List[SubtitleEntry]]::new()
                $batchChars   = 0
            }

            $pendingBatch.Add($entry)
            $batchChars += $entryChars
        }
        if ($pendingBatch.Count -gt 0) { $batches.Add($pendingBatch) }

        $totalBatches = $batches.Count
        Write-Verbose "Translation plan: $totalEntries entries across $totalBatches batch(es) (cap: $maxEntries entries / $maxChars chars per call)."

        for ($b = 0; $b -lt $totalBatches; $b++) {
            $currentBatch = $batches[$b]
            $batchNum     = $b + 1

            if (-not $PSCmdlet.ShouldProcess("$($currentBatch.Count) entries", 'Translate')) { continue }

            $percent = [int](($doneEntries / $totalEntries) * 100)

            # Rate limiting. $rpmCount counts API calls actually made, not batches -
            # a batch that had to split and retry costs several requests.
            if ($provider.RateLimitRpm -gt 0 -and $rpmCount -ge $provider.RateLimitRpm) {
                $rpmElapsed = ([datetime]::UtcNow - $rpmWindowStart).TotalSeconds
                if ($rpmElapsed -lt 60) {
                    $wait = [int](60 - $rpmElapsed) + 1
                    Write-Verbose "Rate limit reached. Waiting ${wait}s..."
                    Write-Progress @progressParams -Activity $activity `
                        -Status "Batch $batchNum/$totalBatches | Rate limit — waiting ${wait}s..." `
                        -PercentComplete $percent
                    Start-Sleep -Seconds $wait
                }
                $rpmWindowStart = [datetime]::UtcNow
                $rpmCount       = 0
            }

            # Keeps the bar moving while a self-healing retry round runs inside the
            # batch, which would otherwise look identical to a hung API call.
            $onProgress = {
                param($statusText)
                Write-Progress @progressParams -Activity $activity `
                    -Status "Batch $batchNum/$totalBatches | $statusText" -PercentComplete $percent
            }.GetNewClosure()

            # Live, sub-batch progress: fires while the model is still writing, so the
            # bar advances per translated line and the token counters tick up, rather
            # than the whole batch landing at once after a long silence. Only reached
            # when streaming is enabled AND the provider actually streams.
            $onLiveProgress = $null
            if (-not $NoStream) {
                $onLiveProgress = {
                    param($live)

                    $inSoFar  = $totalInputTokens  + $live.InputTokens
                    $outSoFar = $totalOutputTokens + $live.OutputTokens
                    # '~' marks a chars/4 approximation, shown until the provider
                    # reports real usage (OpenAI-compatible APIs only do so at the end).
                    $prefix   = if ($live.OutputEstimated) { '~' } else { '' }
                    $tokens   = "$(& $formatCount $inSoFar)/$prefix$(& $formatCount $outSoFar) tok"

                    # At Depth > 0 this is a recovery pass over entries the batch has
                    # already reported, so its line count must not be added to the
                    # running total - doing so makes the bar jump backwards.
                    if ($live.Depth -gt 0) {
                        $phase       = "Recovering $($live.LinesDone)/$($live.Expected)"
                        $entriesDone = $doneEntries
                    } elseif ($live.Reasoning) {
                        # A reasoning model emits nothing visible for a long time before
                        # the first translated line. Name that phase, or the batch is
                        # indistinguishable from a hung request. Reasoning only ever
                        # reports true before the first visible character, so this
                        # cannot pull $entriesDone backwards mid-batch.
                        $phase = if ($live.ReasoningLength -gt 0) {
                            "Thinking ($($live.ReasoningLength) reasoning chars)"
                        } else {
                            'Thinking'
                        }
                        $entriesDone = $doneEntries
                    } else {
                        $phase       = "Translating $($live.LinesDone)/$($live.Expected)"
                        $entriesDone = $doneEntries + $live.LinesDone
                    }

                    $livePercent = [int](($entriesDone / $totalEntries) * 100)
                    if ($livePercent -gt 100) { $livePercent = 100 }

                    Write-Progress @progressParams -Activity $activity `
                        -Status "Batch $batchNum/$totalBatches | $phase | $entriesDone/$totalEntries entries | $tokens" `
                        -PercentComplete $livePercent
                }.GetNewClosure()
            }

            Write-Progress @progressParams -Activity $activity `
                -Status "Batch $batchNum/$totalBatches | Calling API ($($currentBatch.Count) entries) | $doneEntries/$totalEntries done..." `
                -PercentComplete $percent

            $batchStart = [datetime]::UtcNow
            try {
                $batchOutcome = & $translateBatch $currentBatch $provider $apiKeySecure `
                    $SourceLanguage $TargetLanguage $Session.Glossary $Session.Cache `
                    $Session.ContentContext $SystemPromptPath $LogPath $onProgress $onLiveProgress
            } catch {
                & $saveCheckpoint $Session
                throw
            }
            $batchElapsed = [int]([datetime]::UtcNow - $batchStart).TotalSeconds

            $totalInputTokens  += $batchOutcome.InputTokens
            $totalOutputTokens += $batchOutcome.OutputTokens
            $totalRetries      += $batchOutcome.RetryCount
            $totalApiCalls     += $batchOutcome.ApiCalls
            $totalUnresolved   += $batchOutcome.Unresolved
            $totalCacheHits    += $batchOutcome.CacheHits
            $rpmCount          += $batchOutcome.ApiCalls
            if ($batchOutcome.Truncated) { $truncatedBatches++ }

            for ($r = 0; $r -lt $currentBatch.Count; $r++) {
                $srcEntry = $currentBatch[$r]
                $newLines = ($batchOutcome.Results[$r] -replace '<NL>', "`n") -split "`n"
                $newEntry = New-SubtitleEntryCopy -Source $srcEntry -Lines $newLines
                $translatedEntries.Add($newEntry)
            }

            $doneEntries += $currentBatch.Count

            $totalElapsed = ([datetime]::UtcNow - $overallStart).TotalSeconds
            $rate         = if ($totalElapsed -gt 0) { [int]($doneEntries / $totalElapsed * 60) } else { 0 }
            $remaining    = $totalEntries - $doneEntries
            $etaSec       = if ($rate -gt 0) { [int]($remaining / ($rate / 60)) } else { 0 }
            $etaStr       = if ($etaSec -gt 60) { '{0}m {1}s' -f [int]($etaSec / 60), ($etaSec % 60) } else { "${etaSec}s" }
            $tokStr       = "$(& $formatCount $totalInputTokens)/$(& $formatCount $totalOutputTokens) tok"

            Write-Progress @progressParams -Activity $activity `
                -Status "Batch $batchNum/$totalBatches done in ${batchElapsed}s | $doneEntries/$totalEntries entries | ~$rate/min | ETA $etaStr | $tokStr" `
                -PercentComplete ([int](($doneEntries / $totalEntries) * 100))

            Write-SubtitleLog -Message "Batch $batchNum/$totalBatches`: $($currentBatch.Count) entries in ${batchElapsed}s." -LogPath $LogPath
        }

        Write-Progress @progressParams -Activity $activity -Completed

        # Save checkpoint
        & $saveCheckpoint $Session

        $translated.Entries = $translatedEntries.ToArray()

        # --- Run summary ---
        # Everything the run learned that is not in the subtitle itself: what was
        # actually sent where, what it cost, and how much of it came back. Attached to
        # the returned file so it survives into a variable, a log, or a batch report -
        # the printed block below is only a rendering of this object.
        $runElapsed = [datetime]::UtcNow - $overallStart

        $outputChars = 0
        foreach ($te in $translatedEntries) { $outputChars += ($te.Lines -join "`n").Length }

        $ctx = $Session.ContentContext

        $summary = [PSCustomObject]@{
            PSTypeName        = 'SubtitleTools.TranslationSummary'
            Provider          = $provider.Name
            Model             = $provider.Model
            SourceLanguage    = $(if ($SourceLanguage) { $SourceLanguage } else { 'auto-detect' })
            TargetLanguage    = $TargetLanguage
            SourcePath        = $InputObject.Path
            OutputPath        = $OutputPath
            Format            = $translated.Format
            Encoding          = $translated.Encoding
            Entries           = $totalEntries
            # Newly translated by the API, i.e. neither served from cache nor left as
            # source text - the three counts add up to the entries actually processed.
            TranslatedEntries = $doneEntries - $totalCacheHits - $totalUnresolved
            CachedEntries     = $totalCacheHits
            UnresolvedEntries = $totalUnresolved
            SourceCharacters  = $sourceChars
            OutputCharacters  = $outputChars
            Batches           = $totalBatches
            ApiCalls          = $totalApiCalls
            Retries           = $totalRetries
            TruncatedBatches  = $truncatedBatches
            InputTokens       = $totalInputTokens
            OutputTokens      = $totalOutputTokens
            TotalTokens       = $totalInputTokens + $totalOutputTokens
            Streaming         = (-not $NoStream)
            Primed            = ($null -ne $ctx)
            ContentType       = $(if ($ctx) { $ctx.ContentType }  else { $null })
            ContentTitle      = $(if ($ctx) { $ctx.ContentTitle } else { $null })
            Tone              = $(if ($ctx) { $ctx.DominantTone } else { $null })
            GlossaryTerms     = $(if ($Session.Glossary) { $Session.Glossary.Count } else { 0 })
            Duration          = $runElapsed
            EntriesPerMinute  = $(if ($runElapsed.TotalSeconds -gt 0) { [int]($doneEntries / $runElapsed.TotalSeconds * 60) } else { 0 })
            StartedAt         = $overallStart.ToLocalTime()
            CompletedAt       = [datetime]::UtcNow.ToLocalTime()
        }

        $translated | Add-Member -NotePropertyName TranslationSummary -NotePropertyValue $summary -Force

        $tokenSummary = "$(& $formatCount $totalInputTokens)/$(& $formatCount $totalOutputTokens) tok"
        $retrySuffix  = if ($totalRetries -gt 0) { " Retries: $totalRetries." } else { '' }
        $cacheSuffix  = if ($totalCacheHits -gt 0) { " Cache hits: $totalCacheHits." } else { '' }
        Write-SubtitleLog -Message "Translation complete. $($translated.Entries.Count) entries in $totalBatches batch(es), $totalApiCalls API call(s), $([int]$runElapsed.TotalSeconds)s. Provider: $($provider.Name) / $($provider.Model). Tokens: $tokenSummary.$retrySuffix$cacheSuffix" `
            -LogPath $LogPath

        if ($OutputPath -and $PSCmdlet.ShouldProcess($OutputPath, 'Save translated subtitle')) {
            Export-SubtitleFile -InputObject $translated -Path $OutputPath
        }

        # Under -WhatIf no batch actually ran, so a summary of the run would be a
        # summary of nothing.
        if (-not $NoSummary -and -not $WhatIfPreference) {
            Write-TranslationSummary -Summary $summary
        }

        # A partially-translated file is the failure mode most likely to go unnoticed:
        # it opens fine, plays fine, and only the untranslated tail gives it away. Say
        # so loudly on the warning stream, not just in the log file - and last, so the
        # fix is the final thing on screen.
        if ($totalUnresolved -gt 0) {
            Write-Warning ("{0} of {1} entries could not be translated and kept their source text. " -f $totalUnresolved, $totalEntries +
                "This usually means the model's output was cut short. Try a lower -MaxEntriesPerBatch or a higher -MaxOutputTokens: " +
                "Set-TranslationProvider -Name $($provider.Name) -MaxEntriesPerBatch 20")
        }

        return $translated
    }
}
