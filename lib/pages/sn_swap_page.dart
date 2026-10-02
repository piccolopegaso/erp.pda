import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/history.dart';
import '../core/i18n.dart';
import '../ui/el.dart';
import '../ui/widgets.dart';

enum _R { idle, order, got, printed, notFound, error }

/// SN Scan (web: views/warehouse/snScan.vue, API /v0/p11yorders/swapSN).
/// Every code is scanned twice (confirmation). After the two original SNs the server
/// returns a new SN, printed at the print station through the socket.io relay.
class SnSwapPage extends StatefulWidget {
  const SnSwapPage({super.key});

  @override
  State<SnSwapPage> createState() => _SnSwapPageState();
}

class _SnSwapPageState extends State<SnSwapPage> with ScanPageMixin {
  @override
  String get moduleName => 'wms.snScan';

  @override
  int get requiredScans => 2;

  Map<String, dynamic> _order = {};
  int _step = 0; // 0 order, 1 SN1, 2 SN2
  _R _r = _R.idle;
  String _code = '';
  String _msg = '';
  List<Map<String, dynamic>> _history = [];
  List<String>? _printTypes;
  StreamSubscription<String>? _wsSub;

  int get _id => asInt(_order['id']);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _wsSub = app.ws.messages.listen((m) {
        if (mounted) toast(context, m, type: m.toLowerCase().contains('not') ? ElType.danger : ElType.success);
      });
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }

  String get _placeholder => switch (_step) {
        0 => 'Order No.',
        1 => 'Scan the original SN1',
        _ => 'Scan the original SN2',
      };

  @override
  Future<void> onScan(String code) async {
    _code = code;
    try {
      final data = await app.api.command('GET', '/v0/p11yorders/swapSN', params: {'id': _id, 'q': code});
      if (data is! Map || asInt(data['id']) == 0) {
        app.device.error();
        setState(() => _r = _R.notFound);
        log(code, Outcome.error, 'not found');
        return;
      }
      _order = Map<String, dynamic>.from(data);
      _history = jsonList(_order['itemSN']);
      if (_step == 0) {
        _step = 1;
        app.device.ok();
        setState(() => _r = _R.order);
        log(code, Outcome.ok, asStr(_order['unid']));
        return;
      }
      final sn = asStr(_order['sn']);
      if (sn.isNotEmpty) {
        _step = 1;
        log(code, Outcome.ok, 'new SN $sn');
        await _print(sn);
      } else {
        _step = 2;
        app.device.ok();
        setState(() => _r = _R.got);
        log(code, Outcome.ok);
      }
    } catch (e) {
      app.device.error();
      setState(() {
        _r = _R.error;
        _msg = errorText(e);
      });
      log(code, outcomeOf(e), errorText(e));
    }
  }

  Future<List<String>> _types() async {
    if (_printTypes != null) return _printTypes!;
    try {
      final def = await app.api.query('/v0/masken/', params: {'q': 'wms.orders.snScan'});
      final list = jsonDecode('${def['mask']}');
      _printTypes = [for (final p in (list as List)) '${(p as Map)['type']}'];
    } catch (_) {
      _printTypes = ['printSN'];
    }
    return _printTypes!;
  }

  Future<void> _print(String sn) async {
    try {
      for (final t in await _types()) {
        await app.ws.printLabel(t, sn);
      }
      app.device.ok();
      setState(() {
        _r = _R.printed;
        _msg = sn;
      });
    } catch (e) {
      app.device.error();
      setState(() {
        _r = _R.error;
        _msg = '${tr('pda.print.failed', {'msg': '$e'})} ($sn)';
      });
    }
  }

  void _change() => setState(() {
        _order = {};
        _history = [];
        _step = 0;
        _r = _R.idle;
        resetScanConfirm();
      });

  @override
  Widget build(BuildContext context) {
    final change = FilledButton(style: elButton(ElType.primary), onPressed: _change, child: const Text('Change Order'));
    return ScanScaffold(
      title: tr('wms.snScan'),
      placeholder: _placeholder,
      busy: busy,
      onManual: manualEntry,
      progress: scanProgress != null ? '$scanProgress — Please scann again to confirm!' : null,
      lastScanned: lastScanned,
      scanError: scanError,
      children: [
        switch (_r) {
          _R.idle => const ElResult(type: ElType.info, title: 'Please Scan the Order No.'),
          _R.order => ElResult(type: ElType.success, title: 'Order ${asStr(_order['unid'])}', subTitle: 'Please confirm the order info and continue!', extra: change),
          _R.got => ElResult(type: ElType.success, title: 'Got $_code !', subTitle: 'Scan the original SN2', extra: change),
          _R.printed => ElResult(type: ElType.success, title: _msg, subTitle: 'Please check out the printer.', extra: change),
          _R.notFound => const ElResult(type: ElType.warning, title: 'Please scan the next different SN!', subTitle: 'Scan 2 different SNs to return the new SN print.'),
          _R.error => ElResult(type: ElType.danger, title: _msg, subTitle: _code),
        },
        if (_order.isNotEmpty)
          ElDescriptions(title: 'Order Info', items: [
            ('Already Scanned', (_order['shipBundleSent'] as List? ?? const []).join('\n')),
            (
              'Print History',
              _history.isEmpty
                  ? null
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final h in _history)
                        TextButton.icon(
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                          onPressed: asStr(h['sn']).isEmpty
                              ? null
                              : () async {
                                  if (await confirm(context, '${tr('common.print')} ${asStr(h['sn'])}?')) _print(asStr(h['sn']));
                                },
                          icon: const Icon(Icons.print, size: 16),
                          label: Text('${asStr(h['sku'])}:${asStr(h['sn'])}'),
                        ),
                    ])
            ),
          ]),
      ],
    );
  }
}
