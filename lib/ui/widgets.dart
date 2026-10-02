import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/device.dart';
import '../core/history.dart';
import '../core/i18n.dart';
import '../core/net_monitor.dart';
import 'el.dart';

/// Human readable, localized message for any error thrown by the API layer.
String errorText(Object e) {
  if (e is ApiException) {
    switch (e.kind) {
      case FailKind.notSent:
        return tr('pda.err.notSent');
      case FailKind.unknown:
        return tr('pda.err.unknown');
      case FailKind.auth:
        return tr('pda.err.auth');
      case FailKind.server:
        if (e.code == 'HTTP400') return tr('pda.err.http400');
        return tr('pda.err.server', {'code': e.code});
      case FailKind.business:
        return e.message.isNotEmpty ? e.message : e.code;
    }
  }
  return '$e';
}

bool isUnknown(Object e) => e is ApiException && e.kind == FailKind.unknown;

Outcome outcomeOf(Object e) => isUnknown(e) ? Outcome.unknown : Outcome.error;

/// Network quality indicator for the (white) navbar.
class NetBadge extends StatelessWidget {
  const NetBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final net = AppScope.of(context).net;
    return AnimatedBuilder(
      animation: net,
      builder: (context, _) {
        final color = switch (net.state) {
          NetState.good => El.success,
          NetState.slow => El.warning,
          NetState.offline => El.danger,
        };
        return InkWell(
          onTap: net.probe,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Icon(net.state == NetState.offline ? Icons.wifi_off : Icons.wifi, size: 20, color: color),
          ),
        );
      },
    );
  }
}

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final net = AppScope.of(context).net;
    return AnimatedBuilder(
      animation: net,
      builder: (context, _) {
        if (net.state == NetState.good) return const SizedBox.shrink();
        final offline = net.state == NetState.offline;
        return Container(
          width: double.infinity,
          color: offline ? El.danger : El.warning,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(tr(offline ? 'pda.net.offline' : 'pda.net.slow'),
              style: const TextStyle(color: Colors.white, fontSize: 12.5)),
        );
      },
    );
  }
}

PreferredSizeWidget elAppBar(String title, {List<Widget> actions = const []}) {
  return AppBar(
    title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
    actions: [...actions, const NetBadge()],
  );
}

Future<String?> askCode(BuildContext context, {String? title, String initial = '', TextInputType? keyboard}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title ?? tr('pda.inputCode'), style: const TextStyle(fontSize: 16)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: keyboard,
        textInputAction: TextInputAction.done,
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('common.cancelButtonText'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(tr('common.confirmButtonText'))),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String message, {String? title, String? okText, bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: title == null ? null : Text(title, style: const TextStyle(fontSize: 16)),
      content: Text(message, style: const TextStyle(fontSize: 15)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('common.cancelButtonText'))),
        FilledButton(
          style: danger ? elButton(ElType.danger) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(okText ?? tr('common.confirmButtonText')),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// el-message-box alert (single OK button).
Future<void> alertBox(BuildContext context, String title, String message, {ElType type = ElType.warning}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(type == ElType.danger ? Icons.cancel : Icons.warning_rounded, color: elColor(type), size: 36),
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: Text(message, style: const TextStyle(fontSize: 15)),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );
}

/// el-message
void toast(BuildContext context, String msg, {ElType type = ElType.info}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(
    content: Text(msg, style: const TextStyle(fontSize: 14)),
    backgroundColor: type == ElType.info ? const Color(0xFF606266) : elColor(type),
    duration: Duration(seconds: type == ElType.danger ? 6 : 3),
    behavior: SnackBarBehavior.floating,
  ));
}

