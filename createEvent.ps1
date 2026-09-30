#Requires -Version 7.0
<#
    Creates an event in Current: the .ics content plus the descriptive file name.

    With parameters it runs headless; with none it asks (a WPF dialog on Windows, prompts elsewhere).
      ./createEvent.ps1 -Summary 'Dentist' -StartDate 2026-10-05 -TimeInterval '14:30 - 15:15'
      ./createEvent.ps1 -Summary 'Holiday' -StartDate 2026-08-01 -EndDate 2026-08-14 -AllDay
#>
[CmdletBinding()]
param(
    [string]$Summary,
    [datetime]$StartDate = (Get-Date).Date,
    [datetime]$EndDate,
    [string]$TimeInterval,
    [switch]$AllDay,
    [string]$ArchiveFolder,
    [string]$Root
)

Import-Module (Join-Path $PSScriptRoot 'calendarFiles.psm1') -Force
$Root = Get-CalendarRoot $Root

function Show-EventDialog {
    Add-Type -Name Window -Namespace Console -MemberDefinition '
        [DllImport("Kernel32.dll")] public static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);'
    [Console.Window]::ShowWindow([Console.Window]::GetConsoleWindow(), 0) | Out-Null

    Add-Type -AssemblyName PresentationFramework
    $today = Get-Date -Format 'yyyy-MM-dd'

    [xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    x:Name="Window" Title="Calendar"
    WindowStartupLocation="CenterScreen" ShowInTaskbar="True"
    TextOptions.TextRenderingMode="Auto" TextOptions.TextFormattingMode="Display" RenderOptions.ClearTypeHint="Auto"
    Width="500" Height="240" AllowsTransparency="True" WindowStyle="None" Background="Black">
    <StackPanel>
        <StackPanel Margin="8" Orientation="Horizontal" HorizontalAlignment="Center">
            <Label Foreground="White" VerticalAlignment="Center" Content="Summary" />
            <TextBox Name="Summary" VerticalAlignment="Center" Width="200" BorderThickness="1" BorderBrush="Gray" />
            <Label Width="54" />
        </StackPanel>
        <StackPanel Margin="8" Orientation="Horizontal" HorizontalAlignment="Center">
            <Label Foreground="White" Content="Start date" VerticalAlignment="Center" />
            <DatePicker Name="StartDate" VerticalAlignment="Center" BorderBrush="Transparent" SelectedDate="$today" SelectedDateFormat="Long" FirstDayOfWeek="Monday" Width="200" />
            <CheckBox Foreground="White" Name="AllDay" VerticalAlignment="Center">All day</CheckBox>
        </StackPanel>
        <StackPanel Name="EndDateStack" Margin="8" Orientation="Horizontal" Visibility="Collapsed" HorizontalAlignment="Center">
            <Label Foreground="White" VerticalAlignment="Center" Content="End date" />
            <DatePicker Name="EndDate" VerticalAlignment="Center" BorderBrush="Transparent" SelectedDate="$today" SelectedDateFormat="Long" FirstDayOfWeek="Monday" Width="200" />
            <Label Width="53" />
        </StackPanel>
        <StackPanel Name="TimeIntervalStack" Margin="8" Orientation="Horizontal" HorizontalAlignment="Center">
            <Label Foreground="White" VerticalAlignment="Center" Content="Time interval" />
            <TextBox Name="TimeInterval" VerticalAlignment="Center" Width="200" BorderThickness="1" BorderBrush="Gray" />
            <Label Width="70" />
        </StackPanel>
        <StackPanel Margin="8" Orientation="Horizontal" HorizontalAlignment="Center">
            <Label Foreground="White" VerticalAlignment="Center" Content="Archive folder" />
            <ComboBox Name="ArchiveFolder" VerticalAlignment="Center" Width="200" BorderThickness="1" BorderBrush="Gray" />
            <Label Width="76" />
        </StackPanel>
        <StackPanel Margin="8,50" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button Name="OK" MinWidth="100">OK</Button>
            <Button Name="Cancel" MinWidth="100" Margin="10,0,0,0">Cancel</Button>
        </StackPanel>
    </StackPanel>
</Window>
"@

    $window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    $window.Background = [Windows.SystemParameters]::WindowGlassBrush

    $summaryBox = $window.FindName('Summary')
    $start = $window.FindName('StartDate')
    $end = $window.FindName('EndDate')
    $endStack = $window.FindName('EndDateStack')
    $allDayBox = $window.FindName('AllDay')
    $intervalStack = $window.FindName('TimeIntervalStack')
    $intervalBox = $window.FindName('TimeInterval')
    $archiveBox = $window.FindName('ArchiveFolder')

    $archiveBox.Items.Add('Do not archive') | Out-Null
    $archiveBox.SelectedIndex = 0
    Get-ChildItem (Join-Path $Root 'Archive') -Directory -ErrorAction SilentlyContinue | ForEach-Object { $archiveBox.Items.Add($_.Name) | Out-Null }

    $result = @{ Ok = $false }
    $window.FindName('OK').Add_Click({ $result.Ok = $true; $window.Close() }.GetNewClosure())
    $window.FindName('Cancel').Add_Click({ $window.Close() }.GetNewClosure())
    $allDayBox.Add_Click({
            $on = [bool]$allDayBox.IsChecked
            $endStack.Visibility = if ($on) { 'Visible' } else { 'Collapsed' }
            $intervalStack.Visibility = if ($on) { 'Collapsed' } else { 'Visible' }
        }.GetNewClosure())

    $window.ShowDialog() | Out-Null
    if (-not $result.Ok) { return $null }

    $onAllDay = [bool]$allDayBox.IsChecked
    [pscustomobject]@{
        Summary       = $summaryBox.Text
        StartDate     = $start.SelectedDate
        EndDate       = if ($onAllDay) { $end.SelectedDate } else { $null }
        AllDay        = $onAllDay
        TimeInterval  = if ($onAllDay) { '' } else { $intervalBox.Text }
        ArchiveFolder = if ($archiveBox.SelectedIndex -gt 0) { [string]$archiveBox.SelectedValue } else { '' }
    }
}

