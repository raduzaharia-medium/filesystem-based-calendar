#Requires -Version 7.0
<#
    Yearly events live in Recurring, named like any other event (the year in the name is ignored).
    This copies the next occurrence of each one into Current when it falls within -LookaheadDays.
    It is safe to run repeatedly: an occurrence that already exists is left alone.
#>
[CmdletBinding()]
param(
    [string]$Root,
    [int]$LookaheadDays = 90,
    [datetime]$Today = (Get-Date).Date
)

Import-Module (Join-Path $PSScriptRoot 'calendarFiles.psm1') -Force

$Root = Get-CalendarRoot $Root
$current = Join-Path $Root 'Current'
$stamp = [datetime]::UtcNow.ToString("yyyyMMdd'T'HHmmss'Z'")
$limit = $Today.AddDays($LookaheadDays)

function Get-Occurrence([datetime]$date, [int]$year) {
    # 29 February falls back to 28 February in years without one.
    $day = [math]::Min($date.Day, [datetime]::DaysInMonth($year, $date.Month))
    return [datetime]::new($year, $date.Month, $day)
}

foreach ($event in Get-CalendarEvents -Path (Join-Path $Root 'Recurring')) {
    $length = $event.EndDate - $event.StartDate

    foreach ($year in $Today.Year, ($Today.Year + 1)) {
        $start = Get-Occurrence $event.StartDate $year
        $end = $start + $length
        if ($end -lt $Today -or $start -gt $limit) { continue }

        $nameArgs = @{ StartDate = $start; Summary = $event.Summary }
        if ($event.IsTimed) { $nameArgs.StartTime = $event.StartTime; $nameArgs.EndTime = $event.EndTime }
        elseif ($length.Days -gt 0) { $nameArgs.EndDate = $end }

        $target = Join-Path $current (ConvertTo-EventFileName @nameArgs)
        if (Test-Path -LiteralPath $target) { continue }

        $shift = [int]($start - $event.StartDate).TotalDays
        $lines = foreach ($line in Read-IcsLines $event.File.FullName) {
            if ($line -match '^(DTSTART|DTEND)([^:]*):(\d{8})(.*)$') {
                $moved = [datetime]::ParseExact($Matches[3], 'yyyyMMdd', $null).AddDays($shift)
                '{0}{1}:{2}{3}' -f $Matches[1], $Matches[2], $moved.ToString('yyyyMMdd'), $Matches[4]
            }
            elseif ($line -like 'DTSTAMP:*') { "DTSTAMP:$stamp" }
            elseif ($line -match '^UID:(.*?)(@.*)?$') { "UID:$($Matches[1])-$year$($Matches[2])" }
            else { $line }
        }

        New-Item -ItemType Directory -Path $current -Force | Out-Null
        Write-IcsFile -Path $target -Lines $lines
    }
}