/// Common behaviour of every scanning screen (web: components/Widget/ScannerInput):
///  - receives scans only while it is the visible route
///  - one scan at a time (a scan while busy is rejected with a warning beep)
///  - optional "scan twice to confirm" (requiredScans = 2), with the web's
///    "Scanning Progress" / "Just scanned" / "Scanning is not consistent" texts
///  - manual entry
mixin ScanPageMixin<T extends StatefulWidget> on State<T> {
  Object? _scanToken;
  AppState? _app;
  bool busy = false;

  final List<String> _confirmBuffer = [];
  String? lastScanned;
  String? scanError;

  /// Module name (i18n key) used in the scan history.
  String get moduleName;

  /// How many identical scans are needed before [onScan] is called.
  int get requiredScans => 1;

  Future<void> onScan(String code);

  AppState get app => _app ??= AppScope.of(context);

  String? get scanProgress => _confirmBuffer.isEmpty || requiredScans < 2
      ? null
      : '${tr('wms.scanProgress')}: ${_confirmBuffer.length} / $requiredScans';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app ??= AppScope.of(context);
    _scanToken ??= app.scanner.register(handleScan, isActive: () => mounted && (ModalRoute.of(context)?.isCurrent ?? false));
  }

  @override
  void dispose() {
    if (_scanToken != null) _app?.scanner.unregister(_scanToken!);
    super.dispose();
  }

  void resetScanConfirm() => _confirmBuffer.clear();

  void handleScan(String code) async {
    if (busy) {
      app.device.warn();
      toast(context, tr('pda.busyWait'), type: ElType.warning);
      return;
    }
    if (requiredScans > 1) {
      _confirmBuffer.add(code);
      if (_confirmBuffer.length < requiredScans) {
        app.device.ok();
        setState(() => scanError = null);
        return;
      }
      final same = _confirmBuffer.every((c) => c == _confirmBuffer.first);
      _confirmBuffer.clear();
      if (!same) {
        app.device.feedback(Beep.double);
        setState(() => scanError = tr('wms.reScan'));
        return;
      }
    }
    setState(() {
      busy = true;
      scanError = null;
      lastScanned = requiredScans > 1 ? '${tr('wms.lastScanned')}: $code' : null;
    });
    try {
      await onScan(code);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> manualEntry() async {
    final code = await askCode(context);
    if (code == null || code.isEmpty) return;
    // a typed code does not need the double-scan confirmation
    _confirmBuffer
      ..clear()
      ..addAll(List.filled(requiredScans - 1, code));
    handleScan(code);
  }

  void log(String code, Outcome o, [String msg = '']) => app.history.add(moduleName, code, o, msg);
}

/// Standard scaffold for scan screens: navbar, offline banner, scanner bar, content.
/// The content jumps back to the top after every scan so the new result is visible.
class ScanScaffold extends StatefulWidget {
  const ScanScaffold({
    super.key,
    required this.title,
    required this.placeholder,
    required this.onManual,
    required this.busy,
    required this.children,
    this.actions = const [],
    this.bottom,
    this.progress,
    this.lastScanned,
    this.scanError,
    this.disabled = false,
    this.header,
    this.onRefresh,
  });

  final String title;
  final String placeholder;
  final VoidCallback onManual;
  final bool busy;
  final bool disabled;
  final List<Widget> children;
  final List<Widget> actions;
  final Widget? bottom;
  final Widget? header;
  final String? progress;
  final String? lastScanned;
  final String? scanError;
  final Future<void> Function()? onRefresh;

  @override
  State<ScanScaffold> createState() => _ScanScaffoldState();
}

class _ScanScaffoldState extends State<ScanScaffold> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(ScanScaffold old) {
    super.didUpdateWidget(old);
    if (old.busy && !widget.busy && _scroll.hasClients && _scroll.offset > 0) {
      _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final list = ListView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 16),
      children: w.children,
    );
    return Scaffold(
      appBar: elAppBar(w.title, actions: w.actions),
      body: Column(children: [
        const OfflineBanner(),
        if (w.header != null) w.header!,
        ScannerBar(
          placeholder: w.placeholder,
          onManual: w.onManual,
          busy: w.busy,
          disabled: w.disabled,
          progress: w.progress,
          lastScanned: w.lastScanned,
          error: w.scanError,
        ),
        Expanded(child: w.onRefresh == null ? list : RefreshIndicator(onRefresh: w.onRefresh!, child: list)),
        if (w.bottom != null) w.bottom!,
      ]),
    );
  }
}

/// Parses a JSON value that may already be decoded or still be a JSON string.
List<Map<String, dynamic>> jsonList(dynamic v) {
  final d = jsonAny(v);
  if (d is List) {
    return d.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }
  return [];
}

dynamic jsonAny(dynamic v) {
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }
  return v;
}

int asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

String asStr(dynamic v) => v == null ? '' : '$v';

String fmtTime(dynamic v) {
  final s = asStr(v);
  if (s.isEmpty || s.startsWith('0001-01-01')) return '';
  final d = DateTime.tryParse(s);
  if (d == null) return s;
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}
