import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/history.dart';
import '../../core/i18n.dart';
import '../../ui/el.dart';
import '../../ui/widgets.dart';
import 'rma_inbound_page.dart';
import 'rma_service.dart';

/// One RMA (r7g receiving record): web "Edit Scan" dialog fields + item scanning.
class RmaEditPage extends StatefulWidget {
  const RmaEditPage({super.key, this.id, this.shipSN});

  /// existing record
  final int? id;

  /// new record for this tracking number
  final String? shipSN;

  @override
  State<RmaEditPage> createState() => _RmaEditPageState();
}

class _RmaEditPageState extends State<RmaEditPage> with ScanPageMixin {
  @override
  String get moduleName => 'common.rma';

  late final RmaService svc = RmaService(app);

  Map<String, dynamic> rec = {};
  List<Map<String, dynamic>> items = [];
  List<String> images = [];
  Map<String, dynamic>? order;
  bool loading = true;
  bool saving = false;
  bool dirty = false;
  String error = '';
  String notice = '';
  ElType noticeType = ElType.success;

  int get id => asInt(rec['id']);
  bool get isNew => id == 0;
  int get status => asInt(rec['status']);
  bool get readOnly => status >= 100;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    try {
      if (widget.id != null) {
        _apply(await svc.one(widget.id!));
      } else {
        final code = widget.shipSN ?? '';
        _apply({
          'id': 0,
          'shipSN': code,
          'originSN': '',
          'originShipSN': '',
          'businessType': 2,
          'agentGUID': '',
          'type': 1,
          'note': '',
          'items': '[]',
          'image': '',
          'status': 0,
        });
        dirty = true;
        final o = await svc.findOrder(code);
        if (o != null && mounted) {
          setState(() {
            order = o;
            rec['originSN'] = asStr(o['unid']);
            rec['agentGUID'] = asStr(o['agentGUID']);
            final shipSN = asStr(o['shipSN']);
            if (shipSN.isNotEmpty && shipSN.toUpperCase() != code.toUpperCase()) rec['originShipSN'] = shipSN;
            if (asStr(o['recCountry']).isNotEmpty) rec['originCountry'] = asStr(o['recCountry']);
          });
        }
      }
    } catch (e) {
      error = errorText(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _apply(Map<String, dynamic> r) {
    setState(() {
      rec = r;
      items = jsonList(r['items']);
      images = RmaService.imagesOf(r);
      dirty = false;
    });
  }

  // ---------------- scanning: items ----------------

  @override
  Future<void> onScan(String code) async {
    if (readOnly || loading) return;
    setState(() => notice = '');
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
      _notice('Item Not Found: $code', ElType.danger);
      log(code, Outcome.error, 'Item Not Found');
      return;
    }
    final i = items.indexWhere((r) => asStr(r['itemId']) == unid && asStr(r['itemBatch']).isEmpty && asInt(r['valid']) == 1);
    setState(() {
      if (i >= 0) {
        items[i]['qty'] = asInt(items[i]['qty']) + 1;
      } else {
        items.add({'itemId': unid, 'itemBatch': '', 'qty': 1, 'valid': 1, 'remark': ''});
      }
      dirty = true;
    });
    final origin = _originItems();
    if (origin.isNotEmpty && !origin.containsKey(unid.toUpperCase())) {
      app.device.warn();
      _notice('$unid: item not in original order', ElType.warning);
    } else {
      app.device.ok();
      _notice('Got Item $unid !', ElType.success);
    }
    log(code, Outcome.ok, unid);
  }

  /// expected items of the original order (SKU -> qty)
  Map<String, int> _originItems() {
    final out = <String, int>{};
    for (final i in jsonList(order?['items'])) {
      out[asStr(i['sku']).toUpperCase()] = asInt(i['qty']);
    }
    if (out.isEmpty) {
      final s = asStr(rec['itemStrOrigin']).split(':');
      for (var k = 0; k + 1 < s.length; k += 2) {
        out[s[k].toUpperCase()] = int.tryParse(s[k + 1]) ?? 0;
      }
    }
    return out;
  }

  void _notice(String msg, ElType t) {
    if (!mounted) return;
    setState(() {
      notice = msg;
      noticeType = t;
    });
  }

  // ---------------- save ----------------

  Map<String, dynamic> _payload() => {
        ...rec,
        'items': jsonEncode(items),
        'image': images.isEmpty ? '' : jsonEncode({'img': [for (final u in images) {'url': u}]}),
      };

  Future<bool> _save() async {
    if (asStr(rec['shipSN']).trim().isEmpty) {
      _notice('Tracking Number required.', ElType.danger);
      return false;
    }
    setState(() => saving = true);
    try {
      if (isNew) {
        final created = await svc.create(_payload()..remove('id'));
        _apply(created);
      } else {
        await svc.update(_payload());
        _apply(await svc.one(id));
      }
      app.device.ok();
      _notice(tr('pda.saved'), ElType.success);
      log(asStr(rec['shipSN']), Outcome.ok, tr('pda.saved'));
      return true;
    } catch (e) {
      app.device.error();
      _notice(errorText(e), ElType.danger);
      log(asStr(rec['shipSN']), outcomeOf(e), errorText(e));
      return false;
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _inbound() async {
    if (items.isEmpty) {
      _notice(tr('pda.rma.noItems'), ElType.warning);
      return;
    }
    if (asStr(rec['agentGUID']).isEmpty) {
      _notice(tr('pda.rma.customerRequired'), ElType.warning);
      return;
    }
    if (dirty && !await _save()) return;
    if (!mounted) return;
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => RmaInboundPage(record: rec)));
    if (done == true && mounted) {
      _apply(await svc.one(id));
      _notice(tr('wms.taskInbounded'), ElType.success);
    }
  }

  Future<bool> _confirmLeave() async {
    if (!dirty || readOnly) return true;
    return confirm(context, tr('pda.rma.discard'), danger: true);
  }

  // ---------------- photos ----------------

  Future<void> _takePhoto() async {
    String? path;
    try {
      path = await app.device.takePhoto();
    } catch (e) {
      _notice('$e', ElType.danger);
      return;
    }
    if (path == null) return;
    setState(() => saving = true);
    try {
      final url = await svc.uploadImage(path);
      setState(() {
        images.add(url);
        dirty = true;
      });
      _notice(tr('pda.rma.photoUploaded'), ElType.success);
    } catch (e) {
      _notice(errorText(e), ElType.danger);
    } finally {
      try {
        File(path).deleteSync();
      } catch (_) {}
      if (mounted) setState(() => saving = false);
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final title = isNew ? '${tr('common.rma')} · ${tr('pda.rma.new')}' : '${tr('common.rma')} · ${asStr(rec['shipSN'])}';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.of(context).pop();
      },
      child: ScanScaffold(
        title: title,
        placeholder: readOnly ? rmaStatusLabel(status) : 'Item?',
        busy: busy || loading || saving,
        disabled: readOnly,
        onManual: manualEntry,
        bottom: readOnly || loading
            ? null
            : ElBottomBar(children: [
                FilledButton.icon(
                  style: elButton(ElType.primary, plain: true),
                  onPressed: saving ? null : _save,
                  icon: const Icon(Icons.save, size: 18),
                  label: Text(tr('pda.save')),
                ),
                FilledButton.icon(
                  style: elButton(ElType.success),
                  onPressed: saving ? null : _inbound,
                  icon: const Icon(Icons.check_box_outlined, size: 18),
                  label: Text(tr('common.inbound')),
                ),
              ]),
        children: loading
            ? [const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))]
            : [
                if (error.isNotEmpty) ElAlert(type: ElType.danger, title: error),
                if (notice.isNotEmpty) ElAlert(type: noticeType, title: notice),
                if (!isNew)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Wrap(spacing: 6, children: [
                      ElTag(rmaStatusLabel(status), type: rmaStatusType(status), small: false),
                      if (fmtTime(rec['createdAt']).isNotEmpty) ElTag(fmtTime(rec['createdAt']), type: ElType.info, small: false),
                    ]),
                  ),
                _form(),
                _originHint(),
                ElSection('Items Info (${items.fold<int>(0, (a, i) => a + asInt(i['qty']))})'),
                if (items.isEmpty) ElAlert(type: ElType.info, title: readOnly ? tr('pda.noData') : 'Item?'),
                for (var i = 0; i < items.length; i++) _itemRow(i),
                ElSection(
                  'Image',
                  trailing: readOnly
                      ? null
                      : TextButton.icon(onPressed: saving ? null : _takePhoto, icon: const Icon(Icons.photo_camera, size: 18), label: Text(tr('pda.rma.photo'))),
                ),
                if (images.isNotEmpty)
                  SizedBox(
                    height: 84,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: [for (final u in images) _thumb(u)],
                    ),
                  ),
              ],
      ),
    );
  }

  Widget _field(String label, Widget child) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          SizedBox(width: 92, child: Text(label, style: const TextStyle(fontSize: 13, color: El.textRegular))),
          Expanded(child: child),
        ]),
      );

  Widget _textValue(String key, {String? hint, int maxLines = 1}) {
    return InkWell(
      onTap: readOnly
          ? null
          : () async {
              final v = await askCode(context, title: hint, initial: asStr(rec[key]));
              if (v != null) {
                setState(() {
                  rec[key] = v;
                  dirty = true;
                });
              }
            },
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(border: Border.all(color: El.border), borderRadius: BorderRadius.circular(4), color: readOnly ? const Color(0xFFF5F7FA) : Colors.white),
        child: Text(asStr(rec[key]).isEmpty ? '—' : asStr(rec[key]), maxLines: maxLines, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
      ),
    );
  }

  Widget _select<T>(T value, Map<T, String> options, void Function(T) onChanged) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(border: Border.all(color: El.border), borderRadius: BorderRadius.circular(4), color: readOnly ? const Color(0xFFF5F7FA) : Colors.white),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: options.containsKey(value) ? value : null,
          items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 14)))],
          onChanged: readOnly ? null : (v) => v == null ? null : onChanged(v),
        ),
      ),
    );
  }

  Widget _form() {
    final customers = app.session.customers;
    final agent = asStr(rec['agentGUID']);
    return ElCard(
      child: Column(children: [
        _field('Tracking Number', _textValue('shipSN', hint: 'Tracking Number')),
        _field(tr('common.refNo'), _textValue('originSN', hint: tr('common.refNo'))),
        _field(tr('common.origTrackingNo'), _textValue('originShipSN', hint: tr('common.origTrackingNo'))),
        _field(tr('common.type'), _select<int>(asInt(rec['businessType']), rmaBusinessTypes, (v) => setState(() {
              rec['businessType'] = v;
              dirty = true;
            }))),
        _field(
          tr('common.customer'),
          InkWell(
            onTap: readOnly ? null : _pickCustomer,
            child: Container(
              height: 36,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(color: agent.isEmpty && !readOnly ? El.warning : El.border),
                borderRadius: BorderRadius.circular(4),
                color: readOnly ? const Color(0xFFF5F7FA) : Colors.white,
              ),
              child: Text(agent.isEmpty ? '—' : (customers[agent] ?? agent), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
        _field('Package Status', _select<int>(asInt(rec['type']), rmaPackageStatus, (v) => setState(() {
              rec['type'] = v;
              dirty = true;
            }))),
        _field(tr('common.remark'), _textValue('note', hint: tr('common.remark'), maxLines: 3)),
      ]),
    );
  }

  Widget _originHint() {
    final origin = _originItems();
    if (origin.isEmpty) return const SizedBox.shrink();
    return ElAlert(
      type: ElType.info,
      title: tr('pda.rma.originItems'),
      description: origin.entries.map((e) => '${e.key} × ${e.value}').join(',  '),
    );
  }

  Future<void> _pickCustomer() async {
    final customers = app.session.customers;
    final ctrl = TextEditingController();
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final q = ctrl.text.toLowerCase();
        final list = customers.entries.where((e) => q.isEmpty || e.value.toLowerCase().contains(q)).toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
          title: Text(tr('common.customer'), style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            height: 360,
            child: Column(children: [
              TextField(
                controller: ctrl,
                decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search), hintText: tr('common.search')),
                onChanged: (_) => set(() {}),
              ),
              Expanded(
                child: ListView(children: [
                  for (final e in list)
                    ListTile(dense: true, title: Text(e.value), onTap: () => Navigator.pop(ctx, e.key)),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
    if (picked != null) {
      setState(() {
        rec['agentGUID'] = picked;
        dirty = true;
      });
    }
  }

  Widget _itemRow(int i) {
    final r = items[i];
    return ElCard(
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              asStr(r['itemId']) + (asStr(r['itemBatch']).isNotEmpty ? ' (${asStr(r['itemBatch'])})' : ''),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          if (asStr(r['location']).isNotEmpty) ElTag(asStr(r['location'])),
          if (!readOnly)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, color: El.danger, size: 20),
              onPressed: () async {
                if (await confirm(context, '${tr('pda.delete')} ${asStr(r['itemId'])}?', danger: true)) {
                  setState(() {
                    items.removeAt(i);
                    dirty = true;
                  });
                }
              },
            ),
        ]),
        Row(children: [
          if (!readOnly)
            _stepButton(Icons.remove, asInt(r['qty']) > 1 ? () => setState(() {
                  r['qty'] = asInt(r['qty']) - 1;
                  dirty = true;
                }) : null),
          InkWell(
            onTap: readOnly
                ? null
                : () async {
                    final v = await askCode(context, title: tr('common.quantity'), initial: '${asInt(r['qty'])}', keyboard: TextInputType.number);
                    final n = int.tryParse(v ?? '');
                    if (n != null && n > 0) {
                      setState(() {
                        r['qty'] = n;
                        dirty = true;
                      });
                    }
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('× ${asInt(r['qty'])}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
          ),
          if (!readOnly)
            _stepButton(Icons.add, () => setState(() {
                  r['qty'] = asInt(r['qty']) + 1;
                  dirty = true;
                })),
          const SizedBox(width: 8),
          Expanded(
            child: _select<int>(asInt(r['valid']), rmaItemValid, (v) => setState(() {
                  r['valid'] = v;
                  dirty = true;
                })),
          ),
          const SizedBox(width: 4),
        ]),
        InkWell(
          onTap: readOnly
              ? null
              : () async {
                  final v = await askCode(context, title: tr('common.remark'), initial: asStr(r['remark']));
                  if (v != null) {
                    setState(() {
                      r['remark'] = v;
                      dirty = true;
                    });
                  }
                },
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Text(
              asStr(r['remark']).isEmpty ? (readOnly ? '' : '+ ${tr('common.remark')}') : asStr(r['remark']),
              style: TextStyle(fontSize: 12.5, color: asStr(r['remark']).isEmpty ? El.primary : El.textRegular),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _stepButton(IconData icon, VoidCallback? onTap) => SizedBox(
        width: 34,
        height: 32,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
          onPressed: onTap,
          child: Icon(icon, size: 16),
        ),
      );

  Widget _thumb(String url) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => showDialog(
          context: context,
          builder: (ctx) => Dialog(
            insetPadding: const EdgeInsets.all(8),
            child: Stack(children: [
              InteractiveViewer(child: _netImage(url, BoxFit.contain)),
              if (!readOnly)
                Positioned(
                  right: 4,
                  top: 4,
                  child: IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: El.danger),
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() {
                        images.remove(url);
                        dirty = true;
                      });
                    },
                    icon: const Icon(Icons.delete, color: Colors.white),
                  ),
                ),
            ]),
          ),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(4), child: SizedBox(width: 80, height: 80, child: _netImage(url, BoxFit.cover))),
      ),
    );
  }

  Widget _netImage(String url, BoxFit fit) => Image.network(
        svc.staticUrl(url),
        fit: fit,
        headers: {'X-Token': app.settings.token, 'Origin': app.settings.origin},
        errorBuilder: (_, __, ___) => Container(color: El.borderLight, child: const Icon(Icons.broken_image, color: El.textSecondary)),
      );
}

