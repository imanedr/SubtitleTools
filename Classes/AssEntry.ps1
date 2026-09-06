class AssEntry : SubtitleEntry {
    [string]   $Layer       # Numeric layer for Z-ordering
    [string]   $Style       # References an AssStyle Name
    [string]   $Name        # Actor/speaker name field
    [string]   $MarginL
    [string]   $MarginR
    [string]   $MarginV
    [string]   $Effect
    [string]   $EventType   # 'Dialogue' or 'Comment'
    [string[]] $OverrideTags # Extracted {\...} tags for analysis

    AssEntry() : base() {
        $this.Layer        = '0'
        $this.Style        = 'Default'
        $this.Name         = ''
        $this.MarginL      = '0000'
        $this.MarginR      = '0000'
        $this.MarginV      = '0000'
        $this.Effect       = ''
        $this.EventType    = 'Dialogue'
        $this.OverrideTags = @()
    }
}
