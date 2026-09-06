class AssHeader {
    [string]     $ScriptType        # 'v4.00+' for ASS, 'v4.00' for SSA
    [string]     $Title
    [string]     $OriginalScript
    [string]     $PlayResX
    [string]     $PlayResY
    [string]     $YCbCrMatrix
    [hashtable]  $ExtraFields       # Preserves unrecognized Script Info fields
    [AssStyle[]] $Styles
    [string[]]   $EventColumnOrder  # Preserves the exact Format: line column order

    AssHeader() {
        $this.ScriptType       = 'v4.00+'
        $this.Title            = 'Untitled'
        $this.OriginalScript   = ''
        $this.PlayResX         = '640'
        $this.PlayResY         = '480'
        $this.YCbCrMatrix      = ''
        $this.ExtraFields      = @{}
        $this.Styles           = @()
        $this.EventColumnOrder = @('Layer', 'Start', 'End', 'Style', 'Name', 'MarginL', 'MarginR', 'MarginV', 'Effect', 'Text')
    }
}
