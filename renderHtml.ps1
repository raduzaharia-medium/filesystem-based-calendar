#Requires -Version 7.0
<#
    Renders a year of events as a single HTML page, Monday first.
    Reads every calendar folder under -Root; Recurring events are shown in the year being rendered.
#>
[CmdletBinding()]
param(
    [string]$Root,
    [int]$Year = (Get-Date).Year,
    [string]$OutFile
)

Import-Module (Join-Path $PSScriptRoot 'calendarFiles.psm1') -Force

$Root = Get-CalendarRoot $Root
if (-not $OutFile) { $OutFile = Join-Path $Root "calendar-$Year.html" }

$culture = [cultureinfo]::CurrentCulture
$byDay = @{}   # 'yyyy-MM-dd' -> list of labels
$seen = [System.Collections.Generic.HashSet[string]]::new()

function Add-Label([datetime]$day, [string]$label) {
    $key = $day.ToString('yyyy-MM-dd')
    if (-not $byDay.ContainsKey($key)) { $byDay[$key] = [System.Collections.Generic.List[string]]::new() }
    $byDay[$key].Add($label)
}

foreach ($event in Get-CalendarEvents -Path $Root -Recurse) {
    $isRecurring = $event.File.Directory.Name -eq 'Recurring'
    $start = $event.StartDate
    $length = ($event.EndDate - $event.StartDate).Days

    if ($isRecurring) {
        $day = [math]::Min($start.Day, [datetime]::DaysInMonth($Year, $start.Month))
        $start = [datetime]::new($Year, $start.Month, $day)
    }

    $label = $event.Summary
    if ($event.IsTimed) { $label = '{0} {1}' -f $event.StartTime.ToString('hh\:mm'), $label }

    for ($i = 0; $i -le $length; $i++) {
        $day = $start.AddDays($i)
        if ($day.Year -ne $Year) { continue }
        # A recurring event and its copy in Current would otherwise show twice.
        if ($seen.Add(('{0}|{1}' -f $day.ToString('yyyy-MM-dd'), $label))) { Add-Label $day $label }
    }
}

$enc = { param($text) [System.Net.WebUtility]::HtmlEncode($text) }

$html = [System.Text.StringBuilder]::new()
[void]$html.AppendLine(@"
<!DOCTYPE html>
<html lang="en">
<head>
    <title>$Year</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { font-family: Calibri, sans-serif; font-size: 18px; }
        section { margin-bottom: 80px; }
        h2 { text-align: center; }
        table { margin-left: auto; margin-right: auto; }
        td { height: 120px; width: 140px; vertical-align: top; padding: 6px; }
        td.valid { border: 1px solid #DCDCDC; }
        ul { list-style: none; padding: 0; margin: 10px 0 0 0; }
        li { text-overflow: ellipsis; overflow: hidden; width: 140px; white-space: nowrap; font-size: 0.8em;
             border: 1px solid #DCDCDC; border-radius: 4px; margin: 2px 0; cursor: default; }
    </style>
</head>
<body>
"@)

$dayNames = 0..6 | ForEach-Object { $culture.DateTimeFormat.AbbreviatedDayNames[($_ + 1) % 7] }

for ($month = 1; $month -le 12; $month++) {
    $first = [datetime]::new($Year, $month, 1)
    $daysInMonth = [datetime]::DaysInMonth($Year, $month)
    $offset = ([int]$first.DayOfWeek + 6) % 7   # Monday = 0 ... Sunday = 6

    [void]$html.AppendLine("<section><h2>$($culture.DateTimeFormat.GetMonthName($month))</h2><table>")
    [void]$html.AppendLine('<tr>' + (($dayNames | ForEach-Object { "<th>$(& $enc $_)</th>" }) -join '') + '</tr>')

    $cells = @('<td></td>') * $offset
    for ($d = 1; $d -le $daysInMonth; $d++) {
        $key = [datetime]::new($Year, $month, $d).ToString('yyyy-MM-dd')
        $list = ''
        if ($byDay.ContainsKey($key)) {
            $items = $byDay[$key] | ForEach-Object { $t = & $enc $_; "<li title=""$t"">$t</li>" }
            $list = '<ul>' + ($items -join '') + '</ul>'
        }
        $cells += "<td class=""valid"">$d$list</td>"
    }
    while ($cells.Count % 7 -ne 0) { $cells += '<td></td>' }

    for ($row = 0; $row -lt $cells.Count; $row += 7) {
        [void]$html.AppendLine('<tr>' + ($cells[$row..($row + 6)] -join '') + '</tr>')
    }
    [void]$html.AppendLine('</table></section>')
}

[void]$html.AppendLine('</body></html>')
[System.IO.File]::WriteAllText($OutFile, $html.ToString(), [System.Text.UTF8Encoding]::new($false))
Write-Host "Wrote $OutFile"
