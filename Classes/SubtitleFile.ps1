class SubtitleFile {
    [string]          $Path            # Original file path (null if created in memory)
    [string]          $Format          # 'SRT' | 'ASS' | 'SSA'
    [string]          $Encoding        # 'UTF-8' | 'UTF-8-BOM' | 'UTF-16LE' | etc.
    [bool]            $HasBom
    [AssHeader]       $Header          # Null for SRT; populated for ASS/SSA
    [SubtitleEntry[]] $Entries         # Ordered array of all dialogue entries
    [hashtable]       $ParserWarnings  # EntryIndex -> warning message for soft parse issues

    SubtitleFile() {
        $this.Entries        = @()
        $this.ParserWarnings = @{}
        $this.HasBom         = $false
        $this.Encoding       = 'UTF-8'
    }

    [int] EntryCount() {
        return $this.Entries.Count
    }

    [TimeSpan] TotalDuration() {
        if ($this.Entries.Count -eq 0) { return [TimeSpan]::Zero }
        $last = $this.Entries | Sort-Object End | Select-Object -Last 1
        return $last.End
    }

    [string] ToString() {
        return '[SubtitleFile] Format={0} Entries={1} Path={2}' -f $this.Format, $this.Entries.Count, $this.Path
    }
}
