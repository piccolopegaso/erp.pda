import 'package:flutter/material.dart';

import '../core/history.dart';
import '../core/i18n.dart';
import '../ui/el.dart';
import '../ui/widgets.dart';

enum _Mode { none, skuQC, sn }

enum _Result { idle, ok, already, attention, notFound, error }

/// Shipping Scan (web: views/warehouse/shippingScan.vue).
/// Scan a tracking / FBA / order number; orders that need a SKU QC and/or item
/// serial numbers switch into the matching prompt until all required scans are done.
class ShippingScanPage extends StatefulWidget {
  const ShippingScanPage({super.key});

  @override
  State<ShippingScanPage> createState() => _ShippingScanPageState();
}

class _ShippingScanPageState extends State<ShippingScanPage> with ScanPageMixin {
  @override
  String get moduleName => 'wms.shippingScan';

  Map<String, dynamic> _order = {};
  _Mode _mode = _Mode.none;
  _Result _result = _Result.idle;
  String _title = '';
  String _scanned = '';
  String _promptError = '';

  int get _id => asInt(_order['id']);

  String get _placeholder => switch (_mode) {
        _Mode.skuQC => tr('pda.ship.phSKU'),
        _Mode.sn => tr('pda.ship.phSN'),
        _Mode.none => 'Tracking No./FBA /Order No.',
      };

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

  // ---------- helpers mirroring shippingScan.vue ----------

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

  /// buildShippingScanTitle()
  String _statusTitle(Map d) {
    final a = (d['shipBundleSent'] as List? ?? const []).length;
    final b = asInt(d['shipQty']);
    return switch (asInt(d['status'])) {
      91 => 'SN Required',
      95 => '$a/$b Partial QC',
      96 => '$a/$b Ready to Carrier Pickup',
      99 => '$a/$b Shipped Partially',
      100 => '$a/$b Shipped',
      _ => '$a/$b Scanned',
    };
  }

