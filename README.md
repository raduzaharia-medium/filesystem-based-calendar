# powershell-calendar-scripts

A calendar with no database. Folders are calendars, files are events, and **the file name is the index**.

An `.ics` file is already a complete event, and a filesystem already knows how to store, list, sort, move and
delete files. These scripts add one convention on top: put the facts you query by (when, and what) into the
file name. Everything else is ordinary file operations.

## How the pieces map

| A database would have... | Here it is... |
|---|---|
| a table of events | a folder of `.ics` files |
| indexed columns (start, end, title) | the file name |
| the full record | the `.ics` content (description, location, alarms, whatever the format allows) |
| several calendars / categories | several folders |
| `UPDATE status = 'done'` | moving the file to another folder |
| `DELETE` | deleting the file |
| a query | listing a folder and parsing names |
| a backup, sync or history | copy the folder, `git`, Dropbox, rsync... |

Because a name is just text, the calendar is readable and editable with a file manager, `ls`, or a text editor.
You can create an event by saving a file, and reschedule it by renaming it.

## Layout

    Current/       events that are still to come
    Archive/<x>/   finished events that asked to be kept, grouped by <x>
    Recurring/     yearly events (birthdays and the like)

The scripts work in the current directory, or wherever `-Root` / `$env:CALENDAR_ROOT` points.
The folders are created as needed.

## The file name

    YYYY-MM-DD[ - YYYY-MM-DD][ (HH MM - HH MM)] - Summary.ics

| Name | Meaning |
|---|---|
| `2026-05-01 - Labour Day.ics` | single all-day event |
| `2026-08-01 - 2026-08-14 - Holiday.ics` | all-day range; the second date is the **last day, inclusive** |
| `2026-10-05 (14 30 - 15 15) - Dentist.ics` | timed event, 24-hour, hours and minutes separated by a space |

Rules that make it parseable without ambiguity:

- The dates and the time block always come first and have fixed shapes, so the summary can contain anything
  else, including hyphens (`Jean-Luc - dentist`), dashes and commas. Only characters that are not allowed in
  file names (`/ \ : * ? " < > |`) are replaced with `-`.
- Times use a space instead of `:` because `:` is not allowed in file names on Windows.
- Names sort chronologically, so a plain directory listing is already an agenda.
- An event cannot cross midnight: a timed event lives on a single day.
- A file whose name does not follow the pattern is reported and skipped, never guessed at.

## The `.ics` content

The scripts trust the name for scheduling and only look inside the file for one thing: an optional line

    X-ARCHIVE:<folder>

which says where the event should go once it is over. Without it, a finished event is deleted. Everything else in
the file is for calendar apps and for you; import it into any client and it is a normal event.
Keep the name and the `DTSTART`/`DTEND` in agreement (`createEvent.ps1` and `icssplitter.ps1` do this for you).
If you rename a file by hand, the scripts follow the new name.

## What the scripts do, in terms of the filesystem

| Script | Operation |
|---|---|
| `createEvent.ps1` | writes a new `.ics` and derives its name from the details you give |
| `archiveOldEvents.ps1` | lists `Current`, parses names, and moves (or deletes) files whose end has passed. `-WhatIf` shows what it would do |
| `handleRecurring.ps1` | for each file in `Recurring`, writes this year's (or next year's) copy into `Current` if it falls within `-LookaheadDays` (default 90) and is not there yet. Safe to run repeatedly |
| `notifyEvents.ps1` | lists `Current` and sends Today / Tomorrow / Upcoming notifications built from the names alone. `-Console` prints instead |
| `executeCalendarTasks.ps1` | archive, then recurring, then notify: what a daily scheduled task should run |
| `renderHtml.ps1` | reads every folder and draws a one-page year view (`-Year`, `-OutFile`) |
| `icssplitter.ps1` | takes one big export from another calendar app and writes one correctly named file per event |

None of them keeps state anywhere except in the files and folders. There is no index to rebuild or corrupt:
if the files are right, the calendar is right.

## A day in the life

    ./createEvent.ps1 -Summary 'Dentist' -StartDate 2026-10-05 -TimeInterval '14:30 - 15:15' -ArchiveFolder Health
    #   -> Current/2026-10-05 (14 30 - 15 15) - Dentist.ics

    ./notifyEvents.ps1 -Console        # what is on today, tomorrow, later
    ./archiveOldEvents.ps1 -WhatIf     # after 15:15 on the 5th: would move it to Archive/Health/

Schedule `executeCalendarTasks.ps1` once a day (Task Scheduler on Windows, cron/launchd elsewhere).

## Trade-offs

- Queries are limited to what the name encodes (when and what). Anything else means opening files.
- Rescheduling means renaming; the script that does it must also update `DTSTART`/`DTEND` if you want the content
  to agree, though the scripts here only depend on the name.
- Listing a folder is fast up to many thousands of files, which is far more events than a personal calendar has.
  `Archive` keeps `Current` small.
- There is no locking: this is a single-user tool. Sync tools that copy the folder work well because each event
  is its own file (two devices editing different events never conflict).

## Requirements

PowerShell 7. Notifications: on Windows install the [BurntToast](https://github.com/Windos/BurntToast) module
(`Install-Module BurntToast`); macOS and Linux use their built-in notification tools; otherwise output goes to
the console. `createEvent.ps1` shows a dialog on Windows when run without parameters, and prompts elsewhere.
