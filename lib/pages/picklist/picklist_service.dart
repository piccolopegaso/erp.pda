import 'dart:convert';
import 'dart:math' show min;

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../ui/el.dart';
import '../../ui/widgets.dart';

/// web: mixin/orderPick.js tagStatus
String picklistStatusLabel(int s) => switch (s) {
      0 => tr('wms.taskReadyToPick'),
      1 => tr('wms.taskPicklistPrinted'),
      2 => tr('wms.taskRequestedCancel'),
      3 => tr('wms.taskReadyToSwap'),
      4 => tr('wms.taskReadyToPack'),
      5 => tr('wms.taskHoldOn'),
      7 => tr('pda.pick.st7'),
      8 => tr('wms.taskOutOfStock'),
      9 => tr('wms.taskWrongAddress'),
      10 => tr('wms.taskInProcess'),
      15 => tr('wms.taskPickingCompleted'),
      20 => tr('wms.taskPackingCompleted'),
      50 => tr('wms.taskReadyToLoad'),
      95 => tr('wms.taskNotFullyReady'),
      96 => tr('wms.taskCarrierPickupAwaits'),
      99 => tr('wms.taskShippedPartially'),
      100 => tr('wms.taskShipped'),
      101 => tr('pda.pick.st101'),
      102 => tr('pda.pick.st102'),
      120 => 'Canceled',
      121 => 'Retour',
      126 => 'In Transit',
      127 => 'Received',
      _ => '$s',
    };

ElType picklistStatusType(int s) => switch (s) {
      2 || 8 || 9 => ElType.danger,
      20 || 96 || 100 || 101 || 102 || 120 || 126 || 127 => ElType.success,
      1 => ElType.primary,
      _ => ElType.warning,
    };

/// web: mixin/orderPick.js tagType
String picklistTypeLabel(int t) => switch (t) {
      1 => 'Pack Scan Order',
      100 => 'Pack Scan Batch',
      _ => '$t',
    };

/// Server calls shared by Pick Scan Batch and Pack Scan Order
/// (web: views/warehouse/packScanBatch.vue, packScan.vue).
class PicklistService {
  PicklistService(this.app);

  final AppState app;

  static List<Map<String, String>>? _packOpts;
  static Map<String, dynamic>? _outboundDef;
  static final Map<String, List<String>> _packServicesByConfig = {};

  /// GET /v0/p11y/pick/any?q=  -> {id, type, unid, ...}
  Future<Map<String, dynamic>?> findByAny(String code) async {
    try {
      final d = await app.api.query('/v0/p11y/pick/any', params: {'q': code});
      if (d is Map && asInt(d['id']) != 0) return Map<String, dynamic>.from(d);
      return null;
    } on ApiException catch (e) {
      if (e.kind == FailKind.business) return null;
      rethrow;
    }
  }

  /// GET /v0/p11y/pick/?q=id  -> the full picklist (kept as a raw map and PUT back like the web does)
  Future<Map<String, dynamic>> load(int id) async {
    final d = await app.api.query('/v0/p11y/pick/', params: {'q': id});
    if (d is! Map) throw ApiException(FailKind.business, 'Picklist not found, please try again.');
    return Map<String, dynamic>.from(d);
  }

