import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/history.dart';
import '../../core/i18n.dart';
import '../../ui/el.dart';
import '../../ui/widgets.dart';
import 'picklist_service.dart';
import 'picklist_widgets.dart';

/// Pack Scan Order (web: views/warehouse/packScan.vue).
///
/// Scan the items of an order (and the batch number when the picklist is batch-specific),
/// choose the packing material, print the order's shipment label at the print station.
/// Each printed order goes to ordersFin and adds its quantity to itemQtyPicked.
class PackScanOrderPage extends StatefulWidget {
  const PackScanOrderPage({super.key, required this.pickId});

  final int pickId;

  @override
  State<PackScanOrderPage> createState() => _PackScanOrderPageState();
}

class _PackScanOrderPageState extends State<PackScanOrderPage> with ScanPageMixin {
  @override
  String get moduleName => 'pda.packScanOrder';

  late final PicklistService svc = PicklistService(app);

  Map<String, dynamic> picklist = {};
  final Map<int, Map<String, dynamic>> ordersList = {};
  Map<String, List<int>> mapItemOrders = {};
  List<Map<String, dynamic>> itemInfo = [];
  List<int> ordersFin = [];
  Map<String, int> scanned = {};
  String lastScannedUNID = '';
  List<Map<String, dynamic>> orderData = [];
  List<Map<String, String>> packOpts = [];
  bool loading = true;
  bool printing = false;
  bool itemNotFound = false;
  bool orderNotFound = false;
  String loadError = '';
  String notice = '';
  ElType noticeType = ElType.info;

