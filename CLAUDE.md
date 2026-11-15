# Agent notes

Public reference repo: correctness and small diffs over speed.

## Workflow
- Never guess or assume. Verify every claim and change by running it, testing it, or reading the source (including package sources in the pub cache) before reporting it.
- Assess and propose the simplest fix before editing.
- Bugs: write a failing test first, then check it fails with the fix reverted.
- No CI. Run `flutter analyze` and `flutter test` yourself.
- When the test count changes, update the README badge, the "The N tests" line and the test list.

## Traps
- Riverpod 3: in a widget, `ref` after unmount throws `StateError`, release builds too. Check `mounted` after every `await`.
- Riverpod 3 retries a provider that fails with an `Exception` for ~38 s, and `future` waits. Set `retry: (_, _) => null` if retrying can't help.
- Android: `pendingNotificationRequests` is the plugin's saved copy, not `AlarmManager`. That's why a process's first run hands every reminder back to the OS.
- All trip changes go through `TripsController._mutate`, which runs saves one at a time.

## Handoff
Read `HANDOFF.md` before starting. When you finish, add anything you leave open and remove anything you resolved.