if (-not $Summary) {
    if ($IsWindows) {
        $answers = Show-EventDialog
        if (-not $answers) { return }
    }
    else {
        $answers = [pscustomobject]@{
            Summary       = Read-Host 'Summary'
            StartDate     = [datetime](Read-Host 'Start date (yyyy-MM-dd)')
            EndDate       = $null
            AllDay        = $false
            TimeInterval  = Read-Host 'Time interval (HH:MM - HH:MM, empty for all day)'
            ArchiveFolder = Read-Host 'Archive folder (empty to delete when done)'
        }
    }
    $Summary = $answers.Summary
    $StartDate = $answers.StartDate
    if ($answers.EndDate) { $EndDate = $answers.EndDate }
    $AllDay = [switch]$answers.AllDay
    $TimeInterval = $answers.TimeInterval
    $ArchiveFolder = $answers.ArchiveFolder
}

if (-not $Summary.Trim()) { throw 'An event needs a summary.' }
$StartDate = $StartDate.Date

$nameArgs = @{ StartDate = $StartDate; Summary = $Summary }
$props = [System.Collections.Generic.List[string]]::new()
$stamp = [datetime]::UtcNow.ToString("yyyyMMdd'T'HHmmss'Z'")

if ($TimeInterval -and -not $AllDay) {
    if ($TimeInterval -notmatch '^\s*(\d{1,2}):?(\d{2})\s*-\s*(\d{1,2}):?(\d{2})\s*$') {
        throw "Time interval '$TimeInterval' must look like '14:30 - 15:15'."
    }
    $from = [timespan]::new([int]$Matches[1], [int]$Matches[2], 0)
    $to = [timespan]::new([int]$Matches[3], [int]$Matches[4], 0)
    if ($to -le $from) { throw 'The event must end after it starts (events cannot cross midnight in this format).' }

    $nameArgs.StartTime = $from
    $nameArgs.EndTime = $to
    $props.Add('DTSTART:' + ($StartDate + $from).ToString("yyyyMMdd'T'HHmmss"))
    $props.Add('DTEND:' + ($StartDate + $to).ToString("yyyyMMdd'T'HHmmss"))
}
else {
    # All-day: the file name holds the inclusive last day, DTEND is exclusive (the day after).
    $last = $StartDate
    if ($EndDate -gt [datetime]::MinValue) {
        if ($EndDate.Date -lt $StartDate) { throw 'The end date is before the start date.' }
        $last = $EndDate.Date
    }
    if ($last -gt $StartDate) { $nameArgs.EndDate = $last }
    $props.Add('DTSTART;VALUE=DATE:' + $StartDate.ToString('yyyyMMdd'))
    $props.Add('DTEND;VALUE=DATE:' + $last.AddDays(1).ToString('yyyyMMdd'))
}

$lines = @(
    'BEGIN:VCALENDAR'
    'PRODID:-//Radu Zaharia//My Calendar//EN'
    'VERSION:2.0'
    'METHOD:PUBLISH'
    'BEGIN:VEVENT'
    "DTSTAMP:$stamp"
    $props
    'SUMMARY:' + (ConvertTo-IcsText $Summary)
)
if ($ArchiveFolder) { $lines += "X-ARCHIVE:$ArchiveFolder" }
$lines += "UID:$([guid]::NewGuid())@radu.me"
$lines += 'END:VEVENT'
$lines += 'END:VCALENDAR'

$currentFolder = Join-Path $Root 'Current'
New-Item -ItemType Directory -Path $currentFolder -Force | Out-Null

$target = Join-Path $currentFolder (ConvertTo-EventFileName @nameArgs)
if (Test-Path -LiteralPath $target) { throw "'$target' already exists." }

Write-IcsFile -Path $target -Lines $lines
$target
