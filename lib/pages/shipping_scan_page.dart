import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/history.dart';
import '../core/i18n.dart';
import '../ui/widgets.dart';

enum _Mode { none, skuQC, sn }

/// Outbound shipping scan (web: views/warehouse/shippingScan.vue).
///
/// Scan a tracking / FBA / order number -> the server marks the parcel as scanned.
/// If the order requires a SKU QC and/or item serial numbers, the screen switches
/// into the matching prompt until all required scans are done.
class ShippingScanPage extends StatefulWidget {
  const ShippingScanPage({super.key});

  @override
  State<ShippingScanPage> createState() => _ShippingScanPageState();
}

class _ShippingScanPageState extends State<ShippingScanPage> with ScanPageMixin {
  @override
  String get moduleName => 'mod.shipping';

  Map<String, dynamic> _order = {};
  _Mode _mode = _Mode.none;
  Tone _tone = Tone.info;
  String _title = '';
  String _sub = '';
  String _promptError = '';

  int get _id => asInt(_order['id']);

  String get _prompt {
    switch (_mode) {
      case _Mode.skuQC:
        return tr('ship.scanSKU', {'item': asStr(_order['skuQCCurrentItemID'])});
      case _Mode.sn:
        return tr('ship.scanSN', {'item': _currentSNItem});
      case _Mode.none:
        return tr('ship.scanShipment');
    }
  }

  String get _currentSNItem =>
      asStr(_order['snCurrentItemID']).isNotEmpty ? asStr(_order['snCurrentItemID']) : asStr(_order['itemID']);

  @override
  Future<void> onScan(String code) async {
    switch (_mode) {
      case _Mode.skuQC:
        return _scanSKU(code);
      case _Mode.sn:
        return _scanSN(code);
      case _Mode.none:
        return _scanShipment(code);
    }
  }

  // ---------- helpers mirroring the web logic ----------

  List<String> get _sent => (_order['shipBundleSent'] as List? ?? const []).map((e) => '$e').toList()..sort();

  bool _shippingComplete(Map d) {
    final scanned = (d['shipBundleSent'] as List? ?? const []).length;
    final qty = asInt(d['shipQty']) < 1 ? 1 : asInt(d['shipQty']);
    return scanned >= qty;
  }

  bool _needSKU(Map d) {
    if (!_shippingComplete(d)) return false;
    final req = asInt(d['skuQCRequiredQty']);
    return asInt(d['skuQCRemainingQty']) > 0 || (req > 0 && asInt(d['skuQCScannedQty']) < req);
  }

  bool _needSN(Map d) {
    final req = asInt(d['snRequiredQty']);
    return asInt(d['snRemainingQty']) > 0 || (req > 0 && asInt(d['snScannedQty']) < req);
  }

  String _statusTitle(Map d) {
    final a = (d['shipBundleSent'] as List? ?? const []).length;
    final b = asInt(d['shipQty']);
    final args = {'a': a, 'b': b};
    switch (asInt(d['status'])) {
      case 91:
        return tr('ship.st91');
      case 95:
        return tr('ship.st95', args);
      case 96:
        return tr('ship.st96', args);
      case 99:
        return tr('ship.st99', args);
      case 100:
        return tr('ship.st100', args);
      default:
        return tr('ship.stDefault', args);
    }
  }

  void _show(Tone tone, String title, [String sub = '']) {
    setState(() {
      _tone = tone;
      _title = title;
      _sub = sub;
    });
  }

  void _applySKU(Map r) {
    _order = {
      ..._order,
      'shippingScanSKUQC': r['shippingScanSKUQC'],
      'skuQCCurrentItemID': r['itemID'],
      'skuQCRequiredQty': r['requiredSKUQCQty'],
      'skuQCScannedQty': r['scannedSKUQCQty'],
      'skuQCRemainingQty': r['remainingSKUQCQty'],
      'skuQCCompleted': r['skuQCCompleted'],
      'snRequiredQty': r['requiredSNQty'],
      'snScannedQty': r['scannedSNQty'],
      'snRemainingQty': r['remainingSNQty'],
      'snCompleted': r['snCompleted'],
      if (r['status'] != null) 'status': r['status'],
    };
  }

  void _applySN(Map r) {
    _order = {
      ..._order,
      'itemSN': r['itemSN'],
      'itemID': r['itemID'],
      'snCurrentItemID': r['itemID'],
      'snRequiredQty': r['requiredSNQty'],
      'snScannedQty': r['scannedSNQty'],
      'snRemainingQty': r['remainingSNQty'],
      'snCompleted': r['completed'],
      if (r['status'] != null) 'status': r['status'],
    };
  }

  Future<Map> _skuProgress() async =>
      Map.from(await app.api.command('GET', '/v0/p11yorders/scanItemSKUQC', params: {'id': _id, 'q': ''}) as Map);

