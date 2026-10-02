import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/history.dart';
import '../../core/i18n.dart';
import '../../ui/el.dart';
import '../../ui/widgets.dart';
import 'picklist_service.dart';
import 'picklist_widgets.dart';

/// Pick Scan Batch (web: views/warehouse/packScanBatch.vue, menu "Picking Scan").
///
/// Scan item -> enter quantity + packing material -> CarrierGate prints the shipment
/// labels of the next orders containing that item -> picklist progress is saved
/// (itemInfo.qtyPrinted, itemQtyPicked, printBatch). When everything is picked the
/// server moves the picklist to "Packing Completed".
class PickScanBatchPage extends StatefulWidget {
  const PickScanBatchPage({super.key, required this.pickId});

  final int pickId;

  @override
  State<PickScanBatchPage> createState() => _PickScanBatchPageState();
}

class _PickScanBatchPageState extends State<PickScanBatchPage> with ScanPageMixin {
  @override
  String get moduleName => 'pda.pickScanBatch';

  late final PicklistService svc = PicklistService(app);

  Map<String, dynamic> picklist = {};
  List<Map<String, dynamic>> orders = [];
  List<Map<String, dynamic>> itemInfo = [];
  List<Map<String, dynamic>> printBatch = [];
  List<Map<String, String>> packOpts = [];
  List<String> lastMaterials = [];
  bool loading = true;
  String loadError = '';
  bool itemNotFound = false;
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