  int get itemQty => asInt(picklist['itemQty']);
  int get itemQtyPicked => asInt(picklist['itemQtyPicked']);
  int get status => asInt(picklist['status']);
  bool get finished => itemQty > 0 && itemQtyPicked >= itemQty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      svc.packingMaterials().then((v) => mounted ? setState(() => packOpts = v) : null).catchError((_) {});
    });
  }

  /// web getDefinition(): reload the picklist and reset the scan state
  Future<void> _load() async {
    setState(() {
      loading = true;
      loadError = '';
      scanned = {};
      orderData = [];
      lastScannedUNID = '';
      orderNotFound = false;
    });
    try {
      final p = await svc.load(widget.pickId);
      final orders = jsonList(p['orders']);
      final old = Map<int, Map<String, dynamic>>.from(ordersList);
      ordersList.clear();
      for (final o in orders) {
        final id = asInt(o['ID']);
        o['carrierConfig'] = composeCarrierConfig(o['items'], asStr(o['recCountry']));
        o['packServices'] = (old[id]?['packServices'] as List?)?.cast<String>() ?? await svc.packServicesFor(asStr(o['carrierConfig']));
        ordersList[id] = o;
      }
      final map = <String, List<int>>{};
      final raw = jsonAny(p['itemOrders']);
      if (raw is Map) {
        raw.forEach((k, v) {
          final ids = (v is List ? v : const []).map(asInt).toList();
          map['$k'] = ids;
          map['$k'.toUpperCase()] = ids;
        });
      }
      final finRaw = jsonAny(p['ordersFin']);
      setState(() {
        picklist = p;
        mapItemOrders = map;
        ordersFin = finRaw is List ? finRaw.map(asInt).toSet().toList() : [];
        itemInfo = asStr(p['itemInfo']).isEmpty
            ? [for (final i in jsonList(p['items'])) {...i, 'qtyPrinted': 0}]
            : jsonList(p['itemInfo']);
      });
    } catch (e) {
      setState(() => loadError = errorText(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String get placeholder => lastScannedUNID.isNotEmpty ? 'Batch Number?' : 'Item ID / Barcode?';

  List<Map<String, dynamic>> _rank(List<int> orderIds) {
    final scores = <int, int>{};
    for (final id in orderIds) {
      if (ordersFin.contains(id) || !ordersList.containsKey(id)) continue;
      var score = 0;
      for (final it in jsonList(ordersList[id]!['items'])) {
        score += asInt(it['qty']) - (scanned[asStr(it['sku']).toUpperCase()] ?? 0);
      }
      if (score >= 0) scores[id] = score;
    }
    final ids = scores.keys.toList()..sort((a, b) => scores[a]!.compareTo(scores[b]!));
    return [for (final id in ids) ordersList[id]!];
  }

  /// Port of packScan.vue handleChangedSearchVal() for an open picklist
  @override
  Future<void> onScan(String code) async {
    if (picklist.isEmpty) return;
    if (finished || status == 120) {
      app.device.warn();
      toast(context, tr('pda.pick.finished'), type: ElType.warning);
      return;
    }
    if (!app.printer.configured) {
      app.device.error();
      _notice(tr('pda.print.notConfigured'), ElType.danger);
      return;
    }
    setState(() {
      orderData = [];
      itemNotFound = false;
      orderNotFound = false;
      notice = '';
    });
    String unid;
    if (lastScannedUNID.isEmpty) {
      try {
        final item = await app.api.query('/v0/item/any', params: {'q': code});
        unid = item is Map ? asStr(item['unid']) : '';
      } on ApiException catch (e) {
        if (e.kind != FailKind.business) {
          app.device.error();
          _notice(errorText(e), ElType.danger);
          return;
        }
        unid = '';
      }
    } else {
      unid = lastScannedUNID;
    }
    if (unid.isEmpty) {
      app.device.error();
      setState(() => itemNotFound = true);
      log(code, Outcome.error, 'Item Not Found');
      return;
    }
    final itemUNID = unid.toUpperCase();
    final searchIndex = lastScannedUNID.isEmpty ? itemUNID : '$lastScannedUNID|||$code';
    var orderIds = mapItemOrders[searchIndex] ?? mapItemOrders[searchIndex.toUpperCase()];
    if (orderIds == null) {
      for (final k in mapItemOrders.keys) {
        if (k.split('|||').first == searchIndex) {
          orderIds = mapItemOrders[k];
          break;
        }
      }
    }
    if (orderIds != null) {
      scanned[itemUNID] = (scanned[itemUNID] ?? 0) + 1;
      final ranked = _rank(orderIds);
      setState(() {
        orderData = ranked;
        orderNotFound = ranked.isEmpty;
        lastScannedUNID = '';
      });
      if (ranked.isEmpty) {
        app.device.error();
        log(code, Outcome.error, 'Order Not Found');
      } else {
        app.device.ok();
        log(code, Outcome.ok, '$itemUNID -> ${asStr(ranked.first['UNID'])}');
        _maybeAutoPrint();
      }
      return;
    }
    final batchKey = mapItemOrders.keys.where((k) => k.startsWith(itemUNID)).firstOrNull;
    if (batchKey != null) {
      // the picklist is batch specific: the next scan must be the batch number
      setState(() {
        orderData = _rank(mapItemOrders[batchKey]!);
        lastScannedUNID = itemUNID;
      });
      app.device.warn();
      if (mounted) toast(context, 'Scan the batch number!', type: ElType.warning);
      return;
    }
    app.device.error();
    setState(() {
      orderNotFound = true;
      lastScannedUNID = '';
    });
    log(code, Outcome.error, 'Order Not Found');
  }

  bool _allScanned(Map<String, dynamic> o) =>
      jsonList(o['items']).every((it) => scanned[asStr(it['sku']).toUpperCase()] == asInt(it['qty']));

  bool _hasPackServices(Map<String, dynamic> o) => (o['packServices'] as List? ?? const []).isNotEmpty;

  bool _hasLabel(Map<String, dynamic> o) => asStr(o['shipSN']).isNotEmpty || asStr(o['shipBundle']).isNotEmpty;

  bool _canPrint(Map<String, dynamic> o) => _allScanned(o) && _hasPackServices(o) && _hasLabel(o);

  void _maybeAutoPrint() {
    if (!app.settings.autoPackScanPrint || printing || orderData.isEmpty) return;
    final first = orderData.first;
    if (_canPrint(first)) {
      toast(context, 'Auto Printing...', type: ElType.success);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _printShipmentLabel(first);
      });
    }
  }

  /// Port of packScan.vue onPrintShipmentLabel()
  Future<void> _printShipmentLabel(Map<String, dynamic> order) async {
    if (printing) {
      toast(context, 'Now is printing. Please wait for finished.', type: ElType.warning);
      return;
    }
    final id = asInt(order['ID']);
    if (ordersFin.contains(id)) {
      await _load();
      return;
    }
    setState(() => printing = true);
    try {
      final full = await app.api.query('/v0/p11yorders/', params: {'q': id});
      final st = full is Map ? asInt(full['status']) : 0;
      if (st == 2 || st == 120) {
        app.device.error();
        if (mounted) await alertBox(context, 'No need to print', 'Order is canceled!');
        return;
      }
      if (st > 15) {
        app.device.error();
        if (mounted) await alertBox(context, 'No need to print again', 'Order already printed!');
        return;
      }
      final packServices = (order['packServices'] as List? ?? const []).cast<String>();
      await svc.rememberPackServices(asStr(order['carrierConfig']), packServices);
      final url = await svc.printShipmentLabelAtScan([
        {'id': id, 'packServices': packServices}
      ]);

      // record progress (label exists now), then print
      var picked = 0;
      final info = [for (final i in itemInfo) Map<String, dynamic>.from(i)];
      for (final it in jsonList(order['items'])) {
        var toPrint = asInt(it['qty']);
        for (final row in info) {
          if (toPrint <= 0) break;
          if (asStr(row['sku']) != asStr(it['sku']) || asStr(row['itemBatch']) != asStr(it['itemBatch'])) continue;
          final remaining = (asInt(row['qty']) - asInt(row['qtyPrinted'])).clamp(0, 1 << 30);
          final n = toPrint < remaining ? toPrint : remaining;
          if (n > 0) {
            row['qtyPrinted'] = asInt(row['qtyPrinted']) + n;
            picked += n;
            toPrint -= n;
          }
        }
      }
      final fin = [...ordersFin, id];
      final p = Map<String, dynamic>.from(picklist)
        ..['ordersFin'] = jsonStr(fin)
        ..['itemInfo'] = jsonStr(info)
        ..['itemQtyPicked'] = itemQtyPicked + picked;
      await svc.save(p);
      log(asStr(order['UNID']), Outcome.ok, 'Shipment Label');
      final err = await svc.printLabel(url, '${asStr(order['UNID'])}_${DateTime.now().millisecondsSinceEpoch}');
      if (err == null) {
        app.device.ok();
        _notice('${asStr(order['UNID'])}: ${tr('pda.pick.printing')}', ElType.success);
      } else {
        app.device.error();
        _notice(err, ElType.danger);
      }
      await _load();
    } catch (e) {
      app.device.error();
      log(asStr(order['UNID']), outcomeOf(e), errorText(e));
      _notice(errorText(e), ElType.danger);
      if (isUnknown(e)) await _load();
    } finally {
      if (mounted) setState(() => printing = false);
    }
  }

  Future<void> _reprint(Map<String, dynamic> order) async {
    if (!await confirm(context, '${asStr(order['UNID'])} - Shipment Label', title: tr('common.print'))) return;
    setState(() => printing = true);
    try {
      final url = await svc.printShipmentLabelAtScan([
        {'id': asInt(order['ID']), 'packServices': order['packServices'] ?? []}
      ]);
      final err = await svc.printLabel(url, 'reprint_${asStr(order['UNID'])}');
      _notice(err ?? tr('pda.pick.printing'), err == null ? ElType.success : ElType.danger);
    } catch (e) {
      _notice(errorText(e), ElType.danger);
    } finally {
      if (mounted) setState(() => printing = false);
    }
  }

  /// packScan.vue onMarkOutOfStock()
  Future<void> _outOfStock(Map<String, dynamic> order) async {
    final id = asInt(order['ID']);
    if (!await confirm(context, 'Mark this order as "Out of Stock"?\n${asStr(order['UNID'])}', danger: true)) return;
    if (ordersFin.contains(id)) {
      await _load();
      return;
    }
    setState(() => printing = true);
    try {
      await app.api.command('GET', '/v0/p11yorders/outOfStock', params: {'q': id});
      final p = Map<String, dynamic>.from(picklist)..['ordersFin'] = jsonStr([...ordersFin, id]);
      await svc.save(p);
      log(asStr(order['UNID']), Outcome.warn, 'Out of Stock');
      await _load();
    } catch (e) {
      app.device.error();
      _notice(errorText(e), ElType.danger);
    } finally {
      if (mounted) setState(() => printing = false);
    }
  }

  Future<void> _editMaterials(Map<String, dynamic> order) async {
    final sel = await pickMaterials(context, packOpts, (order['packServices'] as List? ?? const []).cast<String>());
    if (sel == null) return;
    setState(() => order['packServices'] = sel);
    _maybeAutoPrint();
  }

  void _notice(String msg, ElType t) {
    if (!mounted) return;
    setState(() {
      notice = msg;
      noticeType = t;
    });
  }

  @override
  Widget build(BuildContext context) {
    final unprinted = ordersList.values.where((o) => !ordersFin.contains(asInt(o['ID']))).toList();
    return ScanScaffold(
      title: 'Pack Scan Order',
      placeholder: placeholder,
      busy: busy || loading || printing,
      disabled: status == 120 || finished,
      onManual: manualEntry,
      onRefresh: _load,
      header: Column(mainAxisSize: MainAxisSize.min, children: [
        PicklistHeader(picklist: picklist),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.only(left: 8),
          child: Row(children: [
            const Text('Auto Print', style: TextStyle(fontSize: 13, color: El.textRegular)),
            Transform.scale(
              scale: 0.75,
              child: Switch(
                value: app.settings.autoPackScanPrint,
                onChanged: (v) => setState(() => app.settings.autoPackScanPrint = v),
              ),
            ),
          ]),
        ),
      ]),
      bottom: ElBottomBar(children: [
        FilledButton.icon(
          style: elButton(ElType.primary, plain: !finished),
          onPressed: () => Navigator.of(context).pop('next'),
          icon: const Icon(Icons.swap_horiz, size: 18),
          label: Text(finished ? tr('pda.pick.next') : tr('pda.pick.change')),
        ),
      ]),
      children: [
        if (loadError.isNotEmpty) ElAlert(type: ElType.danger, title: loadError),
        if (notice.isNotEmpty) ElAlert(type: noticeType, title: notice),
        if (!app.printer.configured) ElAlert(type: ElType.warning, title: tr('pda.print.notConfigured')),
        if (itemNotFound)
          const ElResult(
            type: ElType.danger,
            title: 'Item Not Found',
            subTitle: "The scanned code doesn't match any item. Please configure it in the system and try again.",
          ),
        if (orderNotFound)
          const ElResult(
            type: ElType.danger,
            title: 'Order Not Found',
            subTitle: "The scanned code doesn't match any Order. Please check the item and try again.",
          ),
        if (status == 120)
          const ElResult(type: ElType.danger, title: 'This Picklist has been Canceled', subTitle: "Don't need to scan it any more.")
        else if (finished)
          const ElResult(type: ElType.success, title: 'Well Done', subTitle: 'This picklist has been marked as shipped.')
        else if (status == 99)
          const ElResult(type: ElType.warning, title: 'Shipped Partially', subTitle: 'This picklist has been marked as Shipped Partially.'),
        if (scanned.isNotEmpty)
          ElSection(
            'Scanned Item List',
            trailing: TextButton(
              onPressed: () => setState(() {
                scanned = {};
                orderData = [];
                lastScannedUNID = '';
              }),
              child: const Text('Clear'),
            ),
          ),
        if (scanned.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              for (final e in scanned.entries) ElTag('${e.key} × ${e.value}', type: ElType.info),
            ]),
          ),
        if (orderData.isNotEmpty) ...[
          const ElSection('Matched Orders'),
          for (var i = 0; i < orderData.length; i++) _orderCard(orderData[i], i == 0),
        ] else if (!finished && picklist.isNotEmpty && !itemNotFound && !orderNotFound)
          ElAlert(type: ElType.info, title: placeholder),
        if (itemInfo.isNotEmpty) ...[
          const ElSection('Item List'),
          ItemInfoTable(rows: itemInfo),
        ],
        if (ordersFin.isNotEmpty) ...[
          const ElSection('Print History:'),
          for (final id in ordersFin.reversed)
            if (ordersList[id] != null)
              OrderLine(
                order: ordersList[id]!,
                trailing: TextButton.icon(
                  onPressed: printing ? null : () => _reprint(ordersList[id]!),
                  icon: const Icon(Icons.print, size: 16),
                  label: const Text('Shipment Label', style: TextStyle(fontSize: 12.5)),
                ),
              ),
        ],
        if (unprinted.isNotEmpty && orderData.isEmpty) ...[
          const ElSection('Unprinted Orders:'),
          for (final o in unprinted) OrderLine(order: o),
        ],
      ],
    );
  }

  Widget _orderCard(Map<String, dynamic> o, bool first) {
    final items = jsonList(o['items']);
    final materials = (o['packServices'] as List? ?? const []).cast<String>();
    final labels = {for (final m in packOpts) m['value']: m['label']};
    final ready = _canPrint(o);
    return ElCard(
      highlight: ready ? El.success : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.redeem, size: 18, color: El.textRegular),
          const SizedBox(width: 4),
          Expanded(child: Text(asStr(o['UNID']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
          if (asStr(o['carrier']).isNotEmpty) ElTag(asStr(o['carrier']), type: ElType.info),
        ]),
        const SizedBox(height: 6),
        for (final it in items)
          ElAlert(
            margin: const EdgeInsets.only(top: 4),
            type: () {
              final s = scanned[asStr(it['sku']).toUpperCase()] ?? 0;
              final q = asInt(it['qty']);
              return s == q ? ElType.success : (s < q ? ElType.warning : ElType.info);
            }(),
            title: asStr(it['sku']) + (asStr(it['itemBatch']).isNotEmpty ? ' (${asStr(it['itemBatch'])})' : ''),
            description: '${scanned[asStr(it['sku']).toUpperCase()] ?? 0} / ${asInt(it['qty'])}',
          ),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => _editMaterials(o),
          child: ElAlert(
            margin: EdgeInsets.zero,
            type: materials.isEmpty ? ElType.warning : ElType.success,
            title: 'Packing Material',
            description: materials.isEmpty ? '—' : materials.map((m) => labels[m] ?? m).join(', '),
            trailing: const Icon(Icons.edit, size: 16, color: El.textSecondary),
          ),
        ),
        if (_allScanned(o) && _hasPackServices(o) && !_hasLabel(o))
          ElAlert(type: ElType.warning, title: 'Request Shipment Label', description: tr('pda.pick.requestLabelOnPc')),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: elButton(ElType.primary),
              onPressed: ready && !printing ? () => _printShipmentLabel(o) : null,
              icon: const Icon(Icons.print, size: 18),
              label: const Text('Shipment Label'),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: elButton(ElType.danger, plain: true),
            onPressed: printing ? null : () => _outOfStock(o),
            child: const Text('Out of Stock'),
          ),
        ]),
      ]),
    );
  }
}
