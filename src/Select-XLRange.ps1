function Select-XLRange {
[OutputType([XLRange])]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline=$true)]
    [XLSheet]$Sheet,
    
    [Parameter(Mandatory = $true, Position = 1)]
    [Alias("Row")]
    [int]$FromRow,
    
    [int]$ToRow = $FromRow,
    
    [Parameter(Mandatory = $true, Position = 2)]
    [Alias("Column")]
    [int]$FromColumn,
    
    [int]$ToColumn = $FromColumn,
    
    [string[]]$Headers = $null,
    
    [Switch]$HasHeaders = $false
)  
begin{
}
process {
    [OfficeOpenXml.ExcelRange]$range = $Sheet.Worksheet.Cells.Item($FromRow, $FromColumn, $ToRow, $ToColumn)
    
    if ($Headers -ne $null -and $Headers.Length -ne $range.Columns) {
        throw "Header contains $($Header.Length) elements but the selection is for $($range.Columns) columns"
    }

    $xlRange = [XLRange]::new($Sheet.Owner, $range)
    # TODO move these to ctor so they're not publically writeable
    $xlRange.Headers = $Headers
    $xlRange.HasHeaders = $HasHeaders.IsPresent
    $PSCmdlet.WriteObject($xlRange, $false)
    
}
end{}
}
