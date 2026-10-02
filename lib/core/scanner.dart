import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'settings.dart';

typedef ScanHandler = void Function(String code);

/// Collects barcodes from
///  1. hardware scanner broadcasts (native EventChannel, see MainActivity.kt)
///  2. keyboard-wedge scanners (fast key events terminated by Enter)
/// and delivers each code to the top-most registered handler only,
/// so a scan never reaches a screen that is not visible.
class ScannerService {
  ScannerService(this.settings);

  final AppSettings settings;
  static const _events = EventChannel('mic_pda/scan');

  final List<_Registration> _stack = [];
  StreamSubscription? _sub;
  String _lastCode = '';
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  final StringBuffer _wedge = StringBuffer();
  DateTime _wedgeLastKey = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _wedgeIdle;

  /// Last raw code seen by the service (for the settings test area).
  final ValueNotifier<String> lastRaw = ValueNotifier('');

  void start() {
    _sub ??= _events.receiveBroadcastStream().listen((e) {
      if (e is Map && e['code'] is String) {
        dispatch(e['code'] as String);
      }
    }, onError: (_) {});
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    HardwareKeyboard.instance.removeHandler(_onKey);
  }

  /// [isActive] lets a screen refuse scans while it is covered (e.g. a dialog or another page on top).
  Object register(ScanHandler handler, {bool Function()? isActive}) {
    final r = _Registration(handler, isActive);
    _stack.add(r);
    return r;
  }

  void unregister(Object token) {
    _stack.remove(token);
  }

  /// Entry point for every code (hardware, wedge, or typed manually).
  void dispatch(String raw, {bool manual = false}) {
    final code = _clean(raw);
    if (code.isEmpty) return;
    final now = DateTime.now();
    if (!manual && code == _lastCode && now.difference(_lastAt).inMilliseconds < settings.dedupMs) {
      return; // scanner bounce
    }
    _lastCode = code;
    _lastAt = now;
    lastRaw.value = code;
    if (_stack.isEmpty) return;
    final top = _stack.last;
    if (top.isActive != null && !top.isActive!()) return;
    top.handler(code);
  }

  static String _clean(String raw) {
    // strip control chars (GS1 group separators, CR/LF from some scanners) and surrounding spaces
    return raw.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
  }

  bool _textInputFocused() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.findAncestorStateOfType<EditableTextState>() != null;
  }

  bool _onKey(KeyEvent e) {
    if (!settings.wedgeEnabled) return false;
    if (_textInputFocused()) return false; // a text field consumes the input itself
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return false;

    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.tab) {
      if (_wedge.isEmpty) return false;
      _flushWedge();
      return true;
    }
    final ch = e.character;
    if (ch == null || ch.isEmpty || ch.codeUnitAt(0) < 32) return false;

    final now = DateTime.now();
    // a human typing is much slower than a scanner; a long gap starts a new code
    if (now.difference(_wedgeLastKey).inMilliseconds > 120) {
      _wedge.clear();
    }
    _wedgeLastKey = now;
    _wedge.write(ch);
    // scanners configured without an Enter suffix: emit after a short idle period
    _wedgeIdle?.cancel();
    _wedgeIdle = Timer(const Duration(milliseconds: 250), () {
      if (_wedge.length >= 4) _flushWedge();
    });
    return true;
  }

  void _flushWedge() {
    _wedgeIdle?.cancel();
    final code = _wedge.toString();
    _wedge.clear();
    if (code.isNotEmpty) dispatch(code);
  }
}

class _Registration {
  _Registration(this.handler, this.isActive);
  final ScanHandler handler;
  final bool Function()? isActive;
}
