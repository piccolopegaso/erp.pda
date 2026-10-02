import 'package:flutter/material.dart';

import '../../core/history.dart';
import '../../core/i18n.dart';
import '../../ui/el.dart';
import '../../ui/widgets.dart';
import 'rma_edit_page.dart';
import 'rma_service.dart';

/// RMA (web menu "RMA" / views/receiving/received.vue).
/// Scan a return parcel: an existing RMA opens, otherwise a new one is created
/// (pre-filled from the original order when it can be found).
class RmaPage extends StatefulWidget {
  const RmaPage({super.key});

  @override
  State<RmaPage> createState() => _RmaPageState();
}

class _RmaPageState extends State<RmaPage> with ScanPageMixin {
  @override
  String get moduleName => 'common.rma';

  late final RmaService svc = RmaService(app);

  List<Map<String, dynamic>> rows = [];
  int total = 0;
  int next = 0;
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
      final (r, t, n) = await svc.list(statuses: showAll ? const [] : rmaOpenStatuses);
      setState(() {
        rows = r;
        total = t;
        next = n;
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
      final (r, t, n) = await svc.list(offsetId: next, statuses: showAll ? const [] : rmaOpenStatuses);
      setState(() {
        rows.addAll(r);
        total = t;
        next = n;
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
      final existing = await svc.findByShipSN(code);
      app.device.ok();
      if (existing != null) {
        log(code, Outcome.ok, tr('pda.rma.opened'));
        await _openEdit(id: asInt(existing['id']));
      } else {
        log(code, Outcome.ok, tr('pda.rma.new'));
        await _openEdit(shipSN: code);
      }
    } catch (e) {
      app.device.error();
      setState(() => notice = errorText(e));
      log(code, outcomeOf(e), errorText(e));
    }
  }

  Future<void> _openEdit({int? id, String? shipSN}) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => RmaEditPage(id: id, shipSN: shipSN)));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return ScanScaffold(
      title: tr('common.rma'),
      placeholder: 'Retour/Shipment No.',
      busy: busy,
      onManual: manualEntry,
      onRefresh: _reload,
      actions: [
        IconButton(
          tooltip: tr('pda.rma.new'),
          onPressed: () async {
            final code = await askCode(context, title: 'Tracking Number');
            if (code != null && code.isNotEmpty) handleScanManual(code);
          },
          icon: const Icon(Icons.add),
        ),
      ],
      header: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
        child: Row(children: [
          ChoiceChip(
            visualDensity: VisualDensity.compact,
            label: Text(tr('pda.rma.pending')),
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
        if (rows.isEmpty && !loading && error.isEmpty) const ElResult(type: ElType.info, title: 'Scan the Retour/Shipment No.'),
        for (final r in rows) _card(r),
        if (rows.length < total && next != 0)
          Padding(
            padding: const EdgeInsets.all(8),
            child: OutlinedButton(onPressed: loading ? null : _more, child: Text(tr('pda.loadMore'))),
          ),
        if (loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      ],
    );
  }

  void handleScanManual(String code) {
    resetScanConfirm();
    handleScan(code);
  }

  Widget _card(Map<String, dynamic> r) {
    final st = asInt(r['status']);
    final items = jsonList(r['items']);
    return ElCard(
      onTap: () => _openEdit(id: asInt(r['id'])),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.local_shipping_outlined, size: 16, color: El.textSecondary),
          const SizedBox(width: 4),
          Expanded(child: Text(asStr(r['shipSN']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
          ElTag(rmaStatusLabel(st), type: rmaStatusType(st)),
        ]),
        if (asStr(r['originSN']).isNotEmpty)
          Text('${tr('common.refNo')}: ${asStr(r['originSN'])}', style: const TextStyle(fontSize: 12.5, color: El.textRegular)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: [
          if (app.session.customerName(asStr(r['agentGUID'])).isNotEmpty)
            ElTag(app.session.customerName(asStr(r['agentGUID'])), type: ElType.info),
          if (rmaBusinessTypes[asInt(r['businessType'])] != null) ElTag(rmaBusinessTypes[asInt(r['businessType'])]!, type: ElType.info),
          if (asInt(r['type']) > 1) ElTag(rmaPackageStatus[asInt(r['type'])] ?? '', type: ElType.danger),
        ]),
        if (items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              items.map((i) => '${asStr(i['itemId'])} × ${asStr(i['qty'])}').join(',  '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: El.textRegular),
            ),
          ),
        Text(fmtTime(r['createdAt']), style: const TextStyle(fontSize: 12, color: El.textSecondary)),
      ]),
    );
  }
}
