function Invoke-BackTranslation {
    <#
    .SYNOPSIS
        Translates a subtitle file back to the source language to verify translation quality.
    .DESCRIPTION
        Takes a translated SubtitleFile, re-translates it back to the source language
        using an AI provider, and returns a comparison report showing each entry's
        original text alongside the back-translation.

        Significant divergence between original and back-translated text indicates
        potential mistranslation or meaning loss.

    .PARAMETER TranslatedFile
        The translated SubtitleFile to verify.
    .PARAMETER OriginalFile
        The original source SubtitleFile to compare against.
    .PARAMETER BackLanguage
        The language to translate back to (usually the source language, e.g. 'en').
    .PARAMETER ProviderName
        AI provider for back-translation.
    .PARAMETER Session
        An existing translation session.
    .PARAMETER SimilarityThreshold
        Entries with word-overlap below this threshold (0.0-1.0) are flagged as
        potential issues. Default: 0.5.
    .EXAMPLE
        $original   = Import-SubtitleFile 'movie.srt'
        $translated = $original | Invoke-SubtitleTranslation -TargetLanguage 'fa' -ProviderName Anthropic
        $report     = Invoke-BackTranslation -TranslatedFile $translated -OriginalFile $original `
                          -BackLanguage 'en' -ProviderName Anthropic
        $report | Where-Object { $_.Flagged } | Format-Table -AutoSize
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [SubtitleFile] $TranslatedFile,

        [Parameter(Mandatory)]
        [SubtitleFile] $OriginalFile,

        [Parameter(Mandatory)]
        [string] $BackLanguage,

        [ValidateSet('OpenAI', 'Anthropic', 'Google')]
        [string] $ProviderName,

        [hashtable] $Session,

        [double] $SimilarityThreshold = 0.5
    )

    # Build a session if not provided
    if (-not $Session) {
        if (-not $ProviderName) {
            throw 'Specify -ProviderName or pass -Session.'
        }
        $Session = New-TranslationSession -ProviderName $ProviderName
    }

    Write-Verbose "Back-translating $($TranslatedFile.Entries.Count) entries to '$BackLanguage'..."
    Write-Progress -Activity 'Back-translation verification' -Status 'Translating...' -PercentComplete 0

    $backTranslated = Invoke-SubtitleTranslation `
        -InputObject $TranslatedFile `
        -TargetLanguage $BackLanguage `
        -Session $Session

    Write-Progress -Activity 'Back-translation verification' -Status 'Comparing...' -PercentComplete 80

    $report = [System.Collections.Generic.List[PSCustomObject]]::new()

    $maxIndex = [Math]::Min($OriginalFile.Entries.Count, $backTranslated.Entries.Count)

    for ($i = 0; $i -lt $maxIndex; $i++) {
        $origEntry  = $OriginalFile.Entries[$i]
        $transEntry = $TranslatedFile.Entries[$i]
        $backEntry  = $backTranslated.Entries[$i]

        $origText = ($origEntry.Lines -join ' ').ToLower() -replace '[^a-z0-9 ]', ''
        $backText = ($backEntry.Lines -join ' ').ToLower() -replace '[^a-z0-9 ]', ''

        # Simple word-overlap similarity
        $origWords = $origText -split '\s+' | Where-Object { $_ }
        $backWords = $backText -split '\s+' | Where-Object { $_ }
        $union     = (@($origWords) + @($backWords) | Sort-Object -Unique).Count
        $intersect = $origWords | Where-Object { $backWords -contains $_ }
        $similarity = if ($union -gt 0) { $intersect.Count / $union } else { 1.0 }

        $report.Add([PSCustomObject]@{
            Index           = $origEntry.Index
            Start           = $origEntry.Start
            OriginalText    = $origEntry.Lines -join ' / '
            TranslatedText  = $transEntry.Lines -join ' / '
            BackTranslation = $backEntry.Lines -join ' / '
            Similarity      = [Math]::Round($similarity, 2)
            Flagged         = $similarity -lt $SimilarityThreshold
        })
    }

    Write-Progress -Activity 'Back-translation verification' -Completed

    $flagged = ($report | Where-Object { $_.Flagged }).Count
    Write-Verbose "Back-translation complete. $flagged / $($report.Count) entries flagged (similarity < $SimilarityThreshold)."

    return $report.ToArray()
}
