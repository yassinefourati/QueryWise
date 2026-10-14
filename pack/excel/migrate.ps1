<# Native Windows Excel migration. Requires installed desktop Excel, not just an XLSX viewer.
   V1 creates typed source sheets from fixtures; V2 adds award remaining balances.
   Source workbooks are never overwritten. Run from Windows PowerShell or pwsh on Windows.
#>
param(
    [ValidateSet('seed','migrate','verify')][string]$Action='verify',
    [string]$OutputDirectory=(Join-Path $PSScriptRoot '../output/grants'),
    [string]$FixtureDirectory=(Join-Path $PSScriptRoot 'fixtures')
)
$ErrorActionPreference='Stop'
$excel=$null; $book=$null
$names=@('donors','programs','awards','disbursements','milestones')
function Release-Com($obj) {
    if ($null -ne $obj -and [System.Runtime.InteropServices.Marshal]::IsComObject($obj)) {
        [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($obj)
    }
}
function Save-NewWorkbook($book,$destination) {
    if (Test-Path $destination) {throw 'Destination exists; choose a new output directory.'}
    $temp=Join-Path (Split-Path $destination) ('staging-'+[guid]::NewGuid().ToString()+'.xlsx')
    $book.SaveAs($temp,51)
    $book.Close($false)
    Move-Item -LiteralPath $temp -Destination $destination
    (Get-FileHash -Algorithm SHA256 $destination).Hash | Set-Content ($destination+'.sha256')
}
function Check-Hash($path) {
    if ((Get-FileHash -Algorithm SHA256 $path).Hash -ne (Get-Content ($path+'.sha256')).Trim()) {throw 'Workbook checksum changed; do not migrate an unreviewed modified file.'}
}
try {
    New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
    $OutputDirectory=(Resolve-Path $OutputDirectory).Path
    $v1=Join-Path $OutputDirectory 'grants-v1.xlsx';$v2=Join-Path $OutputDirectory 'grants-v2.xlsx'
    $excel=New-Object -ComObject Excel.Application
    $excel.Visible=$false;$excel.DisplayAlerts=$false
    if ($Action -eq 'seed') {
        if (Test-Path $v1) {throw 'V1 already exists.'}
        $book=$excel.Workbooks.Add()
        while ($book.Worksheets.Count -gt 1) {$book.Worksheets.Item($book.Worksheets.Count).Delete()}
        $first=$true
        foreach ($name in $names) {
            $rows=@(Import-Csv -LiteralPath (Join-Path $FixtureDirectory ($name+'.csv')))
            if ($rows.Count -eq 0) {throw "Empty fixture: $name"}
            if ($first) {$sheet=$book.Worksheets.Item(1);$first=$false}
            else {$sheet=$book.Worksheets.Add([Type]::Missing,$book.Worksheets.Item($book.Worksheets.Count))}
            $sheet.Name=$name;$headers=@($rows[0].PSObject.Properties.Name)
            for ($col=0;$col -lt $headers.Count;$col++) {
                $key=$headers[$col];$sheet.Cells.Item(1,$col+1).Value2=$key
                for ($row=0;$row -lt $rows.Count;$row++) {
                    $cell=$sheet.Cells.Item($row+2,$col+1);$value=$rows[$row].$key
                    if ($key -match '(^id$|_id$|_cents$)') {$cell.Value2=[double]$value;$cell.NumberFormat='0'}
                    elseif ($key -match '_on$' -and $value) {$cell.Value2=[datetime]::ParseExact($value,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture).ToOADate();$cell.NumberFormat='yyyy-mm-dd'}
                    else {$cell.NumberFormat='@';$cell.Value2=[string]$value}
                    Release-Com $cell
                }
            }
            $used=$sheet.UsedRange;$used.Font.Name='Arial';$used.Font.Size=10
            $header=$sheet.Range($sheet.Cells.Item(1,1),$sheet.Cells.Item(1,$headers.Count))
            $header.Font.Bold=$true;$header.Interior.Color=0xA05B20;$header.Font.Color=0xFFFFFF
            [void]$used.AutoFilter();[void]$used.Columns.AutoFit()
            $sheet.Activate();$excel.ActiveWindow.SplitRow=1;$excel.ActiveWindow.FreezePanes=$true
            Release-Com $header;Release-Com $used;Release-Com $sheet
        }
        $excel.CalculateFullRebuild();Save-NewWorkbook $book $v1
    } elseif ($Action -eq 'migrate') {
        Check-Hash $v1
        if (Test-Path $v2) {throw 'V2 already exists.'}
        $book=$excel.Workbooks.Open($v1,0,$true)
        $sheet=$book.Worksheets.Item('awards');$payments=$book.Worksheets.Item('disbursements')
        $last=$sheet.UsedRange.Rows.Count;$lastPayment=$payments.UsedRange.Rows.Count
        $sheet.Cells.Item(1,7).Value2='remaining_cents'
        for ($r=2;$r -le $last;$r++) {
            # A=id, E=committed_cents, F=status; disbursements B=award_id,D=amount_cents.
            $sheet.Cells.Item($r,7).Formula=('=IF(F{0}="cancelled",0,E{0}-SUMIF(disbursements!$B$2:$B${1},A{0},disbursements!$D$2:$D${1}))' -f $r,$lastPayment)
        }
        $sheet.Range("G2:G$last").NumberFormat='0';$sheet.Columns.Item(7).AutoFit() | Out-Null
        $excel.CalculateFullRebuild();Release-Com $sheet;Release-Com $payments
        Save-NewWorkbook $book $v2
    } else {
        Check-Hash $v1;Check-Hash $v2
        $book=$excel.Workbooks.Open($v2,0,$true)
        foreach ($name in $names) {
            $expected=@(Import-Csv -LiteralPath (Join-Path $FixtureDirectory ($name+'.csv')))
            $sheet=$book.Worksheets.Item($name);$headers=@($expected[0].PSObject.Properties.Name)
            if ($sheet.UsedRange.Rows.Count -ne $expected.Count+1) {throw "$name row count mismatch"}
            for ($col=0;$col -lt $headers.Count;$col++) {
                $key=$headers[$col]
                if ($sheet.Cells.Item(1,$col+1).Value2 -ne $key) {throw "$name header mismatch"}
                for ($row=0;$row -lt $expected.Count;$row++) {
                    $want=$expected[$row].$key;$actual=$sheet.Cells.Item($row+2,$col+1).Value2
                    if ($key -match '(^id$|_id$|_cents$)') {$want=[double]$want}
                    elseif ($key -match '_on$' -and $want) {$want=[datetime]::ParseExact($want,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture).ToOADate()}
                    if ([string]$actual -ne [string]$want) {throw "$name value mismatch at row $row, column $key"}
                }
            }
            Release-Com $sheet
        }
        $awards=@(Import-Csv (Join-Path $FixtureDirectory 'awards.csv'))
        $disbursements=@(Import-Csv (Join-Path $FixtureDirectory 'disbursements.csv'))
        $sheet=$book.Worksheets.Item('awards')
        for ($i=0;$i -lt $awards.Count;$i++) {
            $a=$awards[$i];$paid=0L
            foreach ($d in $disbursements) {if ($d.award_id -eq $a.id) {$paid += [long]$d.amount_cents}}
            $want=if ($a.status -eq 'cancelled') {0L} else {[long]$a.committed_cents-$paid}
            if ([double]$sheet.Cells.Item($i+2,7).Value2 -ne $want) {throw 'Award balance reconciliation failed'}
        }
        Release-Com $sheet;$book.Close($false)
        Write-Output 'Excel: PASS — typed source values, row counts, balances and checksums'
    }
} finally {
    if ($book) {Release-Com $book}
    if ($excel) {$excel.Quit();Release-Com $excel}
    [GC]::Collect();[GC]::WaitForPendingFinalizers()
}
