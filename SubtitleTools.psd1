@{
    ModuleVersion        = '1.0.0'
    GUID                 = 'a3f2e1d0-4b5c-6d7e-8f9a-0b1c2d3e4f50'
    Author               = 'Iman Edrisian'
    Copyright            = '(c) 2025 Iman Edrisian. All rights reserved.'
    Description          = 'A comprehensive toolkit for SRT and ASS/SSA subtitle files: parse, validate, repair, shift timestamps, fix encoding, convert formats, manage ASS styles, and translate using OpenAI, Anthropic, Google, or OpenRouter AI APIs.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    RootModule           = 'SubtitleTools.psm1'

    FunctionsToExport    = @(
        # Core I/O
        'Import-SubtitleFile'
        'Export-SubtitleFile'
        'ConvertFrom-SrtFile'
        'ConvertTo-SrtFile'
        'ConvertFrom-AssFile'
        'ConvertTo-AssFile'

        # Validation
        'Test-SrtFile'
        'Test-AssFile'
        'Test-SubtitleTimestamps'
        'Test-SubtitleOverlap'

        # Repair
        'Repair-SrtFile'
        'Repair-AssFile'
        'Repair-SubtitleEncoding'
        'Repair-SubtitleOverlap'
        'Repair-SubtitleNumbering'

        # Timestamps
        'Add-SubtitleOffset'
        'Set-SubtitleOffset'
        'Get-SubtitleDuration'
        'Set-SubtitleDuration'
        'Invoke-SubtitleStretch'
        'Merge-SubtitleFile'
        'Split-SubtitleFile'

        # ASS Advanced
        'Get-AssStyle'
        'Set-AssStyle'
        'New-AssStyle'
        'Remove-AssStyle'
        'Remove-AssOverrideTag'
        'Convert-AssToPlainText'
        'Convert-AssToSrt'
        'Convert-SrtToAss'

        # Translation
        'Invoke-SubtitleTranslation'
        'Get-TranslationProvider'
        'Set-TranslationProvider'
        'Remove-TranslationProvider'
        'New-TranslationSession'
        'Invoke-BackTranslation'
        'Get-OpenRouterModel'
        'Get-TranslationGlossary'
        'Add-TranslationGlossaryEntry'
        'Remove-TranslationGlossaryEntry'
        'Set-SubtitleLineWidth'

        # Utilities
        'Get-SubtitleInfo'
        'Find-SubtitleFile'
        'Compare-SubtitleFile'
        'Optimize-SubtitleFile'
        'Invoke-SubtitleBatch'

        # Sharing
        'Publish-SubtitleFile'
        'Set-SubDLCredential'
        'Get-SubDLCredential'
        'Remove-SubDLCredential'
    )

    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags         = @('Subtitle', 'SRT', 'ASS', 'SSA', 'SubRip', 'SubStation', 'Translation',
                             'Video', 'Encoding', 'Repair', 'Timestamp', 'Batch', 'OpenAI', 'Anthropic', 'Gemini', 'OpenRouter')
            ProjectUri   = 'https://github.com/imanedr/SubtitleTools'
            LicenseUri   = 'https://github.com/imanedr/SubtitleTools/blob/main/LICENSE'
            ReleaseNotes = @'
Version 1.0.0 — Initial release

- Parse and serialize SRT and ASS/SSA files with full round-trip fidelity
- Validate: block structure, timestamps, overlapping entries
- Repair: numbering, encoding (UTF-16/Windows-1252 → UTF-8), timestamp separators, overlaps
- Timestamp manipulation: shift, stretch (two-point sync), merge, split
- ASS/SSA: style CRUD, override tag stripping, format conversion (SRT ↔ ASS)
- AI translation via OpenAI, Anthropic, and Google APIs with batching, caching, glossary,
  content-aware priming, back-translation verification, and resume from checkpoint
- Batch processing: apply any operation to an entire directory tree (PS7+ parallel support)
- Subtitle publishing to SubDL
- No external dependencies; API keys encrypted with Windows DPAPI
'@
        }
    }
}
