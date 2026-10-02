import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n.dart';
import '../../ui/el.dart';
import '../../ui/widgets.dart';
import 'picklist_service.dart';

/// "Picklist No. X" + "N item(s) scanned / M in total" tags (web: table-actions-right).
class PicklistHeader extends StatelessWidget {
  const PicklistHeader({super.key, required this.picklist});

  final Map<String, dynamic> picklist;

  @override
  Widget build(BuildContext context) {
    if (picklist.isEmpty) return const SizedBox.shrink();
    final total = asInt(picklist['itemQty']);
    final picked = asInt(picklist['itemQtyPicked']);
    final st = asInt(picklist['status']);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 4, children: [
          ElTag('Picklist No. ${asStr(picklist['unid'])}'),
          ElTag(picklistStatusLabel(st), type: picklistStatusType(st)),
          if (asInt(picklist['priority']) >= 3) ElTag(tr('common.urgent'), type: ElType.danger, dark: true),
        ]),
        const SizedBox(height: 5),
        Row(children: [
          Text('$picked item(s) scanned / $total in total', style: const TextStyle(fontSize: 13, color: El.textRegular)),
        ]),
        const SizedBox(height: 4),
        ElProgress(value: total == 0 ? 0 : picked / total, complete: total > 0 && picked >= total),
      ]),
    );
  }
}

/// web: "Item List" table (Item ID / Location / Batch / Item Name / Total Qty / Printed Qty)
class ItemInfoTable extends StatelessWidget {
  const ItemInfoTable({super.key, required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: El.borderLight)),
      child: Column(children: [
        Container(
          color: El.labelBg,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: const Row(children: [
            Expanded(child: Text('Item ID / Location', style: TextStyle(fontSize: 12, color: El.textSecondary, fontWeight: FontWeight.w600))),
            Text('Printed / Total', style: TextStyle(fontSize: 12, color: El.textSecondary, fontWeight: FontWeight.w600)),
          ]),
        ),
        for (final r in rows)
          Container(
            decoration: BoxDecoration(
              color: asInt(r['qtyPrinted']) >= asInt(r['qty']) ? const Color(0xFFF0F9EB) : Colors.white,
              border: const Border(top: BorderSide(color: El.borderLight)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(asStr(r['sku']), style: const TextStyle(fontWeight: FontWeight.w600, color: El.textPrimary)),
                  if (asStr(r['inventoryName']).isNotEmpty || asStr(r['itemBatch']).isNotEmpty)
                    Text(
                      [asStr(r['inventoryName']), if (asStr(r['itemBatch']).isNotEmpty) 'Batch: ${asStr(r['itemBatch'])}'].join('  ·  '),
                      style: const TextStyle(fontSize: 12.5, color: El.primary),
                    ),
                  if (asStr(r['itemName']).isNotEmpty)
                    Text(asStr(r['itemName']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: El.textSecondary)),
                ]),
              ),
              Text('${asInt(r['qtyPrinted'])} / ${asInt(r['qty'])}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: asInt(r['qtyPrinted']) >= asInt(r['qty']) ? El.success : El.textPrimary,
                  )),
            ]),
          ),
      ]),
    );
  }
}

class OrderLine extends StatelessWidget {
  const OrderLine({super.key, required this.order, this.trailing});

  final Map<String, dynamic> order;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final items = jsonList(order['items']);
    return ElCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(asStr(order['UNID']), style: const TextStyle(fontWeight: FontWeight.w600, color: El.textPrimary)),
            for (final i in items) Text('${asStr(i['sku'])} x ${asStr(i['qty'])}', style: const TextStyle(fontSize: 12.5, color: El.textRegular)),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class QtyMaterialInput {
  QtyMaterialInput(this.qty, this.materials);

  final int qty;
  final List<String> materials;
}

/// packScanBatch.vue quantity dialog: quantity (1-50) + Packing Material (required).
Future<QtyMaterialInput?> showQtyMaterialDialog(
  BuildContext context, {
  required String sku,
  required String location,
  required String batch,
  required int available,
  required List<Map<String, String>> options,
  required List<String> initialMaterials,
}) {
  return showDialog<QtyMaterialInput>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _QtyMaterialDialog(
      sku: sku,
      location: location,
      batch: batch,
      available: available,
      options: options,
      initial: initialMaterials,
    ),
  );
}

class _QtyMaterialDialog extends StatefulWidget {
  const _QtyMaterialDialog({
    required this.sku,
    required this.location,
    required this.batch,
    required this.available,
    required this.options,
    required this.initial,
  });

  final String sku;
  final String location;
  final String batch;
  final int available;
  final List<Map<String, String>> options;
  final List<String> initial;

  @override
  State<_QtyMaterialDialog> createState() => _QtyMaterialDialogState();
}

class _QtyMaterialDialogState extends State<_QtyMaterialDialog> {
  final _qty = TextEditingController();
  late final List<String> _materials = [...widget.initial.where((m) => widget.options.any((o) => o['value'] == m))];
  String _error = '';

  void _ok() {
    final q = int.tryParse(_qty.text.trim()) ?? 0;
    if (q <= 0 || q > 50) {
      setState(() => _error = 'Please enter a number between 1-50!');
      return;
    }
    if (_materials.isEmpty) {
      setState(() => _error = 'Please select Packing Material!');
      return;
    }
    Navigator.pop(context, QtyMaterialInput(q, _materials));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      title: Text(widget.sku, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 4, children: [
            if (widget.location.isNotEmpty) ElTag(widget.location),
            if (widget.batch.isNotEmpty) ElTag('Batch: ${widget.batch}', type: ElType.info),
            ElTag('Available: ${widget.available}', type: ElType.success),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _qty,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder(), isDense: true),
            onSubmitted: (_) => _ok(),
          ),
          const SizedBox(height: 10),
          const Text('Packing Material', style: TextStyle(fontSize: 13, color: El.textRegular, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          if (widget.options.isEmpty) Text(tr('pda.noData'), style: const TextStyle(color: El.textSecondary)),
          Wrap(spacing: 6, runSpacing: 2, children: [
            for (final o in widget.options)
              FilterChip(
                showCheckmark: false,
                selectedColor: const Color(0xFFD9ECFF),
                visualDensity: VisualDensity.compact,
                label: Text(o['label']!, style: const TextStyle(fontSize: 12.5)),
                selected: _materials.contains(o['value']),
                onSelected: (v) => setState(() => v ? _materials.add(o['value']!) : _materials.remove(o['value'])),
              ),
          ]),
          if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error, style: const TextStyle(color: El.danger))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('common.cancelButtonText'))),
        FilledButton(onPressed: _ok, child: Text(tr('common.confirmButtonText'))),
      ],
    );
  }
}

/// Multi-select of packing materials (Pack Scan Order card).
Future<List<String>?> pickMaterials(BuildContext context, List<Map<String, String>> options, List<String> selected) {
  final sel = [...selected];
  return showDialog<List<String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
        title: const Text('Packing Material', style: TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Wrap(spacing: 6, runSpacing: 2, children: [
            for (final o in options)
              FilterChip(
                showCheckmark: false,
                selectedColor: const Color(0xFFD9ECFF),
                visualDensity: VisualDensity.compact,
                label: Text(o['label']!, style: const TextStyle(fontSize: 12.5)),
                selected: sel.contains(o['value']),
                onSelected: (v) => set(() => v ? sel.add(o['value']!) : sel.remove(o['value'])),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('common.cancelButtonText'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, sel), child: Text(tr('common.confirmButtonText'))),
        ],
      ),
    ),
  );
}
