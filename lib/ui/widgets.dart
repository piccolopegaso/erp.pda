import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/history.dart';
import '../core/i18n.dart';
import '../core/net_monitor.dart';

/// Human readable, localized message for any error thrown by the API layer.
String errorText(Object e) {
  if (e is ApiException) {
    switch (e.kind) {
      case FailKind.notSent:
        return tr('err.network.notSent');
      case FailKind.unknown:
        return tr('err.network.unknown');
      case FailKind.auth:
        return tr('err.auth');
      case FailKind.server:
        if (e.code == 'HTTP400') return tr('err.http400');
        return tr('err.server', {'code': e.code});
      case FailKind.business:
        return e.message.isNotEmpty ? e.message : e.code;
    }
  }
  return '$e';
}

Outcome outcomeOf(Object e) {
  if (e is ApiException && e.kind == FailKind.unknown) return Outcome.unknown;
  return Outcome.error;
}

enum Tone { info, ok, warn, error, unknown }

Color toneColor(Tone t) => switch (t) {
      Tone.info => const Color(0xFF1565C0),
      Tone.ok => const Color(0xFF2E7D32),
      Tone.warn => const Color(0xFFEF6C00),
      Tone.error => const Color(0xFFC62828),
      Tone.unknown => const Color(0xFF6A1B9A),
    };

IconData toneIcon(Tone t) => switch (t) {
      Tone.info => Icons.qr_code_scanner,
      Tone.ok => Icons.check_circle,
      Tone.warn => Icons.warning_amber_rounded,
      Tone.error => Icons.cancel,
      Tone.unknown => Icons.help,
    };

/// The big colored result card at the top of every scan screen.
class StatusCard extends StatelessWidget {
  const StatusCard({super.key, required this.tone, required this.title, this.subtitle, this.trailing});

  final Tone tone;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = toneColor(tone);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        border: Border.all(color: c, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(toneIcon(tone), color: c, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c)),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: const TextStyle(fontSize: 15, color: Color(0xFF333333))),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A titled block of label/value rows.
class InfoSection extends StatelessWidget {
  const InfoSection({super.key, this.title, required this.rows});

  final String? title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final visible = rows.where((r) => r.$2.trim().isNotEmpty).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(title!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const Divider(height: 14),
            ],
            for (final r in visible)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 92, child: Text(r.$1, style: const TextStyle(color: Color(0xFF777777)))),
                    Expanded(child: SelectableText(r.$2, style: const TextStyle(fontSize: 15))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class NetBadge extends StatelessWidget {
  const NetBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final net = AppScope.of(context).net;
    return AnimatedBuilder(
      animation: net,
      builder: (context, _) {
        final (color, label) = switch (net.state) {
          NetState.good => (Colors.greenAccent, tr('net.good')),
          NetState.slow => (Colors.amberAccent, tr('net.slow')),
          NetState.offline => (Colors.redAccent, tr('net.offline')),
        };
        return InkWell(
          onTap: net.probe,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle, size: 11, color: color),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.white)),
            ]),
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
        if (net.state != NetState.offline) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          color: const Color(0xFFC62828),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(tr('net.offlineBanner'), style: const TextStyle(color: Colors.white, fontSize: 13)),
        );
      },
    );
  }
}

/// Prompt line telling the operator what to scan next, with a manual-entry button.
class ScanPrompt extends StatelessWidget {
  const ScanPrompt({super.key, required this.text, required this.onManual, this.busy = false});

  final String text;
  final VoidCallback onManual;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF263238),
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      child: Row(children: [
        if (busy)
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
        else
          const Icon(Icons.qr_code_scanner, color: Colors.white, size: 24),
        const SizedBox(width: 10),
        Expanded(
          child: Text(busy ? tr('common.loading') : text,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        IconButton(
          tooltip: tr('common.manualInput'),
          onPressed: onManual,
          icon: const Icon(Icons.keyboard, color: Colors.white),
        ),
      ]),
    );
  }
}

Future<String?> askCode(BuildContext context, {String? title, String initial = ''}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title ?? tr('common.inputCode')),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('common.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(tr('common.ok'))),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String message, {String? okText}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message, style: const TextStyle(fontSize: 16)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('common.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(okText ?? tr('common.confirm'))),
      ],
    ),
  );
  return r ?? false;
}

void toast(BuildContext context, String msg, {Tone tone = Tone.info}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(
    content: Text(msg, style: const TextStyle(fontSize: 15)),
    backgroundColor: tone == Tone.info ? null : toneColor(tone),
    duration: Duration(seconds: tone == Tone.error ? 6 : 3),
  ));
}

/// Common behavior of every scanning screen:
///  - receives scans only while it is the visible route
///  - one scan at a time (a second scan while busy is rejected with a beep)
///  - manual entry
mixin ScanPageMixin<T extends StatefulWidget> on State<T> {
  Object? _scanToken;
  AppState? _app;
  bool busy = false;

  /// Module id used in the scan history.
  String get moduleName;

  /// Handle one scanned code. Exceptions are not caught here.
  Future<void> onScan(String code);

  AppState get app => _app ??= AppScope.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app ??= AppScope.of(context);
    _scanToken ??= app.scanner.register(_handle, isActive: () => mounted && (ModalRoute.of(context)?.isCurrent ?? false));
  }

  @override
  void dispose() {
    if (_scanToken != null) _app?.scanner.unregister(_scanToken!);
    super.dispose();
  }

  void _handle(String code) async {
    if (busy) {
      app.device.warn();
      toast(context, tr('common.busyWait'), tone: Tone.warn);
      return;
    }
    setState(() => busy = true);
    try {
      await onScan(code);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> manualEntry() async {
    final code = await askCode(context);
    if (code != null && code.isNotEmpty) _handle(code);
  }

  void log(String code, Outcome o, [String msg = '']) => app.history.add(moduleName, code, o, msg);
}

/// Standard scaffold for scan screens.
class ScanScaffold extends StatelessWidget {
  const ScanScaffold({
    super.key,
    required this.title,
    required this.prompt,
    required this.onManual,
    required this.busy,
    required this.children,
    this.actions = const [],
    this.bottom,
  });

  final String title;
  final String prompt;
  final VoidCallback onManual;
  final bool busy;
  final List<Widget> children;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: [...actions, const NetBadge()]),
      body: Column(children: [
        const OfflineBanner(),
        ScanPrompt(text: prompt, onManual: onManual, busy: busy),
        Expanded(child: ListView(padding: const EdgeInsets.only(bottom: 24), children: children)),
        if (bottom != null) bottom!,
      ]),
    );
  }
}

/// Parses a JSON-ish value that may already be decoded or still a JSON string.
List<Map<String, dynamic>> jsonList(dynamic v) {
  dynamic d = v;
  if (d is String) {
    final s = d.trim();
    if (s.length < 2) return const [];
    try {
      d = jsonDecode(s);
    } catch (_) {
      return const [];
    }
  }
  if (d is List) {
    return d.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }
  return const [];
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
