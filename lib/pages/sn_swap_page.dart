import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/device.dart';
import '../core/history.dart';
import '../core/i18n.dart';
import '../ui/widgets.dart';

/// SN swap (web: views/warehouse/snScan.vue, API /v0/p11yorders/swapSN).
/// Every code must be scanned twice (confirmation). After the original SNs are
/// scanned the server returns a new SN, whose label is printed at the desktop
/// print station through the socket.io relay.
class SnSwapPage extends StatefulWidget {
  const SnSwapPage({super.key});

  @override
  State<SnSwapPage> createState() => _SnSwapPageState();
}

class _SnSwapPageState extends State<SnSwapPage> with ScanPageMixin {
  @override
  String get moduleName => 'mod.snswap';

  Map<String, dynamic> _order = {};
  String _pendingConfirm = '';
  int _step = 0; // 0 order, 1 SN1, 2 SN2
  Tone _tone = Tone.info;
  String _title = '';
  String _sub = '';
  List<Map<String, dynamic>> _history = [];
  List<String>? _printTypes;
  StreamSubscription<String>? _wsSub;

  int get _id => asInt(_order['id']);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _wsSub = app.ws.messages.listen((m) {
        if (mounted) toast(context, m, tone: m.toLowerCase().contains('not') ? Tone.error : Tone.ok);
      });
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }

  String get _prompt => switch (_step) {
        0 => tr('sn.scanOrder'),
        1 => tr('sn.scanSN1'),
        _ => tr('sn.scanSN2'),
      };

  @override
  Future<void> onScan(String code) async {
    if (_pendingConfirm.isEmpty) {
      app.device.ok();
      setState(() {
        _pendingConfirm = code;
        _tone = Tone.info;
        _title = tr('rcv.scanAgain', {'code': code});
        _sub = '';
      });
      return;
    }
    if (_pendingConfirm != code) {
      app.device.feedback(Beep.double);
      setState(() {
        _pendingConfirm = '';
        _tone = Tone.error;
        _title = tr('rcv.mismatch');
        _sub = code;
      });
      return;
    }
    _pendingConfirm = '';
    await _submit(code);
  }

  Future<void> _submit(String code) async {
    try {
      final data = await app.api.command('GET', '/v0/p11yorders/swapSN', params: {'id': _id, 'q': code});
      if (data is! Map || asInt(data['id']) == 0) {
        app.device.error();
        _show(Tone.error, tr('common.notFound', {'code': code}));
        log(code, Outcome.error, 'not found');
        return;
      }
      _order = Map<String, dynamic>.from(data);
      _history = jsonList(_order['itemSN']);
      if (_step == 0) {
        _step = 1;
        app.device.ok();
        _show(Tone.ok, '${tr('common.orderNo')} ${asStr(_order['unid'])}', tr('sn.scanSN1'));
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
        _show(Tone.ok, tr('rcv.gotItem', {'code': code}), tr('sn.scanSN2'));
        log(code, Outcome.ok);
      }
    } catch (e) {
      app.device.error();
      _show(e is ApiException && e.kind == FailKind.unknown ? Tone.unknown : Tone.error, errorText(e), code);
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
      _show(Tone.ok, tr('sn.printed', {'sn': sn}));
    } catch (e) {
      app.device.error();
      _show(Tone.error, tr('sn.printFailed', {'msg': errorText(e)}), sn);
    }
  }

  void _show(Tone t, String title, [String sub = '']) => setState(() {
        _tone = t;
        _title = title;
        _sub = sub;
      });

  void _reset() => setState(() {
        _order = {};
        _history = [];
        _step = 0;
        _pendingConfirm = '';
        _title = '';
        _sub = '';
      });

  @override
  Widget build(BuildContext context) {
    return ScanScaffold(
      title: tr('mod.snswap'),
      prompt: _prompt,
      busy: busy,
      onManual: manualEntry,
      actions: [
        if (_id != 0) IconButton(onPressed: busy ? null : _reset, icon: const Icon(Icons.swap_horiz), tooltip: tr('sn.changeOrder')),
      ],
      children: [
        StatusCard(
          tone: _title.isEmpty ? Tone.info : _tone,
          title: _title.isEmpty ? tr('common.waitScan') : _title,
          subtitle: _title.isEmpty ? _prompt : _sub,
        ),
        if (_order.isNotEmpty) ...[
          InfoSection(rows: [
            (tr('common.orderNo'), asStr(_order['unid'])),
            (tr('ship.bundles'), (_order['shipBundleSent'] as List? ?? const []).join(', ')),
          ]),
          if (_history.isNotEmpty)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  child: Text(tr('sn.history'), style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                for (final h in _history)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.print),
                    title: Text(asStr(h['sn'])),
                    subtitle: Text(asStr(h['sku'])),
                    onTap: () async {
                      final sn = asStr(h['sn']);
                      if (sn.isEmpty) return;
                      if (await confirm(context, tr('sn.reprint', {'sn': sn}))) _print(sn);
                    },
                  ),
              ]),
            ),
        ],
      ],
    );
  }
}
