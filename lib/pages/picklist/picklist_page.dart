import 'package:flutter/material.dart';

import '../../core/history.dart';
import '../../core/i18n.dart';
import '../../ui/el.dart';
import '../../ui/widgets.dart';
import 'pack_scan_order_page.dart';
import 'pick_scan_batch_page.dart';
import 'picklist_service.dart';

/// Picklist (web menu "Picklist" / views/warehouse/picklist.vue):
/// open picklists, scan a picklist number to start Pick Scan Batch / Pack Scan Order.
class PicklistPage extends StatefulWidget {
  const PicklistPage({super.key});

  @override
  State<PicklistPage> createState() => _PicklistPageState();
}

class _PicklistPageState extends State<PicklistPage> with ScanPageMixin {
  @override
  String get moduleName => 'wms.picklist';

  late final PicklistService svc = PicklistService(app);

  /// statuses still to be picked/packed
  static const openStatuses = [0, 1, 3, 4, 5, 10, 15, 95];

  List<Map<String, dynamic>> rows = [];
  int total = 0;
  bool loading = false;
  bool showAll = false;
  String error = '';
  String notice = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final (r, t) = await svc.list(statuses: showAll ? const [] : openStatuses);
      setState(() {
        rows = r;
        total = t;
      });
    } catch (e) {
      setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _more() async {
    setState(() => loading = true);
    try {
      final (r, t) = await svc.list(offset: rows.length, statuses: showAll ? const [] : openStatuses);
      setState(() {
        rows.addAll(r);
        total = t;
      });
    } catch (e) {
      if (mounted) toast(context, errorText(e), type: ElType.danger);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Future<void> onScan(String code) async {
    setState(() => notice = '');
    try {
      final p = await svc.findByAny(code);
      if (p == null) {
        app.device.error();
        setState(() => notice = 'Picklist not found, please try again.');
        log(code, Outcome.error, 'not found');
        return;
      }
      app.device.ok();
      log(code, Outcome.ok, asStr(p['unid']));
      await _open(asInt(p['id']), asInt(p['type']));
    } catch (e) {
      app.device.error();
      setState(() => notice = errorText(e));
      log(code, outcomeOf(e), errorText(e));
    }
  }

  Future<void> _open(int id, int type) async {
    if (type != 1 && type != 100) {
      setState(() => notice = 'Pack Scan type not match!');
      return;
    }
    final r = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => type == 100 ? PickScanBatchPage(pickId: id) : PackScanOrderPage(pickId: id),
    ));
    if (!mounted) return;
    _reload();
    if (r == 'next') setState(() => notice = '');
  }

  @override
  Widget build(BuildContext context) {
    return ScanScaffold(
      title: tr('wms.picklist'),
      placeholder: 'Picklist Number?',
      busy: busy,
      onManual: manualEntry,
      onRefresh: _reload,
      header: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
        child: Row(children: [
          ChoiceChip(
            visualDensity: VisualDensity.compact,
            label: Text(tr('pda.pick.todo')),
            selected: !showAll,
            onSelected: (_) {
              showAll = false;
              _reload();
            },
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            visualDensity: VisualDensity.compact,
            label: Text(tr('pda.all')),
            selected: showAll,
            onSelected: (_) {
              showAll = true;
              _reload();
            },
          ),
          const Spacer(),
          Text(tr('pda.total', {'n': total}), style: const TextStyle(fontSize: 12.5, color: El.textSecondary)),
        ]),
      ),
      children: [
        if (notice.isNotEmpty) ElAlert(type: ElType.danger, title: notice),
        if (error.isNotEmpty) ElAlert(type: ElType.danger, title: error),
        if (rows.isEmpty && !loading && error.isEmpty)
          const ElResult(type: ElType.info, title: 'Please Scan the Picklist Number'),
        for (final r in rows) _card(r),
        if (rows.length < total)
          Padding(
            padding: const EdgeInsets.all(8),
            child: OutlinedButton(onPressed: loading ? null : _more, child: Text(tr('pda.loadMore'))),
          ),
        if (loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      ],
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final st = asInt(r['status']);
    final total = asInt(r['itemQty']);
    final picked = asInt(r['itemQtyPicked']);
    final type = asInt(r['type']);
    return ElCard(
      onTap: () => _open(asInt(r['id']), type),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.fingerprint, size: 16, color: El.textSecondary),
          const SizedBox(width: 4),
          Expanded(child: Text(asStr(r['unid']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
          if (asInt(r['priority']) >= 3) const ElTag('URGENT!', type: ElType.danger, dark: true),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: [
          ElTag(picklistTypeLabel(type), type: type == 100 ? ElType.warning : ElType.info),
          ElTag(picklistStatusLabel(st), type: picklistStatusType(st)),
          if (asStr(r['carrier']).isNotEmpty) ElTag(asStr(r['carrier']), type: ElType.info),
          ElTag('${asInt(r['shipQty'])} PKG', type: ElType.info),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: ElProgress(value: total == 0 ? 0 : picked / total, complete: total > 0 && picked >= total)),
          const SizedBox(width: 8),
          Text('$picked / $total', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
        if (app.session.customerName(asStr(r['agentGUID'])).isNotEmpty || fmtTime(r['createdAt']).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              [app.session.customerName(asStr(r['agentGUID'])), fmtTime(r['createdAt'])].where((s) => s.isNotEmpty).join('  ·  '),
              style: const TextStyle(fontSize: 12, color: El.textSecondary),
            ),
          ),
      ]),
    );
  }
}
