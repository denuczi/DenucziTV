import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/errors/app_exception.dart';
import 'package:denuczi_tv/core/network/user_agent.dart';

void main() {
  group('UserAgent', () {
    test('accepts a conventional user agent', () {
      expect(
        UserAgent.validate('ExamplePlayer/1.0 (Linux; x86_64)'),
        'ExamplePlayer/1.0 (Linux; x86_64)',
      );
    });

    test('trims outer spaces', () {
      expect(UserAgent.validate('  Example/1.0  '), 'Example/1.0');
    });

    test('rejects blank and oversized values', () {
      expect(() => UserAgent.validate('  '), throwsA(isA<AppException>()));
      expect(
        () => UserAgent.validate(List.filled(257, 'A').join()),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects HTTP header injection and non ASCII characters', () {
      expect(
        () => UserAgent.validate('Client\r\nX-Injected: yes'),
        throwsA(isA<AppException>()),
      );
      expect(
        () => UserAgent.validate('Client/1.0 🌟'),
        throwsA(isA<AppException>()),
      );
    });
  });
}
