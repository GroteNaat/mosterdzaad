import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosterdzaad/sync/sync_trigger.dart';

void main() {
  testWidgets('Idle time never contacts Dropbox', (tester) async {
    var calls = 0;
    final trigger = SyncTrigger(
      canRun: () => true,
      synchronize: () async => calls++,
    );
    addTearDown(trigger.dispose);
    await tester.pump(const Duration(hours: 12));
    expect(calls, 0);
    trigger.request();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    await tester.pump(const Duration(hours: 12));
    expect(calls, 1);
  });

  testWidgets('Startup and duplicate focus events wait for a busy controller', (
    tester,
  ) async {
    var busy = true, calls = 0;
    final trigger = SyncTrigger(
      canRun: () => !busy,
      synchronize: () async => calls++,
    );
    addTearDown(trigger.dispose);
    trigger.request();
    trigger.request();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 0);
    busy = false;
    trigger.wake();
    await tester.pump();
    expect(calls, 1);
    await tester.pump(const Duration(minutes: 5));
    expect(calls, 1);
  });

  testWidgets('Rapid saves are batched two seconds after the last save', (
    tester,
  ) async {
    var calls = 0;
    final trigger = SyncTrigger(
      canRun: () => true,
      synchronize: () async => calls++,
    );
    addTearDown(trigger.dispose);
    trigger.request(delay: const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    trigger.request(delay: const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
  });

  testWidgets('Edits during a transfer queue one follow-up without overlap', (
    tester,
  ) async {
    var calls = 0;
    final finished = Completer<void>();
    final trigger = SyncTrigger(
      canRun: () => true,
      synchronize: () async {
        calls++;
        if (calls == 1) await finished.future;
      },
    );
    addTearDown(trigger.dispose);
    trigger.request();
    await tester.pump(const Duration(seconds: 1));
    trigger.request(delay: const Duration(seconds: 2));
    trigger.request(delay: const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 3));
    expect(calls, 1);
    finished.complete();
    await tester.pump();
    expect(calls, 2);
    await tester.pump(const Duration(minutes: 5));
    expect(calls, 2);
  });

  testWidgets('Offline work waits for a new event instead of polling', (
    tester,
  ) async {
    var calls = 0;
    final trigger = SyncTrigger(
      canRun: () => true,
      // Controller catches the network error and retains its durable outbox.
      synchronize: () async => calls++,
    );
    addTearDown(trigger.dispose);
    trigger.request();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(hours: 1));
    expect(calls, 1);
    trigger.request(); // OS/browser connectivity-restored notification.
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 2);
  });

  testWidgets('Closing or disconnecting cancels a queued save', (tester) async {
    var calls = 0;
    final trigger = SyncTrigger(
      canRun: () => true,
      synchronize: () async => calls++,
    );
    trigger.request(delay: const Duration(seconds: 2));
    trigger.cancel();
    await tester.pump(const Duration(seconds: 3));
    expect(calls, 0);
    trigger.request();
    trigger.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 0);
  });
}
