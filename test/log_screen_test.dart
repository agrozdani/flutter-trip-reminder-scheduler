import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_reminder_scheduler/src/app/providers.dart';
import 'package:trip_reminder_scheduler/src/app/screens/log_screen.dart';
import 'package:trip_reminder_scheduler/src/core/logging.dart';

void main() {
  testWidgets('the log screen filters by level, copies, and fits a narrow '
      'screen with large text', (tester) async {
    // 320 dp wide, as on an iPhone SE (1st generation), with text at 200%.
    tester.view.physicalSize = const Size(960, 2400);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final buffer = LogBuffer();
    final log = Logger([buffer], tag: 'scheduler');
    log.debug('run.plan', {'toSchedule': 5});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [logBufferProvider.overrideWithValue(buffer)],
        child: const MaterialApp(home: LogScreen()),
      ),
    );
    // Written while the screen is open: it shows up without a refresh.
    log.warning('schedule.clamped', {'id': 7, 'reason': 'came due mid-run'});
    await tester.pumpAndSettle();

    expect(find.textContaining('scheduler run.plan'), findsOneWidget);
    expect(find.textContaining('scheduler schedule.clamped'), findsOneWidget);
    expect(find.text('id=7 reason="came due mid-run"'), findsOneWidget);

    await tester.tap(find.text('warning'));
    await tester.pumpAndSettle();
    expect(find.textContaining('scheduler run.plan'), findsNothing);

    await tester.tap(find.byTooltip('Copy'));
    await tester.pumpAndSettle();
    expect(copied, contains(' W scheduler schedule.clamped id=7'));
    expect(copied, isNot(contains('run.plan')));
    expect(find.text('Log copied'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing logged at this level'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
