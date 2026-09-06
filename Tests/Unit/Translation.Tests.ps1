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

            { Invoke-SubtitleTranslation -InputObject $file -TargetLanguage 'fa' -Session $session } |
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

            $result = Invoke-SubtitleTranslation -InputObject $file -TargetLanguage 'fa' -Session $session -LogPath $logPath

            $result.Entries.Count | Should -Be 2

            $logContent = Get-Content $logPath -Raw
            # Two batches of 100/50 tokens each = 200 input / 100 output.
            $logContent | Should -Match 'Tokens: 200/100 tok'
        }

        Should -Invoke -ModuleName SubtitleTools -CommandName Invoke-RestMethod -Times 2 -Exactly
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
