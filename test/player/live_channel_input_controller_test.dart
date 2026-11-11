import 'package:denuczi_tv/features/player/application/live_channel_input_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('submits five seconds after last digit, not first', (
    tester,
  ) async {
    final updates = <String>[];
    final submitted = <int>[];
    final input = LiveChannelInputController(
      onChanged: updates.add,
      onSubmitted: submitted.add,
    );
    input.addDigit(1);
    await tester.pump(const Duration(seconds: 4));
    input.addDigit(5);
    await tester.pump(const Duration(seconds: 4));
    expect(submitted, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(submitted, [15]);
    expect(updates, ['1', '15', '']);
    input.dispose();
  });

  testWidgets('supports backspace, enter, escape and invalid digits', (
    tester,
  ) async {
    final submitted = <int>[];
    final input = LiveChannelInputController(
      onChanged: (_) {},
      onSubmitted: submitted.add,
    );
    input.addDigit(1);
    input.addDigit(9);
    input.backspace();
    input.addDigit(2);
    input.submitNow();
    expect(submitted, [12]);
    input.addDigit(0);
    input.clear();
    await tester.pump(const Duration(seconds: 6));
    expect(submitted, [12]);
    input.addDigit(-1);
    input.addDigit(10);
    expect(input.digits, isEmpty);
    input.dispose();
  });

  testWidgets('bounds buffer and cancels timers on dispose', (tester) async {
    final submitted = <int>[];
    final input = LiveChannelInputController(
      onChanged: (_) {},
      onSubmitted: submitted.add,
      maxDigits: 3,
    );
    for (final digit in [1, 2, 3, 4, 5]) {
      input.addDigit(digit);
    }
    expect(input.digits, '123');
    input.dispose();
    await tester.pump(const Duration(seconds: 6));
    expect(submitted, isEmpty);
  });

  test(
    'maps numeric row, keypad and navigation keys without stealing others',
    () {
      expect(LiveChannelKeys.digit(LogicalKeyboardKey.digit7), 7);
      expect(LiveChannelKeys.digit(LogicalKeyboardKey.numpad0), 0);
      expect(LiveChannelKeys.digit(LogicalKeyboardKey.space), isNull);
      expect(LiveChannelKeys.direction(LogicalKeyboardKey.arrowUp), -1);
      expect(LiveChannelKeys.direction(LogicalKeyboardKey.keyW), -1);
      expect(LiveChannelKeys.direction(LogicalKeyboardKey.arrowDown), 1);
      expect(LiveChannelKeys.direction(LogicalKeyboardKey.keyS), 1);
      expect(LiveChannelKeys.direction(LogicalKeyboardKey.arrowLeft), isNull);
    },
  );
}
