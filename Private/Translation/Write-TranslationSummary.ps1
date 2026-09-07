function Write-TranslationSummary {
    <#
    .SYNOPSIS
        Renders a translation run summary as a readable console block.
    .DESCRIPTION
        Deliberately writes to the host rather than to the pipeline. This is a
        human-facing end-of-run report; the machine-readable form of exactly the same
        data is returned on the translated file's .TranslationSummary property, so
        nothing here is the only copy of anything. Emitting it to the output stream
        instead would corrupt the SubtitleFile that Invoke-SubtitleTranslation returns.

        Box-drawing characters are used only when the console can actually render
        them. A Windows PowerShell 5.1 console on a legacy OEM code page turns them
        into mojibake, so the ASCII fallback is not cosmetic - it is the difference
        between a summary and a screenful of question marks.
    .PARAMETER Summary
        A SubtitleTools.TranslationSummary object built by Invoke-SubtitleTranslation.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'End-of-run report for a human. The same data is returned on the pipeline object as .TranslationSummary; writing it to the output stream would corrupt the returned SubtitleFile.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject] $Summary
    )

    $useUnicode = $false
    try { $useUnicode = ([Console]::OutputEncoding.CodePage -eq 65001) } catch { $useUnicode = $false }

    if ($useUnicode) {
        $ruleChar = [string][char]0x2500  # box drawing horizontal
        $sep      = [string][char]0x00B7  # middle dot
        $arrow    = [string][char]0x2192  # rightwards arrow
    } else {
        $ruleChar = '-'
        $sep      = '|'
        $arrow    = '->'
    }

    $width = 68
    $rule  = $ruleChar * $width

    # 12400 -> '12.4k'. Raw counts stay on the summary object; this is display only.
    $compact = {
        param([long] $Count)
        if ($Count -ge 1000000) { '{0:N1}M' -f ($Count / 1000000) }
        elseif ($Count -ge 1000) { '{0:N1}k' -f ($Count / 1000) }
        else { [string] $Count }
    }

    $duration = {
        param([timespan] $Span)
        # Floor, not [int]: [int]3.68 rounds up to 4, which would report a 3m41s run as
        # "4m 41s".
        if ($Span.TotalHours -ge 1) { '{0}h {1:00}m {2:00}s' -f [Math]::Floor($Span.TotalHours), $Span.Minutes, $Span.Seconds }
        elseif ($Span.TotalMinutes -ge 1) { '{0}m {1:00}s' -f [Math]::Floor($Span.TotalMinutes), $Span.Seconds }
        else { '{0:N1}s' -f $Span.TotalSeconds }
    }

    $plural = {
        param([int] $Count, [string] $Singular, [string] $PluralForm)
        if ($Count -eq 1) { "$Count $Singular" } else { "$Count $PluralForm" }
    }

    $row = {
        param([string] $Label, [string] $Value, [string] $Color)
        if (-not $Value) { return }
        Write-Host ('  {0,-10}' -f $Label) -NoNewline -ForegroundColor DarkGray
        if ($Color) { Write-Host $Value -ForegroundColor $Color } else { Write-Host $Value }
    }

    Write-Host ''
    Write-Host "  $rule" -ForegroundColor DarkGray
    Write-Host '  Translation complete' -ForegroundColor Cyan
    Write-Host "  $rule" -ForegroundColor DarkGray

    $sourceName = if ($Summary.SourcePath) { Split-Path $Summary.SourcePath -Leaf } else { '(in-memory subtitle)' }
    & $row 'Source' ("{0}  ({1} {2} {3} {2} {4})" -f
        $sourceName, $Summary.Format, $sep, $Summary.Encoding, (& $plural $Summary.Entries 'entry' 'entries'))
    & $row 'Output' $Summary.OutputPath

    & $row 'Language' ("{0} {1} {2}" -f $Summary.SourceLanguage, $arrow, $Summary.TargetLanguage)
    & $row 'Provider' ("{0} {1} {2}" -f $Summary.Provider, $sep, $Summary.Model)

    if ($Summary.Primed -or $Summary.ContentTitle) {
        $ctxParts = @()
        if ($Summary.ContentType -and $Summary.ContentType -ne 'unknown') { $ctxParts += $Summary.ContentType }
        if ($Summary.ContentTitle -and $Summary.ContentTitle -ne 'UNKNOWN') { $ctxParts += '"{0}"' -f $Summary.ContentTitle }
        if ($Summary.Tone) { $ctxParts += "$($Summary.Tone) tone" }
        $ctxText = $ctxParts -join " $sep "
        if ($Summary.Primed -and $ctxText) { $ctxText += '   (primed)' }
        & $row 'Context' $ctxText
    }

    if ($Summary.GlossaryTerms -gt 0) {
        & $row 'Glossary' (& $plural $Summary.GlossaryTerms 'term' 'terms')
    }

    Write-Host ''

    $entryParts = @("$($Summary.TranslatedEntries) translated")
    if ($Summary.CachedEntries -gt 0)     { $entryParts += "$($Summary.CachedEntries) from cache" }
    if ($Summary.UnresolvedEntries -gt 0) { $entryParts += "$($Summary.UnresolvedEntries) unresolved" }
    $entryColor = if ($Summary.UnresolvedEntries -gt 0) { 'Yellow' } else { 'Green' }
    & $row 'Entries' ($entryParts -join " $sep ") $entryColor

    $reqParts = @(
        (& $plural $Summary.Batches 'batch' 'batches')
        (& $plural $Summary.ApiCalls 'API call' 'API calls')
    )
    if ($Summary.Retries -gt 0)          { $reqParts += (& $plural $Summary.Retries 'retry' 'retries') }
    if ($Summary.TruncatedBatches -gt 0) { $reqParts += "$($Summary.TruncatedBatches) truncated" }
    & $row 'Requests' ($reqParts -join " $sep ")

    & $row 'Tokens' ("{0} in {1} {2} out {1} {3} total" -f
        (& $compact $Summary.InputTokens), $sep,
        (& $compact $Summary.OutputTokens),
        (& $compact $Summary.TotalTokens))

    $timeText = & $duration $Summary.Duration
    if ($Summary.EntriesPerMinute -gt 0) { $timeText += " $sep $($Summary.EntriesPerMinute) entries/min" }
    & $row 'Elapsed' $timeText

    & $row 'Text' ("{0} {1} {2} chars" -f
        ('{0:N0}' -f $Summary.SourceCharacters), $arrow, ('{0:N0}' -f $Summary.OutputCharacters))

    Write-Host "  $rule" -ForegroundColor DarkGray
    Write-Host '  Full details: $result.TranslationSummary' -ForegroundColor DarkGray
    Write-Host ''
}
