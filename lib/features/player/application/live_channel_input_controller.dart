import 'dart:async';

import 'package:flutter/services.dart';

/// Buffers remote-control digits and submits the complete number five seconds
/// after the final keypress. No timers survive dispose or explicit clear.
class LiveChannelInputController {
  LiveChannelInputController({
    required this.onChanged,
    required this.onSubmitted,
    this.delay = const Duration(seconds: 5),
    this.maxDigits = 7,
  });

  final void Function(String) onChanged;
  final void Function(int) onSubmitted;
  final Duration delay;
  final int maxDigits;
  Timer? _timer;
  String _digits = '';
  bool _disposed = false;

  String get digits => _digits;

  void addDigit(int digit) {
    if (_disposed || digit < 0 || digit > 9) return;
    // Keep the buffer bounded even when a key repeats unexpectedly.
    if (_digits.length >= maxDigits) {
      _timer?.cancel();
      _timer = Timer(delay, _submit);
      return;
    }
    _digits += digit.toString();
    onChanged(_digits);
    _timer?.cancel();
    _timer = Timer(delay, _submit);
  }

  void backspace() {
    if (_disposed || _digits.isEmpty) return;
    _timer?.cancel();
    _digits = _digits.substring(0, _digits.length - 1);
    onChanged(_digits);
    if (_digits.isNotEmpty) _timer = Timer(delay, _submit);
  }

  void submitNow() {
    if (_disposed) return;
    _timer?.cancel();
    _submit();
  }

  void _submit() {
    if (_disposed || _digits.isEmpty) return;
    final number = int.tryParse(_digits);
    _digits = '';
    onChanged('');
    if (number != null) onSubmitted(number);
  }

  void clear() {
    if (_disposed) return;
    _timer?.cancel();
    if (_digits.isEmpty) return;
    _digits = '';
    onChanged('');
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _digits = '';
  }
}

/// Only player-navigation keys are intercepted. All other keys, including
/// space, left/right, escape (without pending digits), and media shortcuts,
/// remain available to the native video controls.
class LiveChannelKeys {
  const LiveChannelKeys._();

  static const _digits = [
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
  static const _numpad = [
    LogicalKeyboardKey.numpad0,
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];

  static int? digit(LogicalKeyboardKey key) {
    final standard = _digits.indexOf(key);
    if (standard >= 0) return standard;
    final numericPad = _numpad.indexOf(key);
    return numericPad < 0 ? null : numericPad;
  }

  static int? direction(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyW) {
      return -1;
    }
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.keyS) {
      return 1;
    }
    return null;
  }
}
