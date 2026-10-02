import 'package:flutter/material.dart';

import '../core/history.dart';
import '../core/i18n.dart';
import '../ui/el.dart';
import '../ui/widgets.dart';

enum _R { idle, task, got, already, invalid, error }

/// Logging Scan (web: views/warehouse/loggingScan.vue).
/// First scan selects the task (outbound order, or inbound order for "MI…" numbers),
/// following scans log labels/parcels against it.
class LoggingScanPage extends StatefulWidget {
  const LoggingScanPage({super.key});

  @override
  State<LoggingScanPage> createState() => _LoggingScanPageState();
}

class _LoggingScanPageState extends State<LoggingScanPage> with ScanPageMixin {
  @override
  String get moduleName => 'wms.loggingScan';

  Map<String, dynamic> _task = {};
  bool _inbound = false;
  _R _r = _R.idle;
  String _code = '';
  String _err = '';

  int get _id => asInt(_task['id']);

  static bool _isInboundNo(String code) => code.startsWith('MI') && !code.startsWith('MIC');

  List<String> _sentOf(Map d) => (d['shipBundleSent'] as List? ?? const []).map((e) => '$e').toList();

  @override
  Future<void> onScan(String raw) async {
    var code = raw;
    final inbound = _id == 0 ? _isInboundNo(code) : _inbound;
    if (_isInboundNo(code)) code = code.replaceFirst(RegExp(r'P\d{3}$'), '');
    final before = _sentOf(_task);
    _code = code;
    try {
      final data = await app.api.command('GET', inbound ? '/v0/r7gorders/scanLog' : '/v0/p11yorders/scanLog', params: {'id': _id, 'q': code});
      if (data is! Map || asStr(data['unid']).isEmpty) {
        app.device.error();
        setState(() => _r = _R.invalid);
        log(raw, Outcome.error, 'Invalid');
        return;
      }
      final first = _id == 0;
      _task = Map<String, dynamic>.from(data);
      if (first) {
        _inbound = inbound;
        app.device.ok();
        setState(() => _r = _R.task);
        log(raw, Outcome.ok, asStr(_task['unid']));
        return;
      }
      // the web compares updatedAt with the device clock; comparing the logged list is clock-independent
      final already = !inbound && _sentOf(_task).length <= before.length && before.contains(code);
      if (already) {
        app.device.error();
        setState(() => _r = _R.already);
        log(raw, Outcome.warn, 'Already Scanned');
      } else {
        app.device.ok();
        setState(() => _r = _R.got);
        log(raw, Outcome.ok);
      }
    } catch (e) {
      app.device.error();
      setState(() {
        _r = _R.error;
        _err = errorText(e);
      });
      log(raw, outcomeOf(e), errorText(e));
    }
  }

  void _change() => setState(() {
        _task = {};
        _inbound = false;
        _r = _R.idle;
      });

  @override
  Widget build(BuildContext context) {
    final t = _task;
    final sent = _sentOf(t)..sort();
    final items = jsonList(t['items']);
    final head = _inbound ? 'Inbound ${asStr(t['unid'])}' : 'Operation Task ${asStr(t['unid'])}';
    final change = FilledButton(style: elButton(ElType.primary), onPressed: _change, child: const Text('Change Order'));
    return ScanScaffold(
      title: tr('wms.loggingScan'),
      placeholder: _id == 0 ? 'Task No.' : 'Scan to log',
      busy: busy,
      onManual: manualEntry,
      children: [
        switch (_r) {
          _R.idle => const ElResult(type: ElType.info, title: 'Please Scan the Order No.'),
          _R.task => ElResult(type: ElType.success, title: head, subTitle: 'Please confirm the order info and continue!', extra: change),
          _R.got => ElResult(type: ElType.success, title: 'Got $_code!', subTitle: head, extra: change),
          _R.already => ElResult(type: ElType.warning, title: '$_code is Already Scanned!', subTitle: 'This number was scanned before!', extra: change),
          _R.invalid => ElResult(type: ElType.danger, title: '$_code is Invalid!', subTitle: 'Please check what you scanned and try again.'),
          _R.error => ElResult(type: ElType.danger, title: _err, subTitle: _code),
        },
        if (t.isNotEmpty)
          ElDescriptions(title: 'Order Info', items: [
            (tr('common.customer'), app.session.customerName(asStr(t['agentGUID']))),
            ('Already Scanned', sent.isEmpty ? null : Wrap(spacing: 4, runSpacing: 4, children: [for (final s in sent) ElTag(s, type: ElType.success)])),
            ('Order ID', asStr(t['unid'])),
            ('Ref. No.', asStr(t['originSN'])),
            ('Items', items.map((i) => '${asStr(i['sku'] ?? i['itemId'])} * ${asStr(i['qty'])}').join('\n')),
            ('Consignee', asStr(t['recName1'])),
            ('Dst. Country', asStr(t['recCountry'])),
            ('Carrier', asStr(t['carrier'])),
            ('Remark', asStr(t['note'])),
            ('Private Remark', asStr(t['noteInner'])),
          ]),
      ],
    );
  }
}
