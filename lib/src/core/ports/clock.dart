/// The time seam for the whole core.
///
/// Nothing in `core/` ever calls `DateTime.now()` directly. Code that needs the
/// current instant either takes a `now` argument (the pure engine and recovery
/// functions) or reads `package:clock`'s ambient [clock]. Tests then override
/// time with `withClock(Clock.fixed(...), ...)` or `fakeAsync(...)` and never
/// depend on the real wall clock — which is exactly why every timezone, travel
/// and DST scenario is reproducible.
library;

export 'package:clock/clock.dart' show Clock, clock;
