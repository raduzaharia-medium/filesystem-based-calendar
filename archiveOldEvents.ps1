#Requires -Version 7.0
<#
    Moves finished events out of Current.
    An event that has an X-ARCHIVE:<folder> line goes to Archive/<folder>; one without it is deleted.
    Use -WhatIf to see what would happen.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Root,
    [datetime]$Now = (Get-Date)
)

Import-Module (Join-Path $PSScriptRoot 'calendarFiles.psm1') -Force

$Root = Get-CalendarRoot $Root
$current = Join-Path $Root 'Current'
$archive = Join-Path $Root 'Archive'

foreach ($event in Get-CalendarEvents -Path $current) {
    if ($event.End -gt $Now) { continue }

    $file = $event.File
    $archiveLine = [System.IO.File]::ReadLines($file.FullName) | Where-Object { $_ -like 'X-ARCHIVE:*' } | Select-Object -First 1

    if (-not $archiveLine) {
        if ($PSCmdlet.ShouldProcess($file.Name, 'Delete finished event')) {
            Remove-Item -LiteralPath $file.FullName
        }
        continue
    }

    $folder = Get-SafeFileName $archiveLine.Substring('X-ARCHIVE:'.Length).Trim()
    $target = Join-Path $archive $folder

    if ($PSCmdlet.ShouldProcess($file.Name, "Move to Archive/$folder")) {
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Move-Item -LiteralPath $file.FullName -Destination (Join-Path $target $file.Name) -Force
    }
}
