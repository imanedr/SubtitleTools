function Repair-SubtitleNumbering {
    <#
    .SYNOPSIS
        Renumbers SRT sequence numbers sequentially from 1 without touching timestamps or text.
    .PARAMETER InputObject
        A SubtitleFile object.
    .EXAMPLE
        Import-SubtitleFile 'broken.srt' | Repair-SubtitleNumbering
    #>
    [CmdletBinding()]
    [OutputType('SubtitleFile')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [SubtitleFile] $InputObject
    )

    process {
        $i = 1
        foreach ($entry in $InputObject.Entries) {
            $entry.Index = $i
            if ($entry -is [SrtEntry]) {
                $entry.BlockNumber = $i
            }
            $i++
        }

        return $InputObject
    }
}