  Future<void> _load() async {
    setState(() {
      loading = true;
      loadError = '';
    });
    try {
      final p = await svc.load(widget.pickId);
      final info = asStr(p['itemInfo']).isEmpty
          ? [for (final i in jsonList(p['items'])) {...i, 'qtyPrinted': 0}]
          : jsonList(p['itemInfo']);
      setState(() {
        picklist = p;
        orders = jsonList(p['orders']);
        itemInfo = info;
        printBatch = jsonList(p['printBatch']);
      });
    } catch (e) {
      setState(() => loadError = errorText(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  int _findAvailableItemIndex(String sku) =>
      itemInfo.indexWhere((i) => asStr(i['sku']) == sku && asInt(i['qtyPrinted']) < asInt(i['qty']));

  int _printedQty(String sku) =>
      itemInfo.where((i) => asStr(i['sku']) == sku).fold(0, (a, i) => a + asInt(i['qtyPrinted']));

  @override
  Future<void> onScan(String code) async {
    if (picklist.isEmpty) return;
    if (status == 120 || finished) {
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
      itemNotFound = false;
      notice = '';
    });
    String unid;
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
    if (unid.isEmpty) {
      app.device.error();
      setState(() => itemNotFound = true);
      log(code, Outcome.error, 'Item Not Found');
      return;
    }
    final idx = _findAvailableItemIndex(unid);
    if (idx == -1) {
      app.device.error();
      if (!mounted) return;
      await alertBox(context, tr('pda.pick.countAgain'), tr('pda.pick.notEnoughLabels'));
      log(code, Outcome.warn, '$unid: Not enough labels');
      return;
    }
    app.device.ok();
    final row = itemInfo[idx];
    final avail = asInt(row['qty']) - asInt(row['qtyPrinted']);
    if (!mounted) return;
    final input = await showQtyMaterialDialog(
      context,
      sku: unid,
      location: asStr(row['inventoryName']),
      batch: asStr(row['itemBatch']),
      available: avail,
      options: packOpts,
      initialMaterials: lastMaterials,
    );
    if (input == null) {
      if (mounted) toast(context, tr('pda.pick.scanAgain'), type: ElType.warning);
      return;
    }
    lastMaterials = input.materials;
    await _processItem(unid, idx, input.qty, input.materials);
  }

  /// Port of packScanBatch.vue processItem()
  Future<void> _processItem(String sku, int idx, int qty, List<String> materials) async {
    final row = itemInfo[idx];
    if (qty > asInt(row['qty']) - asInt(row['qtyPrinted'])) {
      app.device.error();
      if (!mounted) return;
      await alertBox(context, tr('pda.pick.countAgain'), tr('pda.pick.notEnoughLabels'));
      return;
    }
    final printlist = buildBatchPrintlist(
      orders: orders,
      sku: sku,
      alreadyPrinted: _printedQty(sku),
      qty: qty,
      materials: materials,
    );
    if (printlist.isEmpty) {
      app.device.error();
      if (!mounted) return;
      await alertBox(context, tr('pda.pick.countAgain'), tr('pda.pick.notEnoughLabels'));
      return;
    }

    String url;
    try {
      url = await svc.batchPrintLabel(printlist);
    } catch (e) {
      app.device.error();
      log(sku, outcomeOf(e), errorText(e));
      if (isUnknown(e)) {
        _notice(errorText(e), ElType.danger);
        await _load();
      } else if (mounted) {
        await alertBox(context, 'Error', errorText(e), type: ElType.danger);
      }
      return;
    }

    // record the progress first (labels exist now), then print
    final batch = asStr(row['itemBatch']);
    final loc = asStr(row['inventoryName']);
    final newBatch = {
      'name': '$sku${batch.isNotEmpty ? ' ($batch)' : ''}${loc.isNotEmpty ? ' @ $loc' : ''}:$qty',
      'time': nowString(),
      'data': printlist,
    };
    final info = [for (final i in itemInfo) Map<String, dynamic>.from(i)];
    info[idx]['qtyPrinted'] = asInt(info[idx]['qtyPrinted']) + qty;
    final p = Map<String, dynamic>.from(picklist)
      ..['itemQtyPicked'] = itemQtyPicked + qty
      ..['itemInfo'] = jsonStr(info)
      ..['printBatch'] = jsonStr([...printBatch, newBatch]);
    try {
      await svc.save(p);
      log(sku, Outcome.ok, '${tr('pda.pick.picked')} $qty');
    } catch (e) {
      app.device.error();
      log(sku, outcomeOf(e), errorText(e));
      if (mounted) await alertBox(context, 'Error', '${tr('pda.pick.saveFailed')}\n${errorText(e)}', type: ElType.danger);
      await _load();
      return;
    }
    final err = await svc.printLabel(url, '${asStr(picklist['unid'])}_${sku}_${DateTime.now().millisecondsSinceEpoch}');
    if (err == null) {
      app.device.ok();
      _notice(tr('pda.pick.printing'), ElType.success);
    } else {
      app.device.error();
      _notice(err, ElType.danger);
    }
    await _load();
  }

  Future<void> _reprint(Map<String, dynamic> pb) async {
    if (!await confirm(context, '${tr('pda.pick.shipmentLabel')}: ${asStr(pb['name'])}', title: tr('common.print'))) return;
    setState(() => busy = true);
    try {
      final rows = jsonList(pb['data']);
      final url = await svc.printShipmentLabelAtScan(rows);
      final err = await svc.printLabel(url, 'reprint_${DateTime.now().millisecondsSinceEpoch}');
      _notice(err ?? tr('pda.pick.printing'), err == null ? ElType.success : ElType.danger);
    } catch (e) {
      _notice(errorText(e), ElType.danger);
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
    final printedIds = {
      for (final pb in printBatch)
        for (final d in jsonList(pb['data'])) asInt(d['id'])
    };
    final unprinted = orders.where((o) => !printedIds.contains(asInt(o['ID']))).toList();
    return ScanScaffold(
      title: 'Pick Scan Batch',
      placeholder: picklist.isEmpty ? 'Picklist Number?' : 'Item ID / Barcode?',
      busy: busy || loading,
      disabled: status == 120 || finished,
      onManual: manualEntry,
      onRefresh: _load,
      header: PicklistHeader(picklist: picklist),
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
        if (status == 120)
          const ElResult(type: ElType.danger, title: 'This Picklist has been Canceled', subTitle: "Don't need to scan it any more.")
        else if (finished)
          const ElResult(type: ElType.success, title: 'Well Done', subTitle: 'This picklist has been marked as shipped.')
        else if (status == 99)
          const ElResult(type: ElType.warning, title: 'Shipped Partially', subTitle: 'This picklist has been marked as Shipped Partially.')
        else if (picklist.isNotEmpty && printBatch.isEmpty && !itemNotFound)
          const ElAlert(type: ElType.info, title: 'Please scan the item.'),
        if (itemInfo.isNotEmpty) ...[
          const ElSection('Item List'),
          ItemInfoTable(rows: itemInfo),
        ],
        if (printBatch.isNotEmpty) ...[
          const ElSection('Print History:'),
          for (final pb in printBatch.reversed)
            ElCard(
              onTap: busy ? null : () => _reprint(pb),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(asStr(pb['name']), style: const TextStyle(fontWeight: FontWeight.w600, color: El.textPrimary)),
                    Text(asStr(pb['time']), style: const TextStyle(fontSize: 12, color: El.textSecondary)),
                  ]),
                ),
                const Icon(Icons.print, color: El.primary, size: 18),
                const SizedBox(width: 4),
                const Text('Shipment Label', style: TextStyle(color: El.primary, fontSize: 13)),
              ]),
            ),
        ],
        if (printBatch.isNotEmpty && unprinted.isNotEmpty) ...[
          const ElSection('Unprinted Orders:'),
          for (final o in unprinted) OrderLine(order: o),
        ],
      ],
    );
  }
}
