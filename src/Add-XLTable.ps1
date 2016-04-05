﻿Add-Type -TypeDefinition "public enum XLNumberFormat {Text,Date,General,Percent,DateTime,Time}"

# internal helper functions
function Get-Value($Datum, $ColumnDefinition) {
   $value = $Datum | ForEach-Object -Process $ColumnDefinition.Expression;
   if ($value -eq $null -and $ColumnDefinition.ContainsKey('Default')) {
        $value = $ColumnDefinition.Default;
   }
   $value;
}

function Get-Columns($Datum, $ColumnDefinitions) {
    # normalize columns
    if ($ColumnDefinitions -eq $null) {
        $ColumnDefinitions = Get-Member -InputObject $Datum -MemberType Properties | 
            ForEach-Object -Process { @{Name = $_.Name; Property = $_.Name; } }
    }

    foreach ($col in $ColumnDefinitions) {
        if (-not $col.ContainsKey('Expression')) {
            $propertyName = $col.Property;
            $col.Expression = { $_.$propertyName }.GetNewClosure();
        }

        if (-not $col.ContainsKey('Default')) {
            $col.Default = $null;
        }

        if (-not $col.ContainsKey('Type')) {
            $value = Get-Value -Datum $Datum -Column $col;
            if ($value -ne $null) {
                $col.Type = $value.GetType();
            } else {
                $col.Type = $null;
            }
        }

        if ($col['NumberFormat'] -ne $null) {
            $col.NumberFormat = [XLNumberFormat]$col.NumberFormat;
        } else {
            $col.NumberFormat = switch ($col.Type) {
                    {$_ -eq [String]}        {[XLNumberFormat]::Text}
                    {$_ -eq [DateTime]}      {[XLNumberFormat]::DateTime}
                    default                  {[XLNumberFormat]::General}
                };
        }
    }

    $ColumnDefinitions;
}

