class ValidationIssue {
    [int]    $EntryIndex
    [string] $Field
    [string] $Message
    [string] $Severity   # 'Error' | 'Warning'

    ValidationIssue([int]$index, [string]$field, [string]$message, [string]$severity) {
        $this.EntryIndex = $index
        $this.Field      = $field
        $this.Message    = $message
        $this.Severity   = $severity
    }

    [string] ToString() {
        return '[{0}] Entry {1} {2}: {3}' -f $this.Severity, $this.EntryIndex, $this.Field, $this.Message
    }
}

class ValidationResult {
    [bool]              $IsValid
    [string]            $FilePath
    [string]            $Format
    [ValidationIssue[]] $Errors
    [ValidationIssue[]] $Warnings
    [int]               $ErrorCount
    [int]               $WarningCount

    ValidationResult() {
        $this.IsValid       = $true
        $this.Errors        = @()
        $this.Warnings      = @()
        $this.ErrorCount    = 0
        $this.WarningCount  = 0
    }

    [void] AddError([int]$index, [string]$field, [string]$message) {
        $issue          = [ValidationIssue]::new($index, $field, $message, 'Error')
        $this.Errors   += $issue
        $this.ErrorCount++
        $this.IsValid   = $false
    }

    [void] AddWarning([int]$index, [string]$field, [string]$message) {
        $issue             = [ValidationIssue]::new($index, $field, $message, 'Warning')
        $this.Warnings    += $issue
        $this.WarningCount++
    }

    [string] ToString() {
        $status = if ($this.IsValid) { 'VALID' } else { 'INVALID' }
        return '[ValidationResult] {0} Errors={1} Warnings={2}' -f $status, $this.ErrorCount, $this.WarningCount
    }
}
