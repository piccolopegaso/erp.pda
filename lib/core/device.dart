import 'package:flutter/services.dart';

import 'settings.dart';

enum Beep { ok, error, warn, double }

/// Thin wrapper around the native channel in MainActivity.kt.
class Device {
  Device(this.settings);

  final AppSettings settings;
  static const _ch = MethodChannel('mic_pda/device');

  Future<void> configureScanner() async {
    try {
      await _ch.invokeMethod('configureScanner', {
        'actions': settings.scannerActions,
        'extras': settings.scannerExtras,
      });
    } catch (_) {}
  }

  Future<void> keepScreenOn(bool on) async {
    try {
      await _ch.invokeMethod('keepScreenOn', {'on': on});
    } catch (_) {}
  }

  Future<Map<String, dynamic>> info() async {
    try {
      final r = await _ch.invokeMethod('deviceInfo');
      return Map<String, dynamic>.from(r as Map);
    } catch (_) {
      return {};
    }
  }

  /// Audible + haptic feedback, honoring the user's settings.
  void feedback(Beep b) {
    if (settings.sound) {
      _ch.invokeMethod('beep', {'type': b.name}).catchError((_) {});
    }
    if (settings.vibrate) {
      final ms = switch (b) {
        Beep.ok => 60,
        Beep.warn => 250,
        Beep.error => 600,
        Beep.double => 150,
      };
      _ch.invokeMethod('vibrate', {'ms': ms}).catchError((_) {});
    }
  }

  void ok() => feedback(Beep.ok);
  void error() => feedback(Beep.error);
  void warn() => feedback(Beep.warn);
}