  Future<Map> _snProgress() async => Map.from(
      await app.api.command('GET', '/v0/p11yorders/scanItemSN', params: {'id': _id, 'itemID': '', 'q': ''}) as Map);

  Future<void> _openSNPrompt() async {
    _applySN(await _snProgress());
    _mode = _Mode.sn;
    _promptError = '';
    app.device.warn();
    _show(Tone.warn, tr('ship.scanSN', {'item': _currentSNItem}),
        tr('ship.snProgress', {'a': asInt(_order['snScannedQty']), 'b': asInt(_order['snRequiredQty'])}));
  }

  void _openSKUPrompt() {
    _mode = _Mode.skuQC;
    _promptError = '';
    app.device.warn();
    _show(Tone.warn, tr('ship.scanSKU', {'item': asStr(_order['skuQCCurrentItemID'])}),
        tr('ship.skuProgress', {'a': asInt(_order['skuQCScannedQty']), 'b': asInt(_order['skuQCRequiredQty'])}));
  }

  // ---------- scan handlers ----------

  Future<void> _scanShipment(String code) async {
    try {
      final data = await app.api.command('GET', '/v0/p11yorders/scanShipSN', params: {'q': code});
      if (data is! Map || asStr(data['unid']).isEmpty) {
        _order = {};
        app.device.error();
        _show(Tone.error, tr('common.notFound', {'code': code}));
        log(code, Outcome.error, 'not found');
        return;
      }
      _order = Map<String, dynamic>.from(data);
      _mode = _Mode.none;
      final st = asInt(_order['status']);
      if (st == 2 || st == 120) {
        app.device.error();
        _show(Tone.error, tr('ship.attention'), code);
        log(code, Outcome.error, 'status $st');
        return;
      }
      if (_order['alreadyScanned'] == true) {
        if (st == 95) {
          _applySKU(await _skuProgress());
          if (_needSKU(_order)) {
            _openSKUPrompt();
            log(code, Outcome.warn, 'SKU QC');
            return;
          }
          if (_needSN(_order)) {
            await _openSNPrompt();
            log(code, Outcome.warn, 'SN');
            return;
          }
        }
        app.device.error();
        _show(Tone.warn, tr('ship.already', {'title': _statusTitle(_order)}), code);
        log(code, Outcome.warn, 'already scanned');
        return;
      }
      if (_needSKU(_order)) {
        _openSKUPrompt();
        log(code, Outcome.ok, 'SKU QC required');
      } else if (_needSN(_order)) {
        await _openSNPrompt();
        log(code, Outcome.ok, 'SN required');
      } else {
        app.device.ok();
        _show(Tone.ok, _statusTitle(_order), code);
        log(code, Outcome.ok, _statusTitle(_order));
      }
    } catch (e) {
      app.device.error();
      _order = {};
      _show(e is ApiException && e.kind == FailKind.unknown ? Tone.unknown : Tone.error, errorText(e), code);
      log(code, outcomeOf(e), errorText(e));
    }
  }

  Future<void> _scanSKU(String code) async {
    setState(() => _promptError = '');
    try {
      final r = Map.from(await app.api.command('GET', '/v0/p11yorders/scanItemSKUQC', params: {'id': _id, 'q': code}) as Map);
      _applySKU(r);
      final progress = tr('ship.skuProgress', {'a': asInt(_order['skuQCScannedQty']), 'b': asInt(_order['skuQCRequiredQty'])});
      log(code, Outcome.ok, progress);
      if (r['skuQCCompleted'] == true) {
        if (r['snRequired'] == true && r['snCompleted'] != true) {
          app.device.ok();
          await _openSNPrompt();
        } else {
          _mode = _Mode.none;
          app.device.ok();
          _show(Tone.ok, _statusTitle(_order), progress);
        }
      } else {
        app.device.ok();
        _show(Tone.warn, tr('ship.scanSKU', {'item': asStr(_order['skuQCCurrentItemID'])}), progress);
      }
    } catch (e) {
      app.device.error();
      log(code, outcomeOf(e), errorText(e));
      setState(() => _promptError = errorText(e));
      if (e is ApiException && e.kind == FailKind.unknown) await _verifySKU();
    }
  }

  Future<void> _scanSN(String code) async {
    setState(() => _promptError = '');
    try {
      final r = Map.from(await app.api.command('GET', '/v0/p11yorders/scanItemSN',
          params: {'id': _id, 'itemID': _currentSNItem, 'q': code}) as Map);
      _applySN(r);
      final progress = tr('ship.snProgress', {'a': asInt(_order['snScannedQty']), 'b': asInt(_order['snRequiredQty'])});
      log(code, Outcome.ok, progress);
      app.device.ok();
      if (r['completed'] == true) {
        _mode = _Mode.none;
        _show(Tone.ok, _statusTitle(_order), progress);
      } else {
        _show(Tone.warn, tr('ship.scanSN', {'item': _currentSNItem}), progress);
      }
    } catch (e) {
      app.device.error();
      log(code, outcomeOf(e), errorText(e));
      setState(() => _promptError = errorText(e));
      if (e is ApiException && e.kind == FailKind.unknown) await _verifySN();
    }
  }

