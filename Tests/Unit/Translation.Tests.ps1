#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0.0'}

# NOTE ON TEST TECHNIQUE: TranslationProvider instances and SecureString API keys
# are deliberately constructed *inside* each InModuleScope scriptblock (from
# primitive -Parameters values) rather than built once outside and passed in.
# Marshaling an instance of a module-defined PowerShell class across the
# InModuleScope session-state boundary via -Parameters causes PowerShell to lose
# track of the [TranslationProvider] type, which then surfaces - not as a clean
# type error, but as Pester's generic "break/continue statement escaped" failure
# (a known rough edge, see https://github.com/pester/Pester/issues/2669).
# Building the object inside the module's own scope sidesteps this entirely and
# is confirmed working below.

BeforeAll {
    $ModulePath = Join-Path (Join-Path $PSScriptRoot '..') (Join-Path '..' 'SubtitleTools.psd1')
    Import-Module $ModulePath -Force
}

Describe 'Invoke-TranslationApiRequest retry classification (Bug G)' {
    BeforeEach {
        Mock -ModuleName SubtitleTools -CommandName Start-Sleep -MockWith { }
    }

    It 'Retries a 429 up to MaxRetries times, waiting between attempts, then reports failure with RetryCount = MaxRetries' {
        Mock -ModuleName SubtitleTools -CommandName Invoke-RestMethod -MockWith {
            $ex = [System.Exception]::new('Too Many Requests')
            $ex | Add-Member -NotePropertyName Response -NotePropertyValue ([PSCustomObject]@{ StatusCode = 429 }) -Force
            throw $ex
        }

        $result = InModuleScope SubtitleTools {
            Invoke-TranslationApiRequest -Uri 'https://example.test/v1/messages' `
                -Body @{ foo = 'bar' } -Headers @{} -ProviderLabel 'Test' -MaxRetries 3
        }

        $result.Success    | Should -BeFalse
        $result.StatusCode | Should -Be 429
        $result.RetryCount | Should -Be 3

        # Regression guard for "retry everything": exactly 1 initial attempt + 3
        # retries, and a Start-Sleep backoff between each of the 3 retries.
        Should -Invoke -ModuleName SubtitleTools -CommandName Invoke-RestMethod -Times 4 -Exactly
        Should -Invoke -ModuleName SubtitleTools -CommandName Start-Sleep -Times 3 -Exactly
    }

    It 'Fails a 401 immediately without retrying (RetryCount = 0)' {
        Mock -ModuleName SubtitleTools -CommandName Invoke-RestMethod -MockWith {
            $ex = [System.Exception]::new('Unauthorized')
            $ex | Add-Member -NotePropertyName Response -NotePropertyValue ([PSCustomObject]@{ StatusCode = 401 }) -Force
            throw $ex
        }

        $result = InModuleScope SubtitleTools {
            Invoke-TranslationApiRequest -Uri 'https://example.test/v1/messages' `
                -Body @{ foo = 'bar' } -Headers @{} -ProviderLabel 'Test' -MaxRetries 3
        }

        $result.Success    | Should -BeFalse
        $result.StatusCode | Should -Be 401
        $result.RetryCount | Should -Be 0

        Should -Invoke -ModuleName SubtitleTools -CommandName Invoke-RestMethod -Times 1 -Exactly
        Should -Invoke -ModuleName SubtitleTools -CommandName Start-Sleep -Times 0 -Exactly
    }

    It 'Rejects a Content-Type entry in -Headers rather than ever forwarding it (Bug B guard)' {
        InModuleScope SubtitleTools {
            {
                Invoke-TranslationApiRequest -Uri 'https://example.test/v1/messages' `
                    -Body @{ foo = 'bar' } -Headers @{ 'Content-Type' = 'application/json' } -ProviderLabel 'Test'
            } | Should -Throw
        }
    }
}

Describe 'Invoke-AnthropicTranslation text block selection (Bug E)' {
    BeforeAll {
        Mock -ModuleName SubtitleTools -CommandName Start-Sleep -MockWith { }
    }

    It 'Selects the first block whose type is text, skipping a leading thinking block' {
        Mock -ModuleName SubtitleTools -CommandName Invoke-RestMethod -MockWith {
            [PSCustomObject]@{
                content = @(
                    [PSCustomObject]@{ type = 'thinking'; thinking = 'internal reasoning, not the answer' }
                    [PSCustomObject]@{ type = 'text'; text = '1|Hello world' }
                )
                usage       = [PSCustomObject]@{ input_tokens = 10; output_tokens = 5 }
                stop_reason = 'end_turn'
                model       = 'claude-test'
            }
        }

        $result = InModuleScope SubtitleTools -Parameters @{ modelName = 'claude-test'; baseUrl = 'https://api.anthropic.test/v1'; keyPlain = 'test-key' } {
            param($modelName, $baseUrl, $keyPlain)
            $provider          = [TranslationProvider]::new()
            $provider.Name     = 'Anthropic'
            $provider.Model    = $modelName
            $provider.BaseUrl  = $baseUrl
            $key = ConvertTo-SecureString $keyPlain -AsPlainText -Force
            Invoke-AnthropicTranslation -SystemPrompt 'sys' -UserContent 'user' -Provider $provider -ApiKey $key
        }

        $result.Content      | Should -Be '1|Hello world'
        $result.FinishReason | Should -Be 'end_turn'
        $result.RetryCount   | Should -Be 0
    }

    It 'Returns a non-null error, not $null content, when no block is type text' {
        Mock -ModuleName SubtitleTools -CommandName Invoke-RestMethod -MockWith {
            [PSCustomObject]@{
                content     = @([PSCustomObject]@{ type = 'thinking'; thinking = 'only reasoning, no answer' })
                usage       = [PSCustomObject]@{ input_tokens = 10; output_tokens = 5 }
                stop_reason = 'end_turn'
                model       = 'claude-test'
            }
        }

        $result = InModuleScope SubtitleTools -Parameters @{ modelName = 'claude-test'; baseUrl = 'https://api.anthropic.test/v1'; keyPlain = 'test-key' } {
            param($modelName, $baseUrl, $keyPlain)
            $provider          = [TranslationProvider]::new()
            $provider.Name     = 'Anthropic'
            $provider.Model    = $modelName
            $provider.BaseUrl  = $baseUrl
            $key = ConvertTo-SecureString $keyPlain -AsPlainText -Force
            Invoke-AnthropicTranslation -SystemPrompt 'sys' -UserContent 'user' -Provider $provider -ApiKey $key
        }

        $result.FinishReason | Should -Be 'error'
        $result.Content      | Should -Not -BeNullOrEmpty
    }
}

Describe 'Invoke-GoogleTranslation safety block handling (Bug D)' {
    BeforeAll {
        Mock -ModuleName SubtitleTools -CommandName Start-Sleep -MockWith { }
    }

    It 'Surfaces promptFeedback.blockReason as a non-retryable error when candidates is absent' {
        Mock -ModuleName SubtitleTools -CommandName Invoke-RestMethod -MockWith {
            [PSCustomObject]@{
                promptFeedback = [PSCustomObject]@{ blockReason = 'SAFETY' }
                usageMetadata  = [PSCustomObject]@{ promptTokenCount = 42 }
            }
        }

        $result = InModuleScope SubtitleTools -Parameters @{ modelName = 'gemini-test'; baseUrl = 'https://generativelanguage.googleapis.test/v1'; keyPlain = 'test-key' } {
            param($modelName, $baseUrl, $keyPlain)
            $provider          = [TranslationProvider]::new()
            $provider.Name     = 'Google'
            $provider.Model    = $modelName
            $provider.BaseUrl  = $baseUrl
            $key = ConvertTo-SecureString $keyPlain -AsPlainText -Force
            Invoke-GoogleTranslation -SystemPrompt 'sys' -UserContent 'user' -Provider $provider -ApiKey $key
        }

        $result.FinishReason | Should -Be 'error'
        $result.Content      | Should -Match 'SAFETY'

        # A safety block is a 200 OK with no candidates, not an HTTP error, so it
        # must not trigger the retry loop at all - exactly one call, no sleeps.
        Should -Invoke -ModuleName SubtitleTools -CommandName Invoke-RestMethod -Times 1 -Exactly
        Should -Invoke -ModuleName SubtitleTools -CommandName Start-Sleep -Times 0 -Exactly
    }

    It 'Does not throw on an empty (not absent) candidates array either' {
        Mock -ModuleName SubtitleTools -CommandName Invoke-RestMethod -MockWith {
            [PSCustomObject]@{
                candidates     = @()
                promptFeedback = [PSCustomObject]@{ blockReason = 'OTHER' }
                usageMetadata  = [PSCustomObject]@{ promptTokenCount = 5 }
            }
        }

        {
            InModuleScope SubtitleTools -Parameters @{ modelName = 'gemini-test'; baseUrl = 'https://generativelanguage.googleapis.test/v1'; keyPlain = 'test-key' } {
                param($modelName, $baseUrl, $keyPlain)
                $provider          = [TranslationProvider]::new()
                $provider.Name     = 'Google'
                $provider.Model    = $modelName
                $provider.BaseUrl  = $baseUrl
                $key = ConvertTo-SecureString $keyPlain -AsPlainText -Force
                Invoke-GoogleTranslation -SystemPrompt 'sys' -UserContent 'user' -Provider $provider -ApiKey $key
            }
        } | Should -Not -Throw
    }
}

Describe 'Invoke-GoogleTranslation authentication (Bug H)' {
    BeforeAll {
        Mock -ModuleName SubtitleTools -CommandName Start-Sleep -MockWith { }
    }

    It 'Sends the API key via the x-goog-api-key header and puts no key= in the URI' {
        Mock -ModuleName SubtitleTools -CommandName Invoke-RestMethod -MockWith {
            [PSCustomObject]@{
                candidates    = @([PSCustomObject]@{
                    content      = [PSCustomObject]@{ parts = @([PSCustomObject]@{ text = '1|hi' }) }
                    finishReason = 'STOP'
                })
                usageMetadata = [PSCustomObject]@{ promptTokenCount = 1; candidatesTokenCount = 1 }
            }
        }

        InModuleScope SubtitleTools -Parameters @{ modelName = 'gemini-test'; baseUrl = 'https://generativelanguage.googleapis.test/v1'; keyPlain = 'test-key' } {
            param($modelName, $baseUrl, $keyPlain)
            $provider          = [TranslationProvider]::new()
            $provider.Name     = 'Google'
            $provider.Model    = $modelName
            $provider.BaseUrl  = $baseUrl
            $key = ConvertTo-SecureString $keyPlain -AsPlainText -Force
            Invoke-GoogleTranslation -SystemPrompt 'sys' -UserContent 'user' -Provider $provider -ApiKey $key
        } | Out-Null

        Should -Invoke -ModuleName SubtitleTools -CommandName Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -notmatch 'key=' -and $Headers.ContainsKey('x-goog-api-key') -and $Headers['x-goog-api-key'] -eq 'test-key'
        }
    }
}

Describe 'Invoke-OpenRouterTranslation' {
    BeforeAll {
        Mock -ModuleName SubtitleTools -CommandName Start-Sleep -MockWith { }
    }

    It 'Sends Authorization: Bearer and returns parsed content/token counts from a mocked chat-completions response' {
        Mock -ModuleName SubtitleTools -CommandName Invoke-RestMethod -MockWith {
            [PSCustomObject]@{
                choices = @(
                    [PSCustomObject]@{
                        message       = [PSCustomObject]@{ content = '1|Hello world' }
                        finish_reason = 'stop'
                    }
                )
                usage = [PSCustomObject]@{ prompt_tokens = 12; completion_tokens = 7 }
                model = 'anthropic/claude-sonnet-5'
            }
        }

        $result = InModuleScope SubtitleTools -Parameters @{ modelName = 'anthropic/claude-sonnet-5'; baseUrl = 'https://openrouter.test/api/v1'; keyPlain = 'test-key' } {
            param($modelName, $baseUrl, $keyPlain)
            $provider          = [TranslationProvider]::new()
            $provider.Name     = 'OpenRouter'
            $provider.Model    = $modelName
            $provider.BaseUrl  = $baseUrl
            $key = ConvertTo-SecureString $keyPlain -AsPlainText -Force
            Invoke-OpenRouterTranslation -SystemPrompt 'sys' -UserContent 'user' -Provider $provider -ApiKey $key
        }

        $result.Content      | Should -Be '1|Hello world'
        $result.InputTokens  | Should -Be 12
        $result.OutputTokens | Should -Be 7
        $result.FinishReason | Should -Be 'stop'
        $result.Model        | Should -Be 'anthropic/claude-sonnet-5'
        $result.RetryCount   | Should -Be 0

        Should -Invoke -ModuleName SubtitleTools -CommandName Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Headers.ContainsKey('Authorization') -and $Headers['Authorization'] -eq 'Bearer test-key'
        }
    }

    It 'Sends reasoning effort none when configured' {
        $global:OpenRouterRequestBody = $null
        Mock -ModuleName SubtitleTools -CommandName Invoke-RestMethod -MockWith {
            $global:OpenRouterRequestBody = [System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
            [PSCustomObject]@{
                choices = @([PSCustomObject]@{
                    message = [PSCustomObject]@{ content = '1|Hello' }
                    finish_reason = 'stop'
                })
                usage = [PSCustomObject]@{ prompt_tokens = 1; completion_tokens = 1 }
                model = 'minimax/minimax-m3'
            }
        }

        InModuleScope SubtitleTools {
            $provider = [TranslationProvider]::new()
            $provider.Name = 'OpenRouter'
            $provider.Model = 'minimax/minimax-m3'
            $provider.BaseUrl = 'https://openrouter.test/api/v1'
            $provider.ReasoningEffort = 'none'
            $key = ConvertTo-SecureString 'test-key' -AsPlainText -Force
            Invoke-OpenRouterTranslation -SystemPrompt 'sys' -UserContent 'user' -Provider $provider -ApiKey $key
        } | Out-Null

        $global:OpenRouterRequestBody.reasoning.effort | Should -Be 'none'
        Remove-Variable -Name OpenRouterRequestBody -Scope Global -ErrorAction SilentlyContinue
    }
}

Describe 'Invoke-SubtitleTranslation checkpoint-on-failure and token aggregation (Stage 6)' {
    BeforeEach {
        Mock -ModuleName SubtitleTools -CommandName Start-Sleep -MockWith { }

        # Unprotect-ApiKey uses Windows DPAPI, unavailable on this test host - mock
        # it so Invoke-SubtitleTranslation's decrypt step succeeds everywhere.
        Mock -ModuleName SubtitleTools -CommandName Unprotect-ApiKey -MockWith { 'fake-plain-key' }

        $global:StageSixCallCount = 0
    }

    AfterEach {
        Remove-Variable -Name StageSixCallCount -Scope Global -ErrorAction SilentlyContinue
    }

    It 'Writes the checkpoint with the partial cache AND still throws when a later batch exhausts retries' {
        # First API call (batch 1) succeeds; every call after that (batch 2's
        # initial attempt + all its retries) fails with a retryable 500, so the
        # adapter reports FinishReason = error and $translateBatch throws.
        Mock -ModuleName SubtitleTools -CommandName Invoke-RestMethod -MockWith {
            $global:StageSixCallCount++
            if ($global:StageSixCallCount -eq 1) {
                return [PSCustomObject]@{
                    content     = @([PSCustomObject]@{ type = 'text'; text = '1|Translated First' })
                    usage       = [PSCustomObject]@{ input_tokens = 11; output_tokens = 4 }
                    stop_reason = 'end_turn'
                    model       = 'claude-test'
                }
            }
            $ex = [System.Exception]::new('Internal Server Error')
            $ex | Add-Member -NotePropertyName Response -NotePropertyValue ([PSCustomObject]@{ StatusCode = 500 }) -Force
            throw $ex
        }

        $checkpointPath = Join-Path $TestDrive 'checkpoint.json'

        InModuleScope SubtitleTools -Parameters @{ checkpointPath = $checkpointPath } {
            param($checkpointPath)

            # Built from primitives inside the module's own scope - see the NOTE
            # at the top of this file on why a [TranslationProvider] instance
            # must not cross the InModuleScope boundary.
            $provider                   = [TranslationProvider]::new()
            $provider.Name              = 'Anthropic'
            $provider.Model             = 'claude-test'
            $provider.BaseUrl           = 'https://api.anthropic.test/v1'
            $provider.MaxTokensPerBatch = 1      # forces one entry per batch (maxChars = 4)
            $provider.RateLimitRpm      = 0
            $provider.ApiKeyEncrypted   = 'placeholder-since-Unprotect-ApiKey-is-mocked'

            $session = @{
                Provider       = $provider
                Glossary       = @{}
                Cache          = @{}
                CheckpointPath = $checkpointPath
                ContentContext = $null
            }

            $file = [SubtitleFile]::new()
            $file.Format = 'SRT'

            $e1 = [SubtitleEntry]::new()
            $e1.Index = 1; $e1.Start = [TimeSpan]::Zero;              $e1.End = [TimeSpan]::FromSeconds(1); $e1.Lines = @('First line of dialogue')
            $e2 = [SubtitleEntry]::new()
            $e2.Index = 2; $e2.Start = [TimeSpan]::FromSeconds(1);    $e2.End = [TimeSpan]::FromSeconds(2); $e2.Lines = @('Second line of dialogue')
            $e3 = [SubtitleEntry]::new()
            $e3.Index = 3; $e3.Start = [TimeSpan]::FromSeconds(2);    $e3.End = [TimeSpan]::FromSeconds(3); $e3.Lines = @('Third line of dialogue')
            $file.Entries = @($e1, $e2, $e3)

            { Invoke-SubtitleTranslation -InputObject $file -TargetLanguage 'fa' -Session $session -NoStream -NoSummary } |
                Should -Throw -ExpectedMessage '*API call failed*'

            Test-Path $checkpointPath | Should -BeTrue

            $savedCache = Get-Content $checkpointPath -Raw | ConvertFrom-Json
            $savedProps = $savedCache | Get-Member -MemberType NoteProperty
            $savedProps.Count | Should -Be 1   # only batch 1's entry made it into the cache
        }

        Should -Invoke -ModuleName SubtitleTools -CommandName Invoke-RestMethod -Times 5 -Exactly # 1 success + (1 attempt + 3 retries) failing
    }

    It 'Aggregates InputTokens/OutputTokens across batches into the final log line' {
        Mock -ModuleName SubtitleTools -CommandName Invoke-RestMethod -MockWith {
            $global:StageSixCallCount++
            [PSCustomObject]@{
                content     = @([PSCustomObject]@{ type = 'text'; text = "1|Translated $($global:StageSixCallCount)" })
                usage       = [PSCustomObject]@{ input_tokens = 100; output_tokens = 50 }
                stop_reason = 'end_turn'
                model       = 'claude-test'
            }
        }

        $logPath = Join-Path $TestDrive 'translate.log'

        InModuleScope SubtitleTools -Parameters @{ logPath = $logPath } {
            param($logPath)

            $provider                   = [TranslationProvider]::new()
            $provider.Name              = 'Anthropic'
            $provider.Model             = 'claude-test'
            $provider.BaseUrl           = 'https://api.anthropic.test/v1'
            $provider.MaxTokensPerBatch = 1
            $provider.RateLimitRpm      = 0
            $provider.ApiKeyEncrypted   = 'placeholder-since-Unprotect-ApiKey-is-mocked'

            $session = @{
                Provider       = $provider
                Glossary       = @{}
                Cache          = @{}
                CheckpointPath = $null
                ContentContext = $null
            }

            $file = [SubtitleFile]::new()
            $file.Format = 'SRT'

            $e1 = [SubtitleEntry]::new()
            $e1.Index = 1; $e1.Start = [TimeSpan]::Zero;           $e1.End = [TimeSpan]::FromSeconds(1); $e1.Lines = @('First line of dialogue')
            $e2 = [SubtitleEntry]::new()
            $e2.Index = 2; $e2.Start = [TimeSpan]::FromSeconds(1); $e2.End = [TimeSpan]::FromSeconds(2); $e2.Lines = @('Second line of dialogue')
            $file.Entries = @($e1, $e2)

            $result = Invoke-SubtitleTranslation -InputObject $file -TargetLanguage 'fa' -Session $session -LogPath $logPath -NoStream -NoSummary

            $result.Entries.Count | Should -Be 2

            $logContent = Get-Content $logPath -Raw
            # Two batches of 100/50 tokens each = 200 input / 100 output.
            $logContent | Should -Match 'Tokens: 200/100 tok'
        }

        Should -Invoke -ModuleName SubtitleTools -CommandName Invoke-RestMethod -Times 2 -Exactly
    }
}

Describe 'Test-TranslationTruncated' {
    It 'Recognises <reason> as an output-cap truncation' -ForEach @(
        @{ reason = 'length' }        # OpenAI / OpenRouter
        @{ reason = 'max_tokens' }    # Anthropic
        @{ reason = 'MAX_TOKENS' }    # Google Gemini (upper-case on the wire)
    ) {
        InModuleScope SubtitleTools -Parameters @{ reason = $reason } {
            param($reason)
            Test-TranslationTruncated -FinishReason $reason | Should -BeTrue
        }
    }

    It 'Does not mistake <reason> for a truncation' -ForEach @(
        @{ reason = 'stop' }
        @{ reason = 'end_turn' }
        @{ reason = 'STOP' }
        @{ reason = '' }
        @{ reason = $null }
    ) {
        InModuleScope SubtitleTools -Parameters @{ reason = $reason } {
            param($reason)
            Test-TranslationTruncated -FinishReason $reason | Should -BeFalse
        }
    }
}

Describe 'Truncated-response recovery' {
    # Regression cover for the real-world failure this was written from: a 294-entry
    # file went to google/gemini-3.8-flash via OpenRouter as a single batch, the
    # response stopped after entry 76 because the reasoning tokens exhausted
    # max_tokens, and entries 77-294 were silently written out as untranslated
    # English. finish_reason was 'length' on a 200 OK, so nothing threw.

    BeforeAll {
        # Held as source text, not a live scriptblock: it is rebuilt with
        # [scriptblock]::Create inside InModuleScope so that [TranslationProvider]
        # and [SubtitleFile] resolve in the module's own session state - see the
        # NOTE at the top of this file.
        $TranslateHelper = {
            param($entryCount, $maxEntriesPerBatch)

            $provider                    = [TranslationProvider]::new()
            $provider.Name               = 'OpenRouter'
            $provider.Model              = 'google/gemini-3.8-flash'
            $provider.BaseUrl            = 'https://openrouter.test/api/v1'
            $provider.MaxTokensPerBatch  = 10000
            $provider.MaxEntriesPerBatch = $maxEntriesPerBatch
            $provider.RateLimitRpm       = 0
            $provider.ApiKeyEncrypted    = 'placeholder-since-Unprotect-ApiKey-is-mocked'

            $session = @{
                Provider       = $provider
                Glossary       = @{}
                Cache          = @{}
                CheckpointPath = $null
                ContentContext = $null
            }

            $file        = [SubtitleFile]::new()
            $file.Format = 'SRT'
            $entries     = foreach ($i in 1..$entryCount) {
                $e = [SubtitleEntry]::new()
                $e.Index = $i
                $e.Start = [TimeSpan]::FromSeconds($i)
                $e.End   = [TimeSpan]::FromSeconds($i + 1)
                $e.Lines = @("Source line $i")
                $e
            }
            $file.Entries = @($entries)

            # -NoStream keeps these cases on the buffered Invoke-RestMethod path that
            # they mock. Without it the adapter would first attempt a real streaming
            # request to the fake host and only then fall back - correct behaviour,
            # but it makes the test depend on a DNS failure. Streaming is covered
            # separately, against a mocked Invoke-TranslationApiStream.
            # -NoSummary only keeps the end-of-run console block out of the Pester
            # transcript; the summary object is attached either way and is covered by
            # the 'Translation run summary' Describe below.
            $result = Invoke-SubtitleTranslation -InputObject $file -TargetLanguage 'fa' -Session $session -NoStream -NoSummary
            return @{ Result = $result; Session = $session }
        }.ToString()
    }

    BeforeEach {
        Mock -ModuleName SubtitleTools -CommandName Start-Sleep -MockWith { }
        Mock -ModuleName SubtitleTools -CommandName Unprotect-ApiKey -MockWith { 'fake-plain-key' }
        $global:TruncCallCount = 0
    }

    AfterEach {
        Remove-Variable -Name TruncCallCount -Scope Global -ErrorAction SilentlyContinue
    }

    It 'Re-asks for the cut-off entries instead of writing out untranslated source text' {
        # Emits only the first 2 numbered lines with finish_reason = length on the
        # first call, then answers every follow-up call in full.
        Mock -ModuleName SubtitleTools -CommandName Invoke-RestMethod -MockWith {
            $global:TruncCallCount++
            $request   = [System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
            $requested = @($request.messages[1].content -split "`n").Count

            if ($global:TruncCallCount -eq 1) {
                # Entry 1 completed; entry 2 was still being written when the budget
                # ran out, so it lands as a half-word. Entries 3-5 never appear.
                $content = "1|XLAT-1`n2|XLAT-HALFWRIT"
                $finish  = 'length'
            } else {
                $content = (1..$requested | ForEach-Object { "$_|XLAT-$_" }) -join "`n"
                $finish  = 'stop'
            }

            [PSCustomObject]@{
                choices = @([PSCustomObject]@{
                    message       = [PSCustomObject]@{ content = $content }
                    finish_reason = $finish
                })
                usage = [PSCustomObject]@{ prompt_tokens = 10; completion_tokens = 5 }
                model = 'google/gemini-3.8-flash'
            }
        }

        InModuleScope SubtitleTools -Parameters @{ helper = $TranslateHelper } {
            param($helper)
            $outcome = & ([scriptblock]::Create($helper)) 5 5 -WarningAction SilentlyContinue

            $outcome.Result.Entries.Count | Should -Be 5
            foreach ($entry in $outcome.Result.Entries) {
                # '^XLAT-\d+$' rather than '^XLAT-': it must reject BOTH the original
                # bug's leftover "Source line N" AND the half-written "XLAT-HALFWRIT"
                # that a truncated response's final line carries.
                $entry.Lines[0] | Should -Match '^XLAT-\d+$'
            }
        }

        # 1 truncated call + 2 half-size retries covering the 4 unresolved entries
        # (entry 2 is discarded too: a truncated response's last line is a partial).
        Should -Invoke -ModuleName SubtitleTools -CommandName Invoke-RestMethod -Times 3 -Exactly
    }

    It 'Caps a batch at MaxEntriesPerBatch even when the whole file fits the character budget' {
        # The original bug needed no truncation to occur at all: 294 short entries
        # fit under MaxTokensPerBatch*4 chars, so the planner made ONE call asking
        # for 294 translated lines. MaxEntriesPerBatch is what bounds that.
        Mock -ModuleName SubtitleTools -CommandName Invoke-RestMethod -MockWith {
            $request   = [System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
            $requested = @($request.messages[1].content -split "`n").Count
            $requested | Should -BeLessOrEqual 3

            [PSCustomObject]@{
                choices = @([PSCustomObject]@{
                    message       = [PSCustomObject]@{ content = ((1..$requested | ForEach-Object { "$_|XLAT-$_" }) -join "`n") }
                    finish_reason = 'stop'
                })
                usage = [PSCustomObject]@{ prompt_tokens = 10; completion_tokens = 5 }
                model = 'google/gemini-3.8-flash'
            }
        }

        InModuleScope SubtitleTools -Parameters @{ helper = $TranslateHelper } {
            param($helper)
            $outcome = & ([scriptblock]::Create($helper)) 10 3
            $outcome.Result.Entries.Count | Should -Be 10
        }

        # 10 entries at 3 per batch = 4 calls (3/3/3/1), not 1 call for all 10.
        Should -Invoke -ModuleName SubtitleTools -CommandName Invoke-RestMethod -Times 4 -Exactly
    }

    It 'Falls back to source text without caching it, so a resume can still fix the entry' {
        # Model never returns a parseable numbered line. A single entry cannot be
        # split further, so it exhausts immediately and falls back.
        Mock -ModuleName SubtitleTools -CommandName Invoke-RestMethod -MockWith {
            [PSCustomObject]@{
                choices = @([PSCustomObject]@{
                    message       = [PSCustomObject]@{ content = 'I am sorry, I cannot help with that.' }
                    finish_reason = 'stop'
                })
                usage = [PSCustomObject]@{ prompt_tokens = 10; completion_tokens = 5 }
                model = 'google/gemini-3.8-flash'
            }
        }

        InModuleScope SubtitleTools -Parameters @{ helper = $TranslateHelper } {
            param($helper)
            $outcome = & ([scriptblock]::Create($helper)) 1 5 -WarningAction SilentlyContinue

            $outcome.Result.Entries[0].Lines[0] | Should -Be 'Source line 1'

            # The cache must stay empty. Caching an untranslated fallback would make
            # it a permanent cache hit, so re-running or resuming from a checkpoint
            # could never repair the entry.
            $outcome.Session.Cache.Count | Should -Be 0
        }
    }

    It 'Warns on the warning stream when entries end up untranslated' {
        Mock -ModuleName SubtitleTools -CommandName Invoke-RestMethod -MockWith {
            [PSCustomObject]@{
                choices = @([PSCustomObject]@{
                    message       = [PSCustomObject]@{ content = 'no numbered lines here' }
                    finish_reason = 'stop'
                })
                usage = [PSCustomObject]@{ prompt_tokens = 1; completion_tokens = 1 }
                model = 'google/gemini-3.8-flash'
            }
        }

        $warnings = InModuleScope SubtitleTools -Parameters @{ helper = $TranslateHelper } {
            param($helper)
            & ([scriptblock]::Create($helper)) 1 5 | Out-Null
        } 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }

        # A partially-translated file plays fine and reads fine - the only signal the
        # user gets is this warning, so it must reach the warning stream. Matched on
        # the end-of-run summary's own wording, not the generic "could not be
        # translated" phrase that the per-batch log line also emits.
        ($warnings -join ' ') | Should -Match 'kept their source text'
        ($warnings -join ' ') | Should -Match 'MaxEntriesPerBatch'
    }
}

Describe 'Translation run summary' {
    # The run's own facts - provider, batches, API calls, tokens, what came from
    # cache, what never came back - are not recoverable from the translated file, so
    # they are attached to it as .TranslationSummary and rendered as a console block.

    BeforeAll {
        # Source text, rebuilt inside InModuleScope - see the NOTE at the top of file.
        $SummaryHelper = {
            param($entryCount, $maxEntriesPerBatch, $existingSession, [switch] $ShowSummary)

            if ($existingSession) {
                $session = $existingSession
            } else {
                $provider                    = [TranslationProvider]::new()
                $provider.Name               = 'OpenRouter'
                $provider.Model              = 'google/gemini-3.8-flash'
                $provider.BaseUrl            = 'https://openrouter.test/api/v1'
                $provider.MaxTokensPerBatch  = 10000
                $provider.MaxEntriesPerBatch = $maxEntriesPerBatch
                $provider.RateLimitRpm       = 0
                $provider.ApiKeyEncrypted    = 'placeholder-since-Unprotect-ApiKey-is-mocked'

                $session = @{
                    Provider       = $provider
                    Glossary       = @{}
                    Cache          = @{}
                    CheckpointPath = $null
                    ContentContext = $null
                }
            }

            $file        = [SubtitleFile]::new()
            $file.Format = 'SRT'
            $entries     = foreach ($i in 1..$entryCount) {
                $e = [SubtitleEntry]::new()
                $e.Index = $i
                $e.Start = [TimeSpan]::FromSeconds($i)
                $e.End   = [TimeSpan]::FromSeconds($i + 1)
                $e.Lines = @("Source line $i")
                $e
            }
            $file.Entries = @($entries)

            $params = @{
                InputObject    = $file
                TargetLanguage = 'fa'
                Session        = $session
                NoStream       = $true
            }
            if (-not $ShowSummary) { $params['NoSummary'] = $true }

            $result = Invoke-SubtitleTranslation @params
            return @{ Result = $result; Session = $session }
        }.ToString()
    }

    BeforeEach {
        Mock -ModuleName SubtitleTools -CommandName Start-Sleep     -MockWith { }
        Mock -ModuleName SubtitleTools -CommandName Unprotect-ApiKey -MockWith { 'fake-plain-key' }
    }

    Context 'A run that completes normally' {
        BeforeEach {
            Mock -ModuleName SubtitleTools -CommandName Invoke-RestMethod -MockWith {
                $request   = [System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
                $requested = @($request.messages[1].content -split "`n").Count

                [PSCustomObject]@{
                    choices = @([PSCustomObject]@{
                        message       = [PSCustomObject]@{ content = ((1..$requested | ForEach-Object { "$_|XLAT-$_" }) -join "`n") }
                        finish_reason = 'stop'
                    })
                    usage = [PSCustomObject]@{ prompt_tokens = 10; completion_tokens = 5 }
                    model = 'google/gemini-3.8-flash'
                }
            }
        }

        It 'Attaches a TranslationSummary describing the provider, the work done, and the tokens spent' {
            InModuleScope SubtitleTools -Parameters @{ helper = $SummaryHelper } {
                param($helper)
                $outcome = & ([scriptblock]::Create($helper)) 10 3
                $s = $outcome.Result.TranslationSummary

                $s | Should -Not -BeNullOrEmpty
                $s.PSObject.TypeNames | Should -Contain 'SubtitleTools.TranslationSummary'

                $s.Provider          | Should -Be 'OpenRouter'
                $s.Model             | Should -Be 'google/gemini-3.8-flash'
                $s.TargetLanguage    | Should -Be 'fa'
                $s.SourceLanguage    | Should -Be 'auto-detect'
                $s.Format            | Should -Be 'SRT'

                $s.Entries           | Should -Be 10
                $s.TranslatedEntries | Should -Be 10
                $s.CachedEntries     | Should -Be 0
                $s.UnresolvedEntries | Should -Be 0

                # 10 entries capped at 3 per call = 4 batches, one API call each.
                $s.Batches           | Should -Be 4
                $s.ApiCalls          | Should -Be 4
                $s.Retries           | Should -Be 0
                $s.TruncatedBatches  | Should -Be 0

                # 4 calls x 10 prompt / 5 completion tokens.
                $s.InputTokens       | Should -Be 40
                $s.OutputTokens      | Should -Be 20
                $s.TotalTokens       | Should -Be 60

                # 9 x 'Source line N' (13) + 'Source line 10' (14); each entry comes
                # back as 'XLAT-n' (6). Counted on the text itself, never on the
                # '<NL>'-joined wire form.
                $s.SourceCharacters  | Should -Be 131
                $s.OutputCharacters  | Should -Be 60

                $s.Streaming         | Should -BeFalse   # -NoStream was passed
                $s.Primed            | Should -BeFalse
                $s.Duration          | Should -BeOfType [timespan]
            }
        }

        It 'Counts entries served from the session cache separately from entries the API translated' {
            InModuleScope SubtitleTools -Parameters @{ helper = $SummaryHelper } {
                param($helper)
                $run = [scriptblock]::Create($helper)

                $first  = & $run 10 3
                $second = & $run 10 3 $first.Session   # same session, same source text

                $first.Result.TranslationSummary.CachedEntries      | Should -Be 0
                $first.Result.TranslationSummary.TranslatedEntries  | Should -Be 10

                # Every entry is already cached, so the second run must report zero
                # API calls and zero tokens - not silently re-bill them.
                $second.Result.TranslationSummary.CachedEntries     | Should -Be 10
                $second.Result.TranslationSummary.TranslatedEntries | Should -Be 0
                $second.Result.TranslationSummary.ApiCalls          | Should -Be 0
                $second.Result.TranslationSummary.TotalTokens       | Should -Be 0
                $second.Result.TranslationSummary.Batches           | Should -Be 4
            }
        }

        It 'Prints the summary block by default and stays silent under -NoSummary' {
            Mock -ModuleName SubtitleTools -CommandName Write-TranslationSummary -MockWith { }

            InModuleScope SubtitleTools -Parameters @{ helper = $SummaryHelper } {
                param($helper)
                & ([scriptblock]::Create($helper)) 3 3 $null -ShowSummary | Out-Null
            }
            Should -Invoke -ModuleName SubtitleTools -CommandName Write-TranslationSummary -Times 1 -Exactly

            InModuleScope SubtitleTools -Parameters @{ helper = $SummaryHelper } {
                param($helper)
                & ([scriptblock]::Create($helper)) 3 3 | Out-Null
            }
            # Still 1: the -NoSummary run must not have added a second call.
            Should -Invoke -ModuleName SubtitleTools -CommandName Write-TranslationSummary -Times 1 -Exactly
        }
    }

    It 'Reports unresolved entries and the truncated batch that caused them' {
        # Truncated with nothing parseable in it, on every call including the retries,
        # so the batch exhausts its split depth and gives up.
        Mock -ModuleName SubtitleTools -CommandName Invoke-RestMethod -MockWith {
            [PSCustomObject]@{
                choices = @([PSCustomObject]@{
                    message       = [PSCustomObject]@{ content = 'thinking about it' }
                    finish_reason = 'length'
                })
                usage = [PSCustomObject]@{ prompt_tokens = 10; completion_tokens = 5 }
                model = 'google/gemini-3.8-flash'
            }
        }

        InModuleScope SubtitleTools -Parameters @{ helper = $SummaryHelper } {
            param($helper)
            $WarningPreference = 'SilentlyContinue'
            $outcome = & ([scriptblock]::Create($helper)) 2 2
            $s = $outcome.Result.TranslationSummary

            $s.UnresolvedEntries | Should -Be 2
            $s.TranslatedEntries | Should -Be 0
            $s.TruncatedBatches  | Should -Be 1
            # The initial call plus one single-entry retry per half.
            $s.ApiCalls          | Should -Be 3
        }
    }

    It 'Registers display formatting for SubtitleFile and the summary, so neither dumps raw properties' {
        # Without FormatsToProcess a returned SubtitleFile renders its entire Entries
        # array - which is what made the old end-of-run output unreadable.
        (Get-FormatData -TypeName 'SubtitleFile')                        | Should -Not -BeNullOrEmpty
        (Get-FormatData -TypeName 'SubtitleTools.TranslationSummary')    | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-OpenRouterModel' {
    It 'Parses a mocked /models payload into the right shape, converting per-token prices to per-million' {
        Mock -ModuleName SubtitleTools -CommandName Invoke-RestMethod -MockWith {
            [PSCustomObject]@{
                data = @(
                    [PSCustomObject]@{
                        id             = 'anthropic/claude-sonnet-5'
                        name           = 'Claude Sonnet 5'
                        context_length = 1000000
                        pricing        = [PSCustomObject]@{ prompt = '0.000003'; completion = '0.000015' }
                        top_provider   = [PSCustomObject]@{ max_completion_tokens = 128000 }
                    }
                    [PSCustomObject]@{
                        id             = 'openai/gpt-4o'
                        name           = 'GPT-4o'
                        context_length = 128000
                        pricing        = [PSCustomObject]@{ prompt = '0'; completion = '0' }
                        top_provider   = [PSCustomObject]@{ max_completion_tokens = $null }
                    }
                )
                total_count = 2
            }
        }

        $results = InModuleScope SubtitleTools {
            Get-OpenRouterModel -BaseUrl 'https://openrouter.test/api/v1'
        }

        $results.Count | Should -Be 2

        $sonnet = $results | Where-Object { $_.Id -eq 'anthropic/claude-sonnet-5' }
        $sonnet.Name                   | Should -Be 'Claude Sonnet 5'
        $sonnet.ContextLength          | Should -Be 1000000
        $sonnet.MaxOutputTokens        | Should -Be 128000
        $sonnet.PromptPricePerMTok     | Should -Be 3
        $sonnet.CompletionPricePerMTok | Should -Be 15

        $gpt4o = $results | Where-Object { $_.Id -eq 'openai/gpt-4o' }
        $gpt4o.MaxOutputTokens        | Should -BeNullOrEmpty
        $gpt4o.PromptPricePerMTok     | Should -Be 0
        $gpt4o.CompletionPricePerMTok | Should -Be 0

        Should -Invoke -ModuleName SubtitleTools -CommandName Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'Get' -and $Uri -eq 'https://openrouter.test/api/v1/models'
        }
    }

    It 'Filters results by -Filter against id and name' {
        Mock -ModuleName SubtitleTools -CommandName Invoke-RestMethod -MockWith {
            [PSCustomObject]@{
                data = @(
                    [PSCustomObject]@{
                        id             = 'anthropic/claude-sonnet-5'
                        name           = 'Claude Sonnet 5'
                        context_length = 1000000
                        pricing        = [PSCustomObject]@{ prompt = '0.000003'; completion = '0.000015' }
                        top_provider   = [PSCustomObject]@{ max_completion_tokens = 128000 }
                    }
                    [PSCustomObject]@{
                        id             = 'openai/gpt-4o'
                        name           = 'GPT-4o'
                        context_length = 128000
                        pricing        = [PSCustomObject]@{ prompt = '0.0000025'; completion = '0.00001' }
                        top_provider   = [PSCustomObject]@{ max_completion_tokens = 16384 }
                    }
                )
            }
        }

        $results = InModuleScope SubtitleTools {
            Get-OpenRouterModel -Filter 'anthropic/*' -BaseUrl 'https://openrouter.test/api/v1'
        }

        $results.Count | Should -Be 1
        $results[0].Id | Should -Be 'anthropic/claude-sonnet-5'

        Should -Invoke -ModuleName SubtitleTools -CommandName Invoke-RestMethod -Times 1 -Exactly
    }
}

Describe 'Streaming path' {
    BeforeAll {
        # Drives one batch through Invoke-SubtitleTranslation. Streaming is on by
        # default; -NoStream is appended by the tests that want the buffered path.
        $StreamHelper = {
            param($noStream)

            $provider                    = [TranslationProvider]::new()
            $provider.Name               = 'OpenRouter'
            $provider.Model              = 'google/gemini-3.8-flash'
            $provider.BaseUrl            = 'https://openrouter.test/api/v1'
            $provider.MaxTokensPerBatch  = 10000
            $provider.MaxEntriesPerBatch = 40
            $provider.RateLimitRpm       = 0
            $provider.ApiKeyEncrypted    = 'placeholder-since-Unprotect-ApiKey-is-mocked'

            $session = @{
                Provider       = $provider
                Glossary       = @{}
                Cache          = @{}
                CheckpointPath = $null
                ContentContext = $null
            }

            $file        = [SubtitleFile]::new()
            $file.Format = 'SRT'
            $e = [SubtitleEntry]::new()
            $e.Index = 1; $e.Start = [TimeSpan]::Zero; $e.End = [TimeSpan]::FromSeconds(1); $e.Lines = @('Source line 1')
            $file.Entries = @($e)

            if ($noStream) {
                Invoke-SubtitleTranslation -InputObject $file -TargetLanguage 'fa' -Session $session -NoStream -NoSummary
            } else {
                Invoke-SubtitleTranslation -InputObject $file -TargetLanguage 'fa' -Session $session -NoSummary
            }
        }.ToString()
    }

    BeforeEach {
        Mock -ModuleName SubtitleTools -CommandName Start-Sleep     -MockWith { }
        Mock -ModuleName SubtitleTools -CommandName Unprotect-ApiKey -MockWith { 'fake-plain-key' }
    }

    Context 'Invoke-TranslationStreamAttempt fallback policy' {
        It 'Returns the adapter-shaped result when the stream succeeds' {
            Mock -ModuleName SubtitleTools -CommandName Invoke-TranslationApiStream -MockWith {
                @{ Success = $true; Content = '1|hi'; InputTokens = 9; OutputTokens = 4
                   FinishReason = 'stop'; StatusCode = 200; ErrorMessage = $null }
            }

            $result = InModuleScope SubtitleTools {
                Invoke-TranslationStreamAttempt -Uri 'https://x.test/v1/chat/completions' `
                    -Body @{ model = 'm'; messages = @() } -Shape 'OpenAI' `
                    -ProviderLabel 'OpenRouter' -Model 'm' -StreamCallback { }
            }

            $result.Content      | Should -Be '1|hi'
            $result.InputTokens  | Should -Be 9
            $result.OutputTokens | Should -Be 4
            $result.FinishReason | Should -Be 'stop'
        }

        It 'Asks for stream + usage on the OpenAI shape, and only stream on Anthropic' {
            Mock -ModuleName SubtitleTools -CommandName Invoke-TranslationApiStream -MockWith {
                @{ Success = $true; Content = '1|hi'; InputTokens = 1; OutputTokens = 1
                   FinishReason = 'stop'; StatusCode = 200; ErrorMessage = $null }
            }

            InModuleScope SubtitleTools {
                Invoke-TranslationStreamAttempt -Uri 'https://x.test/v1/chat/completions' `
                    -Body @{ model = 'm' } -Shape 'OpenAI' -ProviderLabel 'OpenRouter' -Model 'm' -StreamCallback { } | Out-Null
                Invoke-TranslationStreamAttempt -Uri 'https://x.test/v1/messages' `
                    -Body @{ model = 'm' } -Shape 'Anthropic' -ProviderLabel 'Anthropic' -Model 'm' -StreamCallback { } | Out-Null
            }

            # Without stream_options.include_usage an OpenAI-compatible endpoint sends
            # no usage block at all and every token count comes back zero.
            Should -Invoke -ModuleName SubtitleTools -CommandName Invoke-TranslationApiStream -Times 1 -Exactly -ParameterFilter {
                $Shape -eq 'OpenAI' -and $Body['stream'] -eq $true -and $Body['stream_options'].include_usage -eq $true
            }
            Should -Invoke -ModuleName SubtitleTools -CommandName Invoke-TranslationApiStream -Times 1 -Exactly -ParameterFilter {
                $Shape -eq 'Anthropic' -and $Body['stream'] -eq $true -and -not $Body.ContainsKey('stream_options')
            }
        }

        It 'Returns $null so the caller falls back when <case>' -ForEach @(
            @{ case = 'the transport failed with no HTTP status'; status = $null }
            @{ case = 'the provider returned 429';                status = 429 }
            @{ case = 'the provider returned 503';                status = 503 }
        ) {
            Mock -ModuleName SubtitleTools -CommandName Invoke-TranslationApiStream -MockWith {
                @{ Success = $false; Content = ''; InputTokens = 0; OutputTokens = 0
                   FinishReason = $null; StatusCode = $status; ErrorMessage = 'nope' }
            }.GetNewClosure()

            $result = InModuleScope SubtitleTools {
                Invoke-TranslationStreamAttempt -Uri 'https://x.test/v1/chat/completions' `
                    -Body @{ model = 'm' } -Shape 'OpenAI' -ProviderLabel 'OpenRouter' -Model 'm' -StreamCallback { }
            }

            # 429/5xx must reach the buffered path, whose backoff-retry loop handles
            # them; a transport failure must not be mistaken for a provider rejection.
            $result | Should -BeNullOrEmpty
        }

        It 'Reports a 401 as an error instead of re-sending it on the buffered path' {
            Mock -ModuleName SubtitleTools -CommandName Invoke-TranslationApiStream -MockWith {
                @{ Success = $false; Content = ''; InputTokens = 0; OutputTokens = 0
                   FinishReason = $null; StatusCode = 401; ErrorMessage = 'invalid api key' }
            }

            $result = InModuleScope SubtitleTools {
                Invoke-TranslationStreamAttempt -Uri 'https://x.test/v1/chat/completions' `
                    -Body @{ model = 'm' } -Shape 'OpenAI' -ProviderLabel 'OpenRouter' -Model 'm' -StreamCallback { }
            }

            $result              | Should -Not -BeNullOrEmpty
            $result.FinishReason | Should -Be 'error'
            $result.Content      | Should -Be 'invalid api key'
        }
    }

    Context 'Wiring through Invoke-SubtitleTranslation' {
        It 'Streams by default and never reaches the buffered request' {
            Mock -ModuleName SubtitleTools -CommandName Invoke-TranslationApiStream -MockWith {
                # Feed the caller two deltas, the way a real stream would.
                if ($OnDelta) {
                    & $OnDelta "1|Trans" @{ InputTokens = 0; OutputTokens = 0 }
                    & $OnDelta "1|Translated`n" @{ InputTokens = 0; OutputTokens = 0 }
                }
                @{ Success = $true; Content = "1|Translated`n"; InputTokens = 20; OutputTokens = 10
                   FinishReason = 'stop'; StatusCode = 200; ErrorMessage = $null }
            }
            Mock -ModuleName SubtitleTools -CommandName Invoke-RestMethod -MockWith { throw 'buffered path must not be used' }

            $result = InModuleScope SubtitleTools -Parameters @{ helper = $StreamHelper } {
                param($helper)
                & ([scriptblock]::Create($helper)) $false
            }

            $result.Entries[0].Lines[0] | Should -Be 'Translated'
            Should -Invoke -ModuleName SubtitleTools -CommandName Invoke-TranslationApiStream -Times 1 -Exactly
            Should -Invoke -ModuleName SubtitleTools -CommandName Invoke-RestMethod -Times 0 -Exactly
        }

        It 'Uses the buffered request and never opens a stream when -NoStream is given' {
            Mock -ModuleName SubtitleTools -CommandName Invoke-TranslationApiStream -MockWith { throw 'streaming must not be used' }
            Mock -ModuleName SubtitleTools -CommandName Invoke-RestMethod -MockWith {
                [PSCustomObject]@{
                    choices = @([PSCustomObject]@{
                        message       = [PSCustomObject]@{ content = '1|Buffered' }
                        finish_reason = 'stop'
                    })
                    usage = [PSCustomObject]@{ prompt_tokens = 20; completion_tokens = 10 }
                    model = 'google/gemini-3.8-flash'
                }
            }

            $result = InModuleScope SubtitleTools -Parameters @{ helper = $StreamHelper } {
                param($helper)
                & ([scriptblock]::Create($helper)) $true
            }

            $result.Entries[0].Lines[0] | Should -Be 'Buffered'
            Should -Invoke -ModuleName SubtitleTools -CommandName Invoke-TranslationApiStream -Times 0 -Exactly
            Should -Invoke -ModuleName SubtitleTools -CommandName Invoke-RestMethod -Times 1 -Exactly
        }

        It 'Falls back to the buffered request, still producing a translation, when streaming is unavailable' {
            Mock -ModuleName SubtitleTools -CommandName Invoke-TranslationApiStream -MockWith {
                @{ Success = $false; Content = ''; InputTokens = 0; OutputTokens = 0
                   FinishReason = $null; StatusCode = $null; ErrorMessage = 'no SSE through this proxy' }
            }
            Mock -ModuleName SubtitleTools -CommandName Invoke-RestMethod -MockWith {
                [PSCustomObject]@{
                    choices = @([PSCustomObject]@{
                        message       = [PSCustomObject]@{ content = '1|Recovered' }
                        finish_reason = 'stop'
                    })
                    usage = [PSCustomObject]@{ prompt_tokens = 20; completion_tokens = 10 }
                    model = 'google/gemini-3.8-flash'
                }
            }

            $result = InModuleScope SubtitleTools -Parameters @{ helper = $StreamHelper } {
                param($helper)
                & ([scriptblock]::Create($helper)) $false
            }

            # Streaming is a progress nicety - it must never be why a translation fails.
            $result.Entries[0].Lines[0] | Should -Be 'Recovered'
            Should -Invoke -ModuleName SubtitleTools -CommandName Invoke-TranslationApiStream -Times 1 -Exactly
            Should -Invoke -ModuleName SubtitleTools -CommandName Invoke-RestMethod -Times 1 -Exactly
        }
    }

    Context 'Live progress reporting' {
        It 'Counts only newline-terminated numbered lines, and flags estimated token counts' {
            Mock -ModuleName SubtitleTools -CommandName Invoke-TranslationApiStream -MockWith {
                if ($OnDelta) {
                    & $OnDelta "1|alpha"          @{ InputTokens = 0; OutputTokens = 0 }   # line 1 incomplete
                    & $OnDelta "1|alpha`n2|be"    @{ InputTokens = 0; OutputTokens = 0 }   # line 1 done
                    & $OnDelta "1|alpha`n2|beta`n" @{ InputTokens = 7; OutputTokens = 9 }  # both done, real usage
                }
                @{ Success = $true; Content = "1|alpha`n2|beta`n"; InputTokens = 7; OutputTokens = 9
                   FinishReason = 'stop'; StatusCode = 200; ErrorMessage = $null }
            }

            $reports = InModuleScope SubtitleTools {
                $seen = [System.Collections.Generic.List[hashtable]]::new()

                $provider         = [TranslationProvider]::new()
                $provider.Name    = 'OpenRouter'
                $provider.Model   = 'm'
                $provider.BaseUrl = 'https://openrouter.test/api/v1'
                $key = ConvertTo-SecureString 'k' -AsPlainText -Force

                Invoke-TranslationBatchRequest -Texts @('a', 'b') -Provider $provider -ApiKey $key `
                    -TargetLanguage 'fa' -OnLiveProgress { param($live) $seen.Add($live) } | Out-Null

                , $seen.ToArray()
            }

            # The throttle drops updates less than 200ms apart, so only the count and
            # shape of what does get through is asserted, not how many arrived.
            $reports.Count      | Should -BeGreaterThan 0
            $reports[0].LinesDone       | Should -Be 0      # "1|alpha" has no newline yet
            $reports[0].Expected        | Should -Be 2
            $reports[0].Depth           | Should -Be 0
            $reports[0].OutputEstimated | Should -BeTrue    # no usage reported yet
        }
    }

    Context 'Reasoning field spellings' {
        # No two providers spell this the same way, and reading only one of them is how
        # the thinking phase silently never fired on OpenRouter.
        It "Reads DeepSeek's flat reasoning_content" {
            InModuleScope SubtitleTools {
                Get-TranslationStreamReasoning -Delta ([PSCustomObject]@{ reasoning_content = 'weighing it up' })
            } | Should -Be 'weighing it up'
        }

        It "Reads OpenRouter's flat reasoning" {
            InModuleScope SubtitleTools {
                Get-TranslationStreamReasoning -Delta ([PSCustomObject]@{ reasoning = 'weighing it up' })
            } | Should -Be 'weighing it up'
        }

        It "Concatenates the text of OpenRouter's structured reasoning_details" {
            InModuleScope SubtitleTools {
                Get-TranslationStreamReasoning -Delta ([PSCustomObject]@{
                    reasoning_details = @(
                        [PSCustomObject]@{ type = 'reasoning.text'; text = 'first ' }
                        [PSCustomObject]@{ type = 'reasoning.text'; text = 'second' }
                    )
                })
            } | Should -Be 'first second'
        }

        It 'Falls back to a reasoning_details summary when there is no text' {
            InModuleScope SubtitleTools {
                Get-TranslationStreamReasoning -Delta ([PSCustomObject]@{
                    reasoning_details = @([PSCustomObject]@{ type = 'reasoning.summary'; summary = 'considered the tone' })
                })
            } | Should -Be 'considered the tone'
        }

        It 'Returns empty, not null, for reasoning that is only an encrypted blob' {
            # The model IS thinking; there is simply nothing readable to count. The
            # caller still needs to hear about it, so this must not be null.
            $reasoning = InModuleScope SubtitleTools {
                Get-TranslationStreamReasoning -Delta ([PSCustomObject]@{
                    reasoning_details = @([PSCustomObject]@{ type = 'reasoning.encrypted'; data = 'AQIDBA==' })
                })
            }

            $reasoning | Should -Not -Be $null
            $reasoning | Should -BeExactly ''
        }

        It 'Returns null for a delta that carries no reasoning at all' {
            InModuleScope SubtitleTools {
                Get-TranslationStreamReasoning -Delta ([PSCustomObject]@{ content = '1|alpha' })
            } | Should -Be $null
        }
    }

    Context 'Reasoning phase reporting' {
        BeforeAll {
            # Collects every OnDelta report a canned SSE body produces, plus the trace
            # of which phase each one claimed: T = thinking, C = content.
            $DecodeSse = {
                param($body, $shape)

                $seen = [System.Collections.Generic.List[hashtable]]::new()

                $decoded = InModuleScope SubtitleTools -Parameters @{ body = $body; shape = $shape; seen = $seen } {
                    param($body, $shape, $seen)

                    $reader = [System.IO.StringReader]::new($body)
                    try {
                        Read-TranslationSseStream -Reader $reader -Shape $shape -OnDelta {
                            param($accumulated, $counters)
                            $seen.Add(@{
                                Reasoning       = [bool]$counters.Reasoning
                                ReasoningLength = [int]$counters.ReasoningLength
                                Accumulated     = $accumulated
                            })
                        }
                    } finally {
                        $reader.Dispose()
                    }
                }

                @{
                    Decoded = $decoded
                    Reports = $seen
                    Trace   = -join ($seen | ForEach-Object { if ($_.Reasoning) { 'T' } else { 'C' } })
                }
            }.ToString()
        }

        It 'Reports the thinking phase, with a growing char count, before any content' {
            $body = @'
data: {"choices":[{"index":0,"delta":{"reasoning_content":"let me think"}}]}
data: {"choices":[{"index":0,"delta":{"reasoning_content":" harder"}}]}
data: {"choices":[{"index":0,"delta":{"content":"1|alpha\n"}}]}
data: [DONE]
'@

            $run = & ([scriptblock]::Create($DecodeSse)) $body 'OpenAI'

            $thinking = @($run.Reports | Where-Object { $_.Reasoning })
            $thinking.Count             | Should -Be 2
            $thinking[0].ReasoningLength | Should -Be 12   # "let me think"
            $thinking[1].ReasoningLength | Should -Be 19   # + " harder"
            # Nothing visible has been produced yet - that is the whole point.
            $thinking[0].Accumulated    | Should -BeExactly ''
            $thinking[1].Accumulated    | Should -BeExactly ''
        }

        It 'Never re-raises the thinking phase once content has started' {
            # The trailing frames are the ones that caused this: an OpenAI-shape stream
            # ends with a finish_reason chunk carrying an empty delta and then a
            # usage-only chunk with no choices at all. Keying the thinking phase off
            # "reasoning was seen at some point" reported both as thinking, which sent
            # the caller's progress bar backwards at the end of every batch.
            $body = @'
data: {"choices":[{"index":0,"delta":{"reasoning_content":"thinking"}}]}
data: {"choices":[{"index":0,"delta":{"content":"1|alpha\n"}}]}
data: {"choices":[{"index":0,"delta":{"content":"2|beta\n"}}]}
data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}
data: {"choices":[],"usage":{"prompt_tokens":11,"completion_tokens":7}}
data: [DONE]
'@

            $run = & ([scriptblock]::Create($DecodeSse)) $body 'OpenAI'

            # Thinking first, then content, and never back again.
            $run.Trace | Should -Match '^T+C+$'

            $run.Decoded.Content      | Should -BeExactly "1|alpha`n2|beta`n"
            $run.Decoded.FinishReason | Should -Be 'stop'
            $run.Decoded.InputTokens  | Should -Be 11
            $run.Decoded.OutputTokens | Should -Be 7
        }

        It 'Surfaces an Anthropic thinking_delta as reasoning without leaking it into the translation' {
            $body = @'
data: {"type":"message_start","message":{"usage":{"input_tokens":31}}}
data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"pondering"}}
data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"1|salaam"}}
data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":5}}
'@

            $run = & ([scriptblock]::Create($DecodeSse)) $body 'Anthropic'

            $run.Trace | Should -Match '^T+C+$'
            # The scratchpad is progress information, never part of the answer.
            $run.Decoded.Content      | Should -BeExactly '1|salaam'
            $run.Decoded.FinishReason | Should -Be 'end_turn'
            $run.Decoded.InputTokens  | Should -Be 31
            $run.Decoded.OutputTokens | Should -Be 5
        }

        It 'Reports no thinking phase at all for a model that does not reason' {
            $body = @'
data: {"choices":[{"index":0,"delta":{"content":"1|alpha\n"}}]}
data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}
data: [DONE]
'@

            $run = & ([scriptblock]::Create($DecodeSse)) $body 'OpenAI'

            $run.Trace | Should -BeExactly 'C'
            @($run.Reports | Where-Object { $_.ReasoningLength -gt 0 }).Count | Should -Be 0
        }
    }

    Context 'SSE framing' {
        It 'Skips a half-flushed frame and stops at [DONE]' {
            $decoded = InModuleScope SubtitleTools {
                $body = @'
data: {"choices":[{"index":0,"delta":{"content":"1|al"}}]}
: this is an SSE comment, not data

data: {"choices":[{"index":0,"delta":{"conte
data: {"choices":[{"index":0,"delta":{"content":"pha"},"finish_reason":"length"}]}
data: [DONE]
data: {"choices":[{"index":0,"delta":{"content":" MUST NOT APPEAR"}}]}
'@
                $reader = [System.IO.StringReader]::new($body)
                try {
                    Read-TranslationSseStream -Reader $reader -Shape 'OpenAI'
                } finally {
                    $reader.Dispose()
                }
            }

            # The truncated frame is dropped rather than throwing, and nothing after
            # [DONE] is read.
            $decoded.Content      | Should -BeExactly '1|alpha'
            $decoded.FinishReason | Should -Be 'length'
        }

        It 'Decodes the Google shape, joining the parts of a candidate' {
            $decoded = InModuleScope SubtitleTools {
                $body = @'
data: {"candidates":[{"content":{"parts":[{"text":"1|sa"},{"text":"laam"}]}}]}
data: {"candidates":[{"content":{"parts":[{"text":"\n"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":13,"candidatesTokenCount":6}}
'@
                $reader = [System.IO.StringReader]::new($body)
                try {
                    Read-TranslationSseStream -Reader $reader -Shape 'Google'
                } finally {
                    $reader.Dispose()
                }
            }

            $decoded.Content      | Should -BeExactly "1|salaam`n"
            $decoded.FinishReason | Should -Be 'STOP'
            $decoded.InputTokens  | Should -Be 13
            $decoded.OutputTokens | Should -Be 6
        }
    }
}