  /// shippingResultSubtitle
  String _statusSubtitle(Map d) => switch (asInt(d['status'])) {
        91 => 'Item serial number scan is required before this order can continue.',
        95 => 'This order is now in Partial QC.',
        96 => '',
        99 => 'This order is partially shipped.',
        100 => 'This order is marked as shipped.',
        _ => 'Shipping scan completed.',
      };

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
    _title = 'Scan SN for ${_currentSNItem.isEmpty ? 'required item' : _currentSNItem}';
    app.device.error(); // web: playBeepLong() to draw attention
  }

  void _openSKUPrompt() {
    _mode = _Mode.skuQC;
    _promptError = '';
    final cur = asStr(_order['skuQCCurrentItemID']);
    _title = 'Scan SKU QC for ${cur.isEmpty ? 'required item' : cur}';
    app.device.error();
  }

  // ---------- scan handlers ----------

  Future<void> _scanShipment(String code) async {
    _scanned = code;
    try {
      final data = await app.api.command('GET', '/v0/p11yorders/scanShipSN', params: {'q': code});
      if (data is! Map || asStr(data['unid']).isEmpty) {
        app.device.error();
        setState(() {
          _order = {};
          _result = _Result.notFound;
        });
        log(code, Outcome.error, 'Order Not Found');
        return;
      }
      _order = Map<String, dynamic>.from(data);
      _mode = _Mode.none;
      final st = asInt(_order['status']);
      if (st == 2 || st == 120) {
        app.device.error();
        setState(() => _result = _Result.attention);
        log(code, Outcome.error, 'Attention: status $st');
        return;
      }
      if (_order['alreadyScanned'] == true) {
        if (st == 95) {
          _applySKU(await _skuProgress());
          if (_needSKU(_order)) {
            _openSKUPrompt();
            setState(() => _result = _Result.ok);
            log(code, Outcome.warn, 'SKU QC');
            return;
          }
          if (_needSN(_order)) {
            await _openSNPrompt();
            setState(() => _result = _Result.ok);
            log(code, Outcome.warn, 'SN');
            return;
          }
        }
        app.device.error();
        setState(() {
          _result = _Result.already;
          _title = st == 96
              ? 'Already Scanned - ${(_order['shipBundleSent'] as List? ?? const []).length}/${asInt(_order['shipQty'])}'
              : 'Already Scanned - ${_statusTitle(_order)}';
        });
        log(code, Outcome.warn, _title);
        return;
      }
      if (_needSKU(_order)) {
        _openSKUPrompt();
      } else if (_needSN(_order)) {
        await _openSNPrompt();
      } else {
        app.device.ok();
        _title = _statusTitle(_order);
      }
      setState(() => _result = _Result.ok);
      log(code, Outcome.ok, _title);
    } catch (e) {
      app.device.error();
      setState(() {
        _order = {};
        _result = _Result.error;
        _title = errorText(e);
      });
      log(code, outcomeOf(e), errorText(e));
    }
  }

  Future<void> _scanSKU(String code) async {
    setState(() => _promptError = '');
    try {
      final r = Map.from(await app.api.command('GET', '/v0/p11yorders/scanItemSKUQC', params: {'id': _id, 'q': code}) as Map);
      _applySKU(r);
      final progress = 'SKU QC ${asInt(_order['skuQCScannedQty'])}/${asInt(_order['skuQCRequiredQty'])} scanned';
      log(code, Outcome.ok, progress);
      app.device.ok();
      if (r['skuQCCompleted'] == true) {
        if (r['snRequired'] == true && r['snCompleted'] != true) {
          _title = progress;
          await _openSNPrompt();
        } else {
          _mode = _Mode.none;
          _title = _statusTitle(_order);
        }
      } else {
        _title = progress;
      }
      setState(() {});
    } catch (e) {
      app.device.error();
      log(code, outcomeOf(e), errorText(e));
      setState(() => _promptError = errorText(e));
      if (isUnknown(e)) {
        try {
          _applySKU(await _skuProgress());
          setState(() => _promptError = '${errorText(e)}\n${tr('pda.err.verified')}');
        } catch (_) {}
      }
    }
  }

  Future<void> _scanSN(String code) async {
    setState(() => _promptError = '');
    try {
      final r = Map.from(await app.api.command('GET', '/v0/p11yorders/scanItemSN',
          params: {'id': _id, 'itemID': _currentSNItem, 'q': code}) as Map);
      _applySN(r);
      final progress = 'SN ${asInt(_order['snScannedQty'])}/${asInt(_order['snRequiredQty'])} scanned';
      log(code, Outcome.ok, progress);
      app.device.ok();
      if (r['completed'] == true) {
        _mode = _Mode.none;
        _title = _statusTitle(_order);
      } else {
        _title = progress;
      }
      setState(() {});
    } catch (e) {
      app.device.error();
      log(code, outcomeOf(e), errorText(e));
      setState(() => _promptError = errorText(e));
      if (isUnknown(e)) {
        try {
          _applySN(await _snProgress());
          setState(() => _promptError = '${errorText(e)}\n${tr('pda.err.verified')}');
        } catch (_) {}
      }
    }
  }

  void _closePrompt() => setState(() {
        _mode = _Mode.none;
        _promptError = '';
      });

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
      title: tr('wms.shippingScan'),
      placeholder: _placeholder,
      busy: busy,
      onManual: manualEntry,
      actions: [
        if (_mode != _Mode.none) IconButton(icon: const Icon(Icons.close), onPressed: _closePrompt),
      ],
      children: [
        if (_mode == _Mode.skuQC) _skuPrompt(skuDone),
        if (_mode == _Mode.sn) _snPrompt(snDone),
        switch (_result) {
          _Result.idle => const ElResult(type: ElType.info, title: 'Please Scan the Shipment No. or Order No.'),
          _Result.notFound => ElResult(type: ElType.danger, title: 'Order Not Found', subTitle: '$_scanned\nPlease check the shipment number and try again.'),
          _Result.attention => const ElResult(type: ElType.danger, title: 'Attention', subTitle: 'Please check the status of the order! Maybe canceled!'),
          _Result.already => ElResult(type: ElType.warning, title: _title, subTitle: 'This order was scanned before!'),
          _Result.error => ElResult(type: isUnknownTitle ? ElType.primary : ElType.danger, icon: Icons.help, title: _title, subTitle: _scanned),
          _Result.ok => _mode == _Mode.none
              ? ElResult(type: ElType.success, title: _title, subTitle: _statusSubtitle(o))
              : const SizedBox.shrink(),
        },
        if (o.isNotEmpty) ...[
          if (asStr(o['noteImportant']).isNotEmpty) ElAlert(type: ElType.danger, title: asStr(o['noteImportant'])),
          ElDescriptions(title: 'Order Info', items: [
            (
              'Already Scanned',
              sent.isEmpty && missing.isEmpty
                  ? null
                  : Wrap(spacing: 4, runSpacing: 4, children: [
                      for (final s in sent) ElTag(s, type: ElType.success),
                      for (final m in missing) ElTag(m, type: ElType.danger),
                    ])
            ),
            ('Order ID', asStr(o['unid'])),
            ('Ref. No.', asStr(o['originSN'])),
            ('Carrier', asStr(o['carrier'])),
            ('Consignee', asStr(o['recName1'])),
            ('Dst. Country', asStr(o['recCountry'])),
            ('Items', items.map((i) => '${asStr(i['sku'])} * ${asStr(i['qty'])}').join('\n')),
            ('Remark', asStr(o['note'])),
            ('Private Remark', asStr(o['noteInner'])),
          ]),
        ],
      ],
    );
  }

  bool get isUnknownTitle => _title == tr('pda.err.unknown');

  Widget _skuPrompt(List<Map<String, dynamic>> done) {
    final grouped = <String, int>{};
    for (final r in done) {
      grouped[asStr(r['sku'])] = (grouped[asStr(r['sku'])] ?? 0) + 1;
    }
    final req = asInt(_order['skuQCRequiredQty']);
    final got = asInt(_order['skuQCScannedQty']);
    return ElCard(
      highlight: El.warning,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Scan SKU for QC', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: El.warning)),
        const SizedBox(height: 6),
        _kv('Current SKU', asStr(_order['skuQCCurrentItemID'])),
        _kv('SKU QC Progress', '$got / $req'),
        const SizedBox(height: 4),
        ElProgress(value: req == 0 ? 0 : got / req, complete: req > 0 && got >= req),
        if (_promptError.isNotEmpty) ElAlert(type: ElType.danger, title: _promptError, margin: const EdgeInsets.only(top: 6)),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Press Enter after each SKU scan. Repeated scans of the same valid SKU count one piece each.',
              style: TextStyle(fontSize: 12, color: El.textSecondary)),
        ),
        if (grouped.isNotEmpty) ...[
          const SizedBox(height: 6),
          const Text('Scanned SKU QC', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          Wrap(spacing: 4, runSpacing: 4, children: [for (final e in grouped.entries) ElTag('${e.key} × ${e.value}', type: ElType.success)]),
        ],
      ]),
    );
  }

  Widget _snPrompt(List<Map<String, dynamic>> done) {
    final req = asInt(_order['snRequiredQty']);
    final got = asInt(_order['snScannedQty']);
    return ElCard(
      highlight: El.warning,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Please Scan Item SN', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: El.warning)),
        const SizedBox(height: 6),
        _kv('Current ItemID', _currentSNItem),
        _kv('Serial Scan Progress', '$got / $req'),
        const SizedBox(height: 4),
        ElProgress(value: req == 0 ? 0 : got / req, complete: req > 0 && got >= req),
        if (_promptError.isNotEmpty) ElAlert(type: ElType.danger, title: _promptError, margin: const EdgeInsets.only(top: 6)),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Press Enter after scanning. The prompt will close automatically when all required SNs are completed.',
              style: TextStyle(fontSize: 12, color: El.textSecondary)),
        ),
        if (done.isNotEmpty) ...[
          const SizedBox(height: 6),
          const Text('Scanned Serial Numbers', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          for (final s in done) Text('${asStr(s['sku'])}: ${asStr(s['sn'])}', style: const TextStyle(fontSize: 13)),
        ],
      ]),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(children: [
          SizedBox(width: 130, child: Text(k, style: const TextStyle(color: El.textSecondary, fontSize: 13))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
        ]),
      );
}
