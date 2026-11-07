import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/shared/navigation/dialog_launch_guard.dart';

void main() {
  test('rapid launches are ignored until the first route closes', () async {
    final guard = DialogLaunchGuard();
    final pending = Completer<void>();
    var opened = 0;
    final first = guard.run(() {
      opened++;
      return pending.future;
    });
    await guard.run(() async {
      opened++;
    });
    expect(opened, 1);
    expect(guard.isBusy, isTrue);

    pending.complete();
    await first;
    expect(guard.isBusy, isFalse);

    await guard.run(() async {
      opened++;
    });
    expect(opened, 2);
  });

  test('a failed route releases the guard', () async {
    final guard = DialogLaunchGuard();
    await expectLater(
      guard.run(() async {
        throw StateError('route failed');
      }),
      throwsStateError,
    );
    expect(guard.isBusy, isFalse);
    var recovered = false;
    await guard.run(() async {
      recovered = true;
    });
    expect(recovered, isTrue);
  });
}
