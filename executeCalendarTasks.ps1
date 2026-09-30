#Requires -Version 7.0
[CmdletBinding()]
param([string]$Root)

$common = @{}
if ($Root) { $common.Root = $Root }

& (Join-Path $PSScriptRoot 'archiveOldEvents.ps1') @common
& (Join-Path $PSScriptRoot 'handleRecurring.ps1') @common
& (Join-Path $PSScriptRoot 'notifyEvents.ps1') @common
