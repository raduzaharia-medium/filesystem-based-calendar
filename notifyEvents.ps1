#Requires -Version 7.0
<#
    Sends up to three notifications: Today, Tomorrow and Upcoming (everything later in Current).
    Events that already ended but were not archived yet are listed under Today as overdue.
    Windows needs the BurntToast module for real toasts; -Console prints instead.
#>
[CmdletBinding()]
param(
    [string]$Root,
    [datetime]$Today = (Get-Date).Date,
    [switch]$Console
)

Import-Module (Join-Path $PSScriptRoot 'calendarFiles.psm1') -Force

$Root = Get-CalendarRoot $Root
$tomorrow = $Today.AddDays(1)

$todayLines = [System.Collections.Generic.List[string]]::new()
$tomorrowLines = [System.Collections.Generic.List[string]]::new()
$upcomingLines = [System.Collections.Generic.List[string]]::new()

function Format-Line($event, [switch]$WithDate) {
    $line = $event.Summary
    if ($event.IsTimed) {
        $line = '{0} - {1} {2}' -f $event.StartTime.ToString('hh\:mm'), $event.EndTime.ToString('hh\:mm'), $line
    }
    if ($WithDate) { $line = '{0} {1}' -f $event.StartDate.ToString('yyyy-MM-dd'), $line }
    return $line
}

foreach ($event in Get-CalendarEvents -Path (Join-Path $Root 'Current') | Sort-Object Start) {
    if ($event.EndDate -lt $Today) {
        $todayLines.Add('Overdue: ' + (Format-Line $event -WithDate))
    }
    elseif ($event.StartDate -le $Today) {
        $todayLines.Add((Format-Line $event))
    }
    elseif ($event.StartDate -eq $tomorrow) {
        $tomorrowLines.Add((Format-Line $event))
    }
    else {
        $upcomingLines.Add((Format-Line $event -WithDate))
    }
}

foreach ($group in @(
        @{ Title = 'Today'; Lines = $todayLines }
        @{ Title = 'Tomorrow'; Lines = $tomorrowLines }
        @{ Title = 'Upcoming'; Lines = $upcomingLines }
    )) {
    if ($group.Lines.Count -eq 0) { continue }
    Send-CalendarNotification -Title $group.Title -Body ($group.Lines -join "`n") -Console:$Console
    Start-Sleep -Seconds 1
}
