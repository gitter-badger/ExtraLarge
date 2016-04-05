Import-Module -Name "$PSScriptRoot\src\ExtraLarge.psm1" -Force

$raw = @"
A,B,C,Date
2,1,0.5,2016-03-29
5,10,,2016-03-30
"@

$data = ConvertFrom-Csv -InputObject $raw
Remove-Item C:\temp\out3.xlsx -Force

New-XLFile -Path c:\temp\out3.xlsx -PassThru |
    Add-XLSheet -Name 'Sheet 1' |
        Add-XLTable -Name Table1 -Data $data -Columns @{Name='A';Type=[int]},@{Name='B';Type=[int]},@{Name='C';Type=[float];NumberFormat='Percent'},@{Name='Date';Type=[DateTime]} -PassThru |
        Add-XLTable -Name Table2 -Data $data -Columns  @{Name='A';Type=[int]},@{Name='B';Type=[int]},@{Name='C';Type=[float];Default=30},@{Name='D';Type=[float];Default=99},@{Name='Date';Type=[DateTime];NumberFormat=[XLNumberFormat]::Date} -PassThru |
        Add-XLChart -Header "Chart 1" -Type "Line" -With { $_ | Add-XLChartSeries -X "Table2[Date]" -Y "Table2[A]" -PassThru | 
                                                                Add-XLChartSeries -X "Table2[Date]" -Y "Table2[B]" -Type AreaStacked -PassThru |
                                                                Add-XLChartSeries -X "Table2[Date]" -Y "Table2[C]" -Type AreaStacked -PassThru } -Column 6

return;