  /// After a timeout the scan may have been counted: re-read the progress instead of guessing.
  Future<void> _verifySKU() async {
    try {
      _applySKU(await _skuProgress());
      setState(() => _promptError = '${tr('err.unknownCheck')}\n'
          '${tr('ship.skuProgress', {'a': asInt(_order['skuQCScannedQty']), 'b': asInt(_order['skuQCRequiredQty'])})}');
    } catch (_) {}
  }

  Future<void> _verifySN() async {
    try {
      _applySN(await _snProgress());
      setState(() => _promptError = '${tr('err.unknownCheck')}\n'
          '${tr('ship.snProgress', {'a': asInt(_order['snScannedQty']), 'b': asInt(_order['snRequiredQty'])})}');
    } catch (_) {}
  }

  void _leavePrompt() {
    setState(() {
      _mode = _Mode.none;
      _promptError = '';
      _tone = Tone.info;
      _title = '';
      _sub = '';
    });
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final o = _order;
    final items = jsonList(o['items']);
    final skuDone = jsonList(o['shippingScanSKUQC']);
    final snDone = jsonList(o['itemSN']);
    final bundleLines = asStr(o['shipBundle']).split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final sent = _sent;
    final missing = bundleLines.where((b) => !sent.contains(b)).toList();

    return ScanScaffold(
      title: tr('mod.shipping'),
      prompt: _prompt,
      busy: busy,
      onManual: manualEntry,
      actions: [
        if (_mode != _Mode.none)
          IconButton(icon: const Icon(Icons.close), tooltip: tr('ship.cancelPrompt'), onPressed: _leavePrompt),
      ],
      children: [
        if (_title.isNotEmpty)
          StatusCard(tone: _tone, title: _title, subtitle: _sub)
        else
          StatusCard(tone: Tone.info, title: tr('common.waitScan'), subtitle: tr('ship.scanShipment')),
        if (_promptError.isNotEmpty)
          StatusCard(tone: Tone.error, title: _promptError),
        if (o.isNotEmpty) ...[
          if (asStr(o['noteInner']).isNotEmpty || asStr(o['noteImportant']).isNotEmpty)
            StatusCard(
              tone: Tone.warn,
              title: tr('common.noteInner'),
              subtitle: [asStr(o['noteImportant']), asStr(o['noteInner'])].where((s) => s.isNotEmpty).join('\n'),
            ),
          InfoSection(rows: [
            (tr('common.orderNo'), asStr(o['unid'])),
            (tr('common.refNo'), asStr(o['originSN'])),
            (tr('common.customer'), app.session.customerName(asStr(o['agentGUID']))),
            (tr('common.carrier'), asStr(o['carrier'])),
            (tr('common.consignee'), asStr(o['recName1'])),
            (tr('common.country'), asStr(o['recCountry'])),
            (tr('common.note'), asStr(o['note'])),
          ]),
          if (items.isNotEmpty)
            InfoSection(
              title: tr('common.items'),
              rows: [for (final it in items) (asStr(it['sku'] ?? it['itemId']), '× ${asStr(it['qty'])}')],
            ),
          if (sent.isNotEmpty || missing.isNotEmpty)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${tr('ship.bundles')} ${sent.length}/${asInt(o['shipQty'])}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final s in sent) _chip(s, const Color(0xFF2E7D32)),
                    for (final m in missing) _chip('${tr('ship.missing')}: $m', const Color(0xFFC62828)),
                  ]),
                ]),
              ),
            ),
          if (skuDone.isNotEmpty)
            InfoSection(title: tr('ship.skuScanned'), rows: _grouped(skuDone, 'sku')),
          if (snDone.isNotEmpty)
            InfoSection(
              title: tr('ship.snScanned'),
              rows: [for (final s in snDone) (asStr(s['sku'] ?? s['itemID']), asStr(s['sn']))],
            ),
        ],
      ],
    );
  }

  List<(String, String)> _grouped(List<Map<String, dynamic>> rows, String key) {
    final m = <String, int>{};
    for (final r in rows) {
      final k = asStr(r[key]);
      m[k] = (m[k] ?? 0) + 1;
    }
    return [for (final e in m.entries) (e.key, '× ${e.value}')];
  }

  Widget _chip(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.1), border: Border.all(color: c), borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: TextStyle(color: c, fontSize: 13)),
      );
}