  /// GET /v0/p11y/pick/list (web list page). [statuses] empty = all.
  Future<(List<Map<String, dynamic>>, int)> list({int offset = 0, int limit = 20, String search = '', List<int> statuses = const []}) async {
    final params = <String, dynamic>{'l': limit, 'o': offset, 'q': search};
    if (statuses.isNotEmpty) params['Status[]'] = statuses;
    final d = await app.api.query('/v0/p11y/pick/list', params: params);
    if (d is! Map) return (<Map<String, dynamic>>[], 0);
    final rows = (d['data'] as List? ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    return (rows, asInt(d['total']));
  }

  /// PUT /v0/p11y/pick/ with the whole picklist. The body carries absolute values
  /// (itemQtyPicked, itemInfo, ordersFin ...), so re-sending it after a timeout is safe.
  Future<void> save(Map<String, dynamic> picklist) async {
    for (var attempt = 1;; attempt++) {
      try {
        await app.api.command('PUT', '/v0/p11y/pick/', data: picklist);
        return;
      } on ApiException catch (e) {
        if (!e.isNetwork || attempt >= 3) rethrow;
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
  }

  /// Packing materials: GET /v0/item/opts?Type=2 -> [{value: unid, label: name}]
  Future<List<Map<String, String>>> packingMaterials() async {
    if (_packOpts != null) return _packOpts!;
    final cached = app.settings.readJson<List>('packOpts');
    try {
      final d = await app.api.query('/v0/item/opts', params: {'Type': 2});
      final values = d is Map ? d.values : (d is List ? d : const []);
      _packOpts = [
        for (final v in values)
          if (v is Map && asStr(v['unid']).isNotEmpty) {'value': asStr(v['unid']), 'label': asStr(v['name']).isEmpty ? asStr(v['unid']) : asStr(v['name'])}
      ];
      await app.settings.writeJson('packOpts', _packOpts);
    } catch (_) {
      if (cached != null) {
        _packOpts = [for (final m in cached.whereType<Map>()) {'value': asStr(m['value']), 'label': asStr(m['label'])}];
      } else {
        rethrow;
      }
    }
    return _packOpts!;
  }

  /// The web loads Mask "oms.outbound.list" for the printShipmentLabelAtScan definition.
  Future<Map<String, dynamic>> outboundDef() async {
    if (_outboundDef != null) return _outboundDef!;
    final d = await app.api.query('/v0/masken/', params: {'q': 'oms.outbound.list'});
    final mask = d is Map ? jsonAny(d['mask']) : null;
    _outboundDef = mask is Map ? Map<String, dynamic>.from(mask) : <String, dynamic>{};
    return _outboundDef!;
  }

  /// $CG_API/v0/order/batchPrintLabel (Pick Scan Batch). Returns the label PDF URL.
  Future<String> batchPrintLabel(List<Map<String, dynamic>> printlist) async {
    final d = await app.api.command('POST', '${app.settings.cgServer}/v0/order/batchPrintLabel', data: printlist);
    return _labelUrl(d);
  }

  /// definition.printShipmentLabelAtScan (Pack Scan Order, and reprints from the print history).
  Future<String> printShipmentLabelAtScan(List<Map<String, dynamic>> rows) async {
    final def = await outboundDef();
    final cfg = def['printShipmentLabelAtScan'];
    if (cfg is! Map || asStr(cfg['api']).isEmpty) {
      throw ApiException(FailKind.business, 'Mask oms.outbound.list: printShipmentLabelAtScan missing');
    }
    final constant = cfg['constant'] is Map ? Map<String, dynamic>.from(cfg['constant'] as Map) : <String, dynamic>{};
    final body = [for (final r in rows) {...r, ...constant}];
    final d = await app.api.command(asStr(cfg['method']).isEmpty ? 'POST' : asStr(cfg['method']).toUpperCase(), asStr(cfg['api']), data: body);
    return _labelUrl(d);
  }

  String _labelUrl(dynamic d) {
    final url = d is String ? d : (d is Map ? asStr(d['url'] ?? d['data']) : asStr(d));
    if (url.contains('files=[]')) {
      throw ApiException(FailKind.business, tr('pda.pick.orderMaybeCanceled'));
    }
    if (url.isEmpty) throw ApiException(FailKind.business, 'empty label response');
    return url;
  }

  /// GET /v0/lookup/kct?c=0&t=1&k=(carrierConfig) -> remembered packing materials
  Future<List<String>> packServicesFor(String carrierConfig) async {
    if (carrierConfig.isEmpty) return [];
    if (_packServicesByConfig.containsKey(carrierConfig)) return _packServicesByConfig[carrierConfig]!;
    try {
      final d = await app.api.query('/v0/lookup/kct', params: {'c': 0, 't': 1, 'k': carrierConfig});
      final ps = d is Map && d['packServices'] is List ? (d['packServices'] as List).map((e) => '$e').toList() : <String>[];
      if (ps.isNotEmpty) _packServicesByConfig[carrierConfig] = ps;
      return ps;
    } catch (_) {
      return [];
    }
  }

  /// PUT /v0/lookup/ - remember the packing materials for this item/country combination
  Future<void> rememberPackServices(String carrierConfig, List<String> packServices) async {
    if (carrierConfig.isEmpty || packServices.isEmpty) return;
    _packServicesByConfig[carrierConfig] = packServices;
    try {
      await app.api.command('PUT', '/v0/lookup/', data: {
        'key': carrierConfig,
        'class': 0,
        'type': 1,
        'meta': {'packServices': packServices},
      });
    } catch (_) {}
  }

  /// Print a label PDF at the print station. Returns null on success, otherwise the error text.
  Future<String?> printLabel(String url, String id) async {
    if (!app.printer.configured) return tr('pda.print.notConfigured');
    try {
      await app.printer.printPdfUrl(url, id: id);
      return null;
    } catch (e) {
      return tr('pda.print.failed', {'msg': e is ApiException ? errorText(e) : '$e'});
    }
  }
}

/// Port of packScanBatch.vue processItem(): which label indexes of which orders to print
/// when [qty] pieces of [sku] are picked and [alreadyPrinted] were printed before.
List<Map<String, dynamic>> buildBatchPrintlist({
  required List<Map<String, dynamic>> orders,
  required String sku,
  required int alreadyPrinted,
  required int qty,
  required List<String> materials,
}) {
  final limitQty = alreadyPrinted + qty;
  var thisListQty = 0;
  final printlist = <Map<String, dynamic>>[];
  for (final order in orders) {
    if (limitQty <= thisListQty) break;
    List<int>? lblIdx;
    for (final p in (order['itemPacks'] as List? ?? const [])) {
      if (p is Map && asStr(p['sku']) == sku) {
        lblIdx = (p['lblIdx'] as List? ?? const []).map(asInt).toList();
        break;
      }
    }
    if (lblIdx == null) {
      var itemSum = 0;
      for (final it in (order['items'] as List? ?? const [])) {
        if (it is! Map) continue;
        final q = asInt(it['qty']);
        if (asStr(it['sku']) == sku) {
          lblIdx = List.generate(q, (i) => itemSum + i);
          break;
        }
        itemSum += q;
      }
    }
    if (lblIdx == null) continue;
    Map<String, dynamic> entry(List<int> idxs) => {
          'UNID': order['UNID'],
          'id': order['ID'],
          'packSKU': sku,
          'lblIdx': idxs,
          'packingMaterials': materials,
          'initiator': 'packScanBatch',
        };
    final n = lblIdx.length;
    if (thisListQty < alreadyPrinted && thisListQty + n > alreadyPrinted) {
      final lblrest = alreadyPrinted - thisListQty;
      thisListQty += lblrest;
      final rest = min(limitQty - thisListQty, n - lblrest);
      printlist.add(entry(lblIdx.sublist(lblrest, lblrest + rest)));
      thisListQty += rest;
    } else if (thisListQty < alreadyPrinted) {
      thisListQty += n;
    } else {
      printlist.add(entry(lblIdx.sublist(0, min(n, limitQty - thisListQty))));
      thisListQty += min(n, limitQty - thisListQty);
    }
  }
  return printlist;
}

/// web: utils/auth.js composeCarrierConfig
String composeCarrierConfig(dynamic items, String recCountry) {
  final list = jsonList(items);
  if (list.isEmpty) return '';
  final bySku = <String, Map<String, dynamic>>{};
  for (final i in list) {
    bySku[asStr(i['sku'])] = i;
  }
  final keys = bySku.keys.toList()..sort();
  final content = keys.map((k) => '$k:${bySku[k]!['qty']}').join(':');
  return '$content:${recCountry.isEmpty ? 'DE' : recCountry}';
}

String nowString() {
  final n = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${n.year}-${two(n.month)}-${two(n.day)} ${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
}

String jsonStr(Object o) => jsonEncode(o);

