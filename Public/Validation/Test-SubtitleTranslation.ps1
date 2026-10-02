function Test-SubtitleTranslation {
    <#
    .SYNOPSIS
        Checks a translated subtitle against its source for structural problems.
    .DESCRIPTION
        A translation must change the text and nothing else. This compares the two
        files entry by entry and reports anything that suggests otherwise:

        Errors (IsValid = $false):
          - Entry count differs from the source.
          - An entry's Start or End time differs from the source.
          - An entry's timestamps are invalid (negative, or End before Start).
          - A source entry with text came back empty.

        Warnings:
          - Text identical to the source (untranslated, or left as source fallback).
            Entries with no letters at all ("...", "♪", "123") are not flagged.
          - Protocol leftovers in the text: a literal '<NL>' marker, or a leading
            'N|' line number from the batch wire format.
          - Parser warnings on the translated file (most useful when it was
            re-imported from disk, as Invoke-SubtitleTranslation does).
          - ASS override tags ({\i1}, {\an8}, ...) present in the source but not
            in the translation.

        Built on Compare-SubtitleFile and Test-SubtitleTimestamps. Timestamp
        problems already present in the source are reported as warnings, since the
        translation did not introduce them.
    .PARAMETER Source
        The original SubtitleFile.
    .PARAMETER Translated
        The translated SubtitleFile. Pass a re-imported copy of the written file to
        also verify what actually reached disk.
    .EXAMPLE
        $src = Import-SubtitleFile 'movie.en.srt'
        $dst = Import-SubtitleFile 'movie.fa.srt'
        Test-SubtitleTranslation -Source $src -Translated $dst
    .EXAMPLE
        $result = Invoke-SubtitleTranslation -Path 'movie.srt' -TargetLanguage 'fa' -ProviderName Anthropic -OutputPath 'movie.fa.srt'
        $result.TranslationValidation.Warnings | Format-Table EntryIndex, Field, Message
    #>
    [CmdletBinding()]
    [OutputType('ValidationResult')]
    param(
        [Parameter(Mandatory)]
        [SubtitleFile] $Source,

        [Parameter(Mandatory)]
        [SubtitleFile] $Translated
    )

    $result          = [ValidationResult]::new()
    $result.FilePath = $Translated.Path
    $result.Format   = $Translated.Format

    $srcCount = $Source.Entries.Count
    $dstCount = $Translated.Entries.Count
    if ($srcCount -ne $dstCount) {
        $result.AddError(0, 'Count', "Entry count differs: source has $srcCount, translation has $dstCount.")
    }

    # --- Timestamps and text, entry by entry ---
    # Compare-SubtitleFile reports only entries that differ, so an entry it does NOT
    # return has identical timestamps AND identical text - i.e. it was not translated.
    $diffs     = @(Compare-SubtitleFile -Reference $Source -Difference $Translated)
    $diffByIdx = @{}
    foreach ($d in $diffs) { $diffByIdx[$d.Index] = $d }

    $pairCount = [Math]::Min($srcCount, $dstCount)
    for ($i = 0; $i -lt $pairCount; $i++) {
        $src   = $Source.Entries[$i]
        $dst   = $Translated.Entries[$i]
        $index = $i + 1
        $diff  = $diffByIdx[$index]

        if ($diff) {
            foreach ($change in $diff.Changes) {
                if ($change -like 'Start:*' -or $change -like 'End:*') {
                    $result.AddError($index, 'Timestamp', "Timestamp changed by translation. $change")
                }
            }
        }

        $srcText = ($src.Lines -join "`n").Trim()
        $dstText = ($dst.Lines -join "`n").Trim()

        if ($srcText -and -not $dstText) {
            $result.AddError($index, 'Text', 'Translation is empty but the source entry has text.')
            continue
        }

        if ($srcText -and $srcText -eq $dstText -and $srcText -match '\p{L}') {
            $result.AddWarning($index, 'Untranslated', "Text is identical to the source: '$($src.Lines -join ' / ')'")
        }

        if ($dstText -match '<NL>' -and $srcText -notmatch '<NL>') {
            $result.AddWarning($index, 'Format', "Literal '<NL>' marker left in translated text.")
        }
        if ($dstText -match '^\d+\|' -and $srcText -notmatch '^\d+\|') {
            $result.AddWarning($index, 'Format', "Translated text starts with a line-number prefix: '$($dst.Lines[0])'")
        }

        if ($src -is [AssEntry] -and $src.OverrideTags.Count -gt 0) {
            $dstTags = if ($dst -is [AssEntry]) { $dst.OverrideTags.Count } else { 0 }
            if ($dstTags -lt $src.OverrideTags.Count) {
                $result.AddWarning($index, 'OverrideTag', "Source has $($src.OverrideTags.Count) override tag(s) ($($src.OverrideTags -join '')); translation has $dstTags.")
            }
        }
    }

    # --- Timestamp validity of the translation itself ---
    # Anything Test-SubtitleTimestamps also finds in the source was inherited, not
    # introduced, so it is downgraded to a warning rather than failing the check.
    $srcTimeIssues = @{}
    foreach ($issue in (Test-SubtitleTimestamps -InputObject $Source).Errors) {
        $srcTimeIssues["$($issue.EntryIndex)|$($issue.Field)"] = $true
    }
    $dstTimeCheck = Test-SubtitleTimestamps -InputObject $Translated
    foreach ($issue in $dstTimeCheck.Errors) {
        if ($srcTimeIssues.ContainsKey("$($issue.EntryIndex)|$($issue.Field)")) {
            $result.AddWarning($issue.EntryIndex, $issue.Field, "$($issue.Message) (also present in source)")
        } else {
            $result.AddError($issue.EntryIndex, $issue.Field, $issue.Message)
        }
    }

    foreach ($key in $Translated.ParserWarnings.Keys) {
        $result.AddWarning($key, 'Parse', $Translated.ParserWarnings[$key])
    }

    return $result
}
