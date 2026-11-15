# Handoff

Open items for whoever works on this repo next. Remove an item once it's resolved, and add anything you leave open, with how sure you are.

## Known issues (found in review, not reproduced)
- **Possible double fire at launch.** A process's first run reschedules every reminder. If one comes due between computing the schedule and the call that schedules it, the gateway's 2 s clamp (`flutter_notification_gateway.dart`) schedules it again. The window is under a second.
- **13+ reminders in the same minute spill into the next one.** Spacing (`ScheduleEngine._applyMicroOffsets`) is 5 s per reminder, so the 13th lands on the next minute and can share an exact instant with a reminder set for that minute.
- **Unreadable stored trips can't be recovered in the app.** `PrefsTripStore.load()` throws on purpose so nothing is overwritten. The Trips tab shows the error, and nothing can be added until the data is cleared.

## Not verified on a device
- **Force-stop recovery on Android 14 or older.** Checked only on an API 36 emulator with the plugin's boot receiver removed, which stands in for the older behaviour.
- **The trip form's Back-blocking and the controller fixes from PR #6.** Covered by widget and unit tests only.
