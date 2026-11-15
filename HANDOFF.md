# Handoff

Open items for whoever works on this repo next. Remove an item once it's resolved, and add anything you leave open, with how sure you are.

## Known issues (found in review, not reproduced)
- **Possible double fire at launch.** A process's first run reschedules every reminder. If one comes due between computing the schedule and the call that schedules it, the gateway's 2 s clamp (`flutter_notification_gateway.dart`) schedules it again. The window is under a second.
- **13+ reminders in the same minute spill into the next one.** Spacing (`ScheduleEngine._applyMicroOffsets`) is 5 s per reminder, so the 13th lands on the next minute and can share an exact instant with a reminder set for that minute.
- **Unreadable stored trips can't be recovered in the app.** `PrefsTripStore.load()` throws on purpose so nothing is overwritten. The Trips tab shows the error, and nothing can be added until the data is cleared.
- **A corrupt registry loads as empty.** `PrefsRegistryStore.load()` still returns an empty registry on a decode failure, unlike the trip store. The run that loads it reschedules and records every wanted reminder, but one already pending that isn't wanted any more (its trip deleted in that run, say) is in no registry and is never cancelled. Read from the code; not tested.

## Known issues (reproduced in unit tests, not fixed)
- **Deleting a trip inside a same-minute group's spacing window cancels a sibling.** Trips A, B and C fire at :00, :05 and :10. Delete A at :03: B's offset drops to +0, which has passed, so the diff cancels B 2 s before it fires, and it doesn't fire that day. Any change to a group's members inside its window does the same (a live-location change that moves one out of the minute, for one). The window is 5 s per later member. A fix would keep a still-pending reminder whose new instant spacing alone moved into the past, at the cost of two reminders sharing an instant once.
- **With a live location set, a day can fire twice, or be lost, when the home-zone date rolls over.** "Today" is the home-zone date, and only today uses the live zone. Home Auckland, destination United States, live zone London: on 12 June the 12th fires at 09:00 London (08:00Z). At 12:30Z the 13th has begun in Auckland, so the 12th is recomputed in New York (13:00Z), still ahead, and scheduled again. With other zones the recomputed instant has passed and the pending reminder is cancelled instead. Predates PR #6; deciding which zone a day keeps once it has passed is a design question.

## Not verified on a device
- **Force-stop recovery on Android 14 or older.** Checked only on an API 36 emulator with the plugin's boot receiver removed, which stands in for the older behaviour.
- **The trip form on iOS, and the controller fixes from PR #6.** On an API 36 emulator, a Back pressed during a save and a date picker tapped during a save were each checked against builds from before and after their fix (Save, then the second input, 10–60 ms apart). On iOS, that a held Back also blocks the edge swipe comes from Flutter's `ModalRoute.popGestureEnabled`, not from a run. The controller fixes are covered by unit tests only.
- **Recording a run that fails partway.** Unit tests only: no device run produced a partial failure (some `zonedSchedule` calls succeeding, then one throwing).
