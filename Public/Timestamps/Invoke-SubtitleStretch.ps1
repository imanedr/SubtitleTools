function Invoke-SubtitleStretch {
    <#
    .SYNOPSIS
        Applies linear time-stretch using two sync point pairs to correct A/V drift.
    .DESCRIPTION
        When subtitles drift non-linearly (e.g., they start in sync but gradually
        fall behind), provide two reference points: where a subtitle currently appears
        and where it should appear. The function calculates a linear scale + offset
        and applies it to all entries.

        Formula: NewTime = (OldTime - SourcePoint1) * Scale + TargetPoint1
        Where: Scale = (TargetPoint2 - TargetPoint1) / (SourcePoint2 - SourcePoint1)
    .PARAMETER InputObject
        A SubtitleFile object.
    .PARAMETER SourcePoint1
        The current (wrong) time of the first sync reference point.
    .PARAMETER TargetPoint1
        The correct time for the first sync reference point.
    .PARAMETER SourcePoint2
        The current (wrong) time of the second sync reference point.
    .PARAMETER TargetPoint2
        The correct time for the second sync reference point.
    .EXAMPLE
        # Subtitle at 0:01:00 should be 0:01:02; at 1:30:00 should be 1:30:10
        Invoke-SubtitleStretch -InputObject $sub `
            -SourcePoint1 '00:01:00' -TargetPoint1 '00:01:02' `
            -SourcePoint2 '01:30:00' -TargetPoint2 '01:30:10'
    #>
    [CmdletBinding()]
    [OutputType('SubtitleFile')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [SubtitleFile] $InputObject,

        [Parameter(Mandatory)]
        [TimeSpan] $SourcePoint1,

        [Parameter(Mandatory)]
        [TimeSpan] $TargetPoint1,

        [Parameter(Mandatory)]
        [TimeSpan] $SourcePoint2,

        [Parameter(Mandatory)]
        [TimeSpan] $TargetPoint2
    )

    process {
        $srcRange = ($SourcePoint2 - $SourcePoint1).TotalMilliseconds
        $tgtRange = ($TargetPoint2 - $TargetPoint1).TotalMilliseconds

        if ($srcRange -eq 0) {
            throw 'SourcePoint1 and SourcePoint2 must be different times.'
        }

        $scale = $tgtRange / $srcRange

        foreach ($entry in $InputObject.Entries) {
            $entry.Start = [TimeSpan]::FromMilliseconds(
                ($entry.Start - $SourcePoint1).TotalMilliseconds * $scale + $TargetPoint1.TotalMilliseconds
            )
            $entry.End = [TimeSpan]::FromMilliseconds(
                ($entry.End - $SourcePoint1).TotalMilliseconds * $scale + $TargetPoint1.TotalMilliseconds
            )

            # Clamp negatives
            if ($entry.Start -lt [TimeSpan]::Zero) { $entry.Start = [TimeSpan]::Zero }
            if ($entry.End   -lt [TimeSpan]::Zero) { $entry.End   = [TimeSpan]::Zero }
        }

        return $InputObject
    }
}
