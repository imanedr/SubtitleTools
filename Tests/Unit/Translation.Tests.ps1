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
