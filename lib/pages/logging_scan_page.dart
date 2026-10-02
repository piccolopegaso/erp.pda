import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/history.dart';
import '../core/i18n.dart';
import '../ui/widgets.dart';

/// Logging scan (web: views/warehouse/loggingScan.vue).
/// First scan selects the task (outbound order, or inbound order for "MI…" numbers),
/// following scans log labels/parcels against it.
class LoggingScanPage extends StatefulWidget {
  const LoggingScanPage({super.key});

  @override
  State<LoggingScanPage> createState() => _LoggingScanPageState();
}

class _LoggingScanPageState extends State<LoggingScanPage> with ScanPageMixin {
  @override
  String get moduleName => 'mod.logging';

  Map<String, dynamic> _task = {};
  bool _inbound = false;
  Tone _tone = Tone.info;
  String _title = '';
  String _sub = '';

  int get _id => asInt(_task['id']);

  static bool _isInboundNo(String code) => code.startsWith('MI') && !code.startsWith('MIC');

  List<String> _sentOf(Map d) => (d['shipBundleSent'] as List? ?? const []).map((e) => '$e').toList();

  @override
  Future<void> onScan(String raw) async {
    var code = raw;
    final inbound = _id == 0 ? _isInboundNo(code) : _inbound;
    if (_isInboundNo(code)) code = code.replaceFirst(RegExp(r'P\d{3}$'), '');
    final before = _sentOf(_task);
    try {
      final data = await app.api.command(
        'GET',
        inbound ? '/v0/r7gorders/scanLog' : '/v0/p11yorders/scanLog',
        params: {'id': _id, 'q': code},
      );
      if (data is! Map || asStr(data['unid']).isEmpty) {
        app.device.error();
        _show(Tone.error, tr('common.notFound', {'code': raw}));
        log(raw, Outcome.error, 'not found');
        return;
      }
      final first = _id == 0;
      _task = Map<String, dynamic>.from(data);
      if (first) {
        _inbound = inbound;
        app.device.ok();
        _show(Tone.ok, tr(inbound ? 'log.inbound' : 'log.task', {'unid': asStr(_task['unid'])}), tr('log.scanToLog'));
        log(raw, Outcome.ok, asStr(_task['unid']));
        return;
      }
      final after = _sentOf(_task);
      final already = !inbound && after.length <= before.length && before.contains(code);
      if (already) {
        app.device.warn();
        _show(Tone.warn, tr('log.already', {'code': code}));
        log(raw, Outcome.warn, 'already');
      } else {
        app.device.ok();
        _show(Tone.ok, tr('log.got', {'code': code}));
        log(raw, Outcome.ok);
      }
    } catch (e) {
      app.device.error();
      _show(e is ApiException && e.kind == FailKind.unknown ? Tone.unknown : Tone.error, errorText(e), raw);
      log(raw, outcomeOf(e), errorText(e));
    }
  }

  void _show(Tone t, String title, [String sub = '']) => setState(() {
        _tone = t;
        _title = title;
        _sub = sub;
      });

  void _reset() => setState(() {
        _task = {};
        _inbound = false;
        _title = '';
        _sub = '';
        _tone = Tone.info;
      });

  @override
  Widget build(BuildContext context) {
    final t = _task;
    final sent = _sentOf(t)..sort();
    final items = jsonList(t['items']);
    return ScanScaffold(
      title: tr('mod.logging'),
      prompt: _id == 0 ? tr('log.scanTask') : tr('log.scanToLog'),
      busy: busy,
      onManual: manualEntry,
      actions: [
        if (_id != 0) IconButton(onPressed: busy ? null : _reset, icon: const Icon(Icons.swap_horiz), tooltip: tr('log.changeTask')),
      ],
      children: [
        StatusCard(
          tone: _title.isEmpty ? Tone.info : _tone,
          title: _title.isEmpty ? tr('common.waitScan') : _title,
          subtitle: _title.isEmpty ? tr('log.scanTask') : _sub,
        ),
        if (t.isNotEmpty) ...[
          InfoSection(rows: [
            (tr('common.orderNo'), asStr(t['unid'])),
            (tr('common.refNo'), asStr(t['originSN'])),
            (tr('common.customer'), app.session.customerName(asStr(t['agentGUID']))),
            (tr('common.carrier'), asStr(t['carrier'])),
            (tr('common.consignee'), asStr(t['recName1'])),
            (tr('common.country'), asStr(t['recCountry'])),
            (tr('common.note'), asStr(t['note'])),
            (tr('common.noteInner'), asStr(t['noteInner'])),
          ]),
          if (sent.isNotEmpty)
            InfoSection(title: '${tr('ship.bundles')} (${sent.length})', rows: [for (final s in sent) ('✔', s)]),
          if (items.isNotEmpty)
            InfoSection(
              title: tr('common.items'),
              rows: [for (final it in items) (asStr(it['sku'] ?? it['itemId']), '× ${asStr(it['qty'])}')],
            ),
        ],
      ],
    );
  }
}