function Add-XLTable {
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline=$true)]
    [OfficeOpenXml.ExcelWorksheet]$Sheet,
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $true)]
    [object]$Data,
    [object[]]$Columns = $null,
    [int]$Row = 0,
    [int]$Column = 0,
    [switch]$AutoSize = $false,
    [Switch]$Transpose = $false,
    [switch]$PassThru = $false
)  
begin{
    #validate some input
    if ($Columns -ne $null) {
        $Columns = $Columns | ForEach-Object -Process {
                switch ($_) {
                    {$_ -is [string]} { @{Name = $_; Property = $_}; break; }
                    {$_ -is [System.Collections.IDictionary]} { 
                        if ($_['Name'] -eq $null) {
                            if ($_['Property'] -ne $null) {
                                $_.Name = $_.Property;        
                            } else {
                                throw "Name or Property is required for column definition";
                            }
                        } elseif ($_['Property'] -eq $null -and $_['Expression'] -eq $null) {
                            $_.Property = $_.Name;
                        }

                        if ($_['Property'] -eq $null -and $_['Expression'] -eq $null) {
                            throw "Property or Expression is requierd for column definitions";
                        }

                        if ($_['Type'] -ne $null) {
                            if ($_.Type -isnot [Type]) {
                                if ($_.Type -is [string]) {
                                    Write-Verbose -Message "Coercing string '${_.Type}' to [Type]"
                                    $_.Type = [Type]$_.Type;
                                } else {
                                    throw "Type must be either String or Type";
                                }
                            }
                        }
                        $_;
                        break;
                    }
                    default {throw "Invalid column definition: " + $_;}
                }
            };
        }


    # extract tabular data 
    $rows = [System.Collections.Generic.List[object[]]]::new(); 

    if ($Data -is [System.Collections.IDictionary]) {
        foreach ($kvp in $Data.GetEnumerator()) {
            $rows.Add(@($kvp.Name, $kvp.Value))
        }
    } else {
        [bool]$firstIteration = $true;
        foreach ($datum in @($Data)) {
            if ($firstIteration) {
                $Columns = Get-Columns -Datum $datum -ColumnDefinitions $Columns
                # add header row
                $rows.Add($Columns.Name);
                $firstIteration = $false;
            }

            $rows.Add(@($Columns | ForEach-Object -Process { Get-Value -Datum $datum -Column $_ }));
        }
    }

}
process{

    # find empty location in sheet that can accomodate data
    [int]$tableHeight = $rows.Count;
    [int]$tableWidth = $rows[0].Count;

    if ($Row -eq 0 -and $Column -eq 0) {
        if ($Sheet.Dimension -ne $null) {
            $Row = $Sheet.Dimension.End.Row + 2;
            $Column = $Sheet.Dimension.Start.Column;
        } else {
            $Row = 2;
            $Column = 2;
        }
    } elseif ($Row -eq 0) {
        if ($Sheet.Dimension -ne $null) {
            $Row = $Sheet.Dimension.End.Row + 2;
        } else {
            $Row = 2;
        }
    } elseif ($Column -eq 0) {
        if ($Sheet.Dimension -ne $null) {
            $Column = $Sheet.Dimension.End.Column + 2;        
        } else {
            $Column = 2;
        }
    }

    # write data into sheet
    [int]$currentRow = $Row;
    foreach ($dataRow in $rows) {
        [int]$currentColumn = $Column;
        foreach ($value in $dataRow) {
            if ($Transpose.IsPresent) {
                $cell = $Sheet.Cells[$currentColumn, $currentRow];
            } else {
                $cell = $Sheet.Cells[$currentRow, $currentColumn];
            }
            
            $colDef = $Columns[$currentColumn - $Column]; 
            $colType = $colDef.Type;
            $colValue = $null;
            # don't conver the header
            # TODO maybe exclude the header from the $rows data
            if ($currentRow -gt $Row -and $colType -ne $null -and $value -isnot $colType) {
                $result = $null;
                if ($value -eq $null -or $value -eq '') {
                    $colValue = $colDef.Default;
                } else {
                    Invoke-Expression “`$result = [$colType]`$value”
                    if ($result -eq $null) {
                        Write-Warning -Message "Failed to convert value '$value' to type '$colType'";
                        $result = $colDef.Default;
                    } else {
                        $colValue = $result;
                    }
                }
            } else {
                $colValue = if ($value -ne $null) {$value} else {$colDef.Default};
            }

            if ($colValue -ne $null) {
                $cell.Value = $colValue;
                $cellFmt = $cell.Style.Numberformat;
                # this could very well be wrong
                switch ([XLNumberFormat]$colDef.NumberFormat) {
                    "Text" { $cellFmt.Format = "Text" }
                    "Date" { $cellFmt.Format = "yyyy-mm-dd" }
                    "General" { $cellFmt.Format = "General" }
                    "Percent" { $cellFmt.Format = "0.0%"; }
                    "DateTime" { $cellFmt.Format = "yyyy-mm-dd h:mm.ss" }
                    "Time" { $cellFmt.Format = "h:mm.ss" }
                }
            }
            $currentColumn++;
        }
        $currentRow++;
    }

    # create table
    if ($Transpose.IsPresent) {
        $tableRange = [OfficeOpenXml.ExcelRange]::GetAddress($Row, $Column, $Row + $tableWidth - 1, $Column + $tableHeight - 1);
    } else {
        $tableRange = [OfficeOpenXml.ExcelRange]::GetAddress($Row, $Column, $Row + $tableHeight - 1, $Column + $tableWidth - 1);
    }
    $table = $Sheet.Tables.Add($tableRange, $Name)
    if ($AutoSize) {
        $Sheet.Cells[$tableRange].AutoFitColumns();
    }
    if ($Transpose.IsPresent) {
        $table.ShowHeader = $false;
    }
    if ($PassThru.IsPresent) {
        Write-Output -InputObject $Sheet
    }
}
end{}
}