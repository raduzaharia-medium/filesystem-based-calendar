#Requires -Version 7.0
<#
    Splits an .ics export (Outlook, Google, ...) into one file per event, named the way the calendar expects.
      ./icssplitter.ps1 -InputFile aniversari.ics -OutputFolder Recurring
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputFile,
    [Parameter(Mandatory)][string]$OutputFolder
)

Import-Module (Join-Path $PSScriptRoot 'calendarFiles.psm1') -Force

# Properties that only clutter a single-event file.
$dropped = '^(CLASS|CREATED|LAST-MODIFIED|PRIORITY|SEQUENCE|TRANSP|X-)'

function ConvertFrom-IcsDate([string]$value) {
    # 20190501, 20190501T093000 or 20190501T093000Z
    $date = [datetime]::ParseExact($value.Substring(0, 8), 'yyyyMMdd', $null)
    $time = $null
    if ($value.Length -ge 13 -and $value[8] -eq 'T') {
        $time = [timespan]::new([int]$value.Substring(9, 2), [int]$value.Substring(11, 2), 0)
    }
    [pscustomobject]@{ Date = $date; Time = $time }
}

New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null

$lines = Read-IcsLines (Resolve-Path -LiteralPath $InputFile).Path
$block = $null
$written = 0

foreach ($line in $lines) {
    if ($line -eq 'BEGIN:VEVENT') { $block = [System.Collections.Generic.List[string]]::new(); $block.Add($line); continue }
    if ($null -eq $block) { continue }

    if ($line -ne 'END:VEVENT') {
        if ($line -notmatch $dropped) { $block.Add($line) }
        continue
    }
    $block.Add($line)

    $dtstart = Get-IcsProperty $block 'DTSTART'
    $dtend = Get-IcsProperty $block 'DTEND'
    $summary = ConvertFrom-IcsText (Get-IcsProperty $block 'SUMMARY')
    $eventLines = $block
    $block = $null

    if (-not $dtstart -or -not $summary) { Write-Warning 'Skipping an event without DTSTART or SUMMARY.'; continue }

    $start = ConvertFrom-IcsDate $dtstart
    $nameArgs = @{ StartDate = $start.Date; Summary = $summary }

    if ($null -ne $start.Time) {
        $end = if ($dtend) { ConvertFrom-IcsDate $dtend } else { $null }
        $endTime = if ($end -and $null -ne $end.Time) { $end.Time } else { $start.Time }
        if ($end -and $end.Date -gt $start.Date) {
            Write-Warning "'$summary' runs past midnight; the file name can only hold the start day's times."
            $endTime = [timespan]::new(23, 59, 0)
        }
        $nameArgs.StartTime = $start.Time
        $nameArgs.EndTime = $endTime
    }
    elseif ($dtend) {
        # DTEND is exclusive for all-day events; the file name holds the last day.
        $last = (ConvertFrom-IcsDate $dtend).Date.AddDays(-1)
        if ($last -gt $start.Date) { $nameArgs.EndDate = $last }
    }

    $name = ConvertTo-EventFileName @nameArgs
    $target = Join-Path $OutputFolder $name
    for ($n = 2; Test-Path -LiteralPath $target; $n++) {
        $target = Join-Path $OutputFolder ($name -replace '\.ics$', " [$n].ics")
    }

    $body = @(
        'BEGIN:VCALENDAR'
        'PRODID:-//Microsoft Corporation//Outlook 16.0 MIMEDIR//EN'
        'VERSION:2.0'
        'METHOD:PUBLISH'
    ) + $eventLines + 'END:VCALENDAR'

    Write-IcsFile -Path $target -Lines $body
    $written++
}

Write-Host "Wrote $written event(s) to $OutputFolder"
