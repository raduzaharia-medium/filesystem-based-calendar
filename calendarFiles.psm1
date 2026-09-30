#Requires -Version 7.0
<#
    Shared helpers for the filesystem calendar.

    A calendar is a folder, an event is a file, and the file name is the index:

        YYYY-MM-DD[ - YYYY-MM-DD][ (HH MM - HH MM)] - Summary.ics

    Everything the scripts need to know about an event (when it starts, when it ends,
    what it is called) is read from the name. The .ics content only carries the extra detail.
#>

Set-StrictMode -Version Latest

$script:EventNamePattern = '^(?<start>\d{4}-\d{2}-\d{2})(?: - (?<end>\d{4}-\d{2}-\d{2}))?(?: \((?<sh>\d{2}) (?<sm>\d{2}) - (?<eh>\d{2}) (?<em>\d{2})\))? - (?<summary>.+?)\.ics$'

function Get-CalendarRoot {
    param([string]$Root)
    if ($Root) { return (Resolve-Path -LiteralPath $Root).Path }
    if ($env:CALENDAR_ROOT) { return (Resolve-Path -LiteralPath $env:CALENDAR_ROOT).Path }
    return (Get-Location).Path
}

function Get-SafeFileName {
    <# Replaces characters that are invalid in file names on Windows, macOS or Linux. #>
    param([Parameter(Mandatory)][string]$Name)
    $safe = $Name -replace '[\\/:*?"<>|\x00-\x1f]', '-'
    $safe = $safe -replace '\s+', ' '
    return $safe.Trim().TrimEnd('.')
}

function ConvertFrom-EventFileName {
    <# Parses an event file name. Returns $null when the name does not follow the convention. #>
    param([Parameter(Mandatory)][string]$Name)

    $m = [regex]::Match($Name, $script:EventNamePattern)
    if (-not $m.Success) { return $null }

    $start = [datetime]::ParseExact($m.Groups['start'].Value, 'yyyy-MM-dd', $null)
    $end = $start
    if ($m.Groups['end'].Success) {
        $end = [datetime]::ParseExact($m.Groups['end'].Value, 'yyyy-MM-dd', $null)
    }

    $timed = $m.Groups['sh'].Success
    $startTime = $null
    $endTime = $null
    if ($timed) {
        $startTime = [timespan]::new([int]$m.Groups['sh'].Value, [int]$m.Groups['sm'].Value, 0)
        $endTime = [timespan]::new([int]$m.Groups['eh'].Value, [int]$m.Groups['em'].Value, 0)
    }

    [pscustomobject]@{
        StartDate = $start        # first day, midnight
        EndDate   = $end          # last day (inclusive), midnight
        IsTimed   = $timed
        StartTime = $startTime
        EndTime   = $endTime
        Summary   = $m.Groups['summary'].Value
        Start     = if ($timed) { $start + $startTime } else { $start }
        # The moment the event is over: end of the last day for all-day events.
        End       = if ($timed) { $end + $endTime } else { $end.AddDays(1) }
    }
}

function ConvertTo-EventFileName {
    param(
        [Parameter(Mandatory)][datetime]$StartDate,
        [datetime]$EndDate,
        [timespan]$StartTime,
        [timespan]$EndTime,
        [Parameter(Mandatory)][string]$Summary
    )

    $name = $StartDate.ToString('yyyy-MM-dd')
    $hasTime = $PSBoundParameters.ContainsKey('StartTime') -and $PSBoundParameters.ContainsKey('EndTime')

    if ($hasTime) {
        $name += ' ({0} - {1})' -f $StartTime.ToString('hh\ mm'), $EndTime.ToString('hh\ mm')
    }
    elseif ($PSBoundParameters.ContainsKey('EndDate') -and $EndDate.Date -gt $StartDate.Date) {
        $name += ' - ' + $EndDate.ToString('yyyy-MM-dd')
    }

    $safeSummary = Get-SafeFileName $Summary
    if (-not $safeSummary) { $safeSummary = 'Untitled' }
    if ($safeSummary.Length -gt 120) { $safeSummary = $safeSummary.Substring(0, 120).TrimEnd() }

    return "$name - $safeSummary.ics"
}

function Get-CalendarEvents {
    <# Lists the events in a calendar folder, parsed from their file names. Files that do not follow the convention are reported and skipped. #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Recurse
    )

    if (-not (Test-Path -LiteralPath $Path)) { return }

    Get-ChildItem -LiteralPath $Path -Filter '*.ics' -File -Recurse:$Recurse | ForEach-Object {
        $parsed = ConvertFrom-EventFileName $_.Name
        if ($null -eq $parsed) {
            Write-Warning "Skipping '$($_.FullName)': the name does not follow 'YYYY-MM-DD[ - YYYY-MM-DD][ (HH MM - HH MM)] - Summary.ics'."
            return
        }
        $parsed | Add-Member -NotePropertyName File -NotePropertyValue $_ -PassThru
    }
}

function Read-IcsLines {
    <# Reads an .ics file and unfolds continuation lines (RFC 5545 3.1). #>
    param([Parameter(Mandatory)][string]$Path)

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line.Length -gt 0 -and ($line[0] -eq ' ' -or $line[0] -eq "`t") -and $lines.Count -gt 0) {
            $lines[$lines.Count - 1] += $line.Substring(1)
        }
        else {
            $lines.Add($line)
        }
    }
    return $lines.ToArray()
}

function Write-IcsFile {
    <# Writes UTF-8 (no BOM) with CRLF line endings, as calendar clients expect. #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Lines
    )
    $text = ($Lines -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($Path, $text, [System.Text.UTF8Encoding]::new($false))
}

function ConvertTo-IcsText {
    param([string]$Text)
    return ($Text -replace '\\', '\\' -replace ';', '\;' -replace ',', '\,' -replace "`r?`n", '\n')
}

function ConvertFrom-IcsText {
    param([string]$Text)
    return ($Text -replace '\\[nN]', ' ' -replace '\\([,;\\])', '$1')
}

function Get-IcsProperty {
    <# Returns the value of the first property with the given name, or $null. #>
    param([string[]]$Lines, [string]$Name)
    foreach ($line in $Lines) {
        if ($line -match "^$([regex]::Escape($Name))(;[^:]*)?:(.*)$") { return $Matches[2] }
    }
    return $null
}

function Send-CalendarNotification {
    <#
        Shows a desktop notification. Windows uses the BurntToast module when installed
        (Install-Module BurntToast); macOS and Linux use their native tools.
        Falls back to the console, which is also what -Console forces.
    #>
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Body,
        [switch]$Console
    )

    if (-not $Console) {
        if ($IsWindows -and (Get-Module -ListAvailable -Name BurntToast)) {
            Import-Module BurntToast
            New-BurntToastNotification -Text $Title, $Body
            return
        }
        if ($IsMacOS) {
            $script = 'display notification "{0}" with title "{1}"' -f ($Body -replace '["\\]', '\$0'), ($Title -replace '["\\]', '\$0')
            & osascript -e $script
            return
        }
        if ($IsLinux -and (Get-Command notify-send -ErrorAction SilentlyContinue)) {
            & notify-send $Title $Body
            return
        }
    }

    Write-Host "== $Title"
    Write-Host $Body
}

Export-ModuleMember -Function *
