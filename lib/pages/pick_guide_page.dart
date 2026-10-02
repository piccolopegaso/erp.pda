import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/history.dart';
import '../core/i18n.dart';
import '../ui/widgets.dart';

class _Line {
  _Line(this.index, this.raw);

  final int index;
  final Map<String, dynamic> raw;
  int picked = 0;

  String get sku => asStr(raw['sku']);
  String get location => asStr(raw['inventoryName']);
  String get batch => asStr(raw['itemBatch']);
  String get name => asStr(raw['itemName']);
  int get qty => asInt(raw['qty']);
  bool get done => picked >= qty;
}

/// Pick guide: loads a picklist (read-only) and walks the picker through it in
/// location order. Progress is kept on the device only - nothing is written back,
/// packing/confirmation stays at the pack station (web: packScan*).
/// Once the list is loaded it keeps working without network.
class PickGuidePage extends StatefulWidget {
  const PickGuidePage({super.key});

  @override
  State<PickGuidePage> createState() => _PickGuidePageState();
}

class _PickGuidePageState extends State<PickGuidePage> with ScanPageMixin {
  @override
  String get moduleName => 'mod.pick';

  Map<String, dynamic> _list = {};
  List<_Line> _lines = [];
  final List<int> _undo = [];
  Tone _tone = Tone.info;
  String _title = '';
  String _sub = '';

  int get _id => asInt(_list['id']);

  // ---------- natural sort for location names like A-2-10 vs A-10-1 ----------
  static int _natural(String a, String b) {
    final re = RegExp(r'(\d+)|(\D+)');
    final pa = re.allMatches(a.toUpperCase()).map((m) => m.group(0)!).toList();
    final pb = re.allMatches(b.toUpperCase()).map((m) => m.group(0)!).toList();
    for (var i = 0; i < pa.length && i < pb.length; i++) {
      final na = int.tryParse(pa[i]);
      final nb = int.tryParse(pb[i]);
      final c = (na != null && nb != null) ? na.compareTo(nb) : pa[i].compareTo(pb[i]);
      if (c != 0) return c;
    }
    return pa.length.compareTo(pb.length);
  }

  @override
  Future<void> onScan(String code) async {
    if (_id == 0) return _loadList(code);
    return _pick(code);
  }

  Future<void> _loadList(String code) async {
    try {
      final found = await app.api.query('/v0/p11y/pick/any', params: {'q': code});
      final id = found is Map ? asInt(found['id']) : 0;
      if (id == 0) {
        app.device.error();
        _show(Tone.error, tr('common.notFound', {'code': code}));
        log(code, Outcome.error, 'picklist not found');
        return;
      }
      final data = await app.api.query('/v0/p11y/pick/', params: {'q': id});
      if (data is! Map) throw ApiException(FailKind.business, 'empty picklist');
      _list = Map<String, dynamic>.from(data);
      final raw = jsonList(_list['items']);
      _lines = [for (var i = 0; i < raw.length; i++) _Line(i, raw[i])]
        ..sort((a, b) {
          final c = _natural(a.location, b.location);
          return c != 0 ? c : a.sku.compareTo(b.sku);
        });
      // restore local progress
      final saved = app.settings.readJson<Map>('pick:$id') ?? const {};
      for (final l in _lines) {
        l.picked = asInt(saved['${l.index}']).clamp(0, l.qty);
      }
      _undo.clear();
      if (asInt(_list['status']) == 120) {
        app.device.error();
        _show(Tone.error, tr('pick.canceled'), asStr(_list['unid']));
      } else {
        app.device.ok();
        _show(Tone.ok, asStr(_list['unid']), tr('pick.scanItem'));
      }
      log(code, Outcome.ok, asStr(_list['unid']));
    } catch (e) {
      app.device.error();
      _show(e is ApiException && e.kind == FailKind.unknown ? Tone.unknown : Tone.error, errorText(e), code);
      log(code, outcomeOf(e), errorText(e));
    }
  }

  /// Barcode -> SKU, cached on the device so picking keeps working in Wi-Fi dead zones.
  Future<String?> _resolveSku(String code) async {
    if (_lines.any((l) => l.sku.toLowerCase() == code.toLowerCase())) {
      return _lines.firstWhere((l) => l.sku.toLowerCase() == code.toLowerCase()).sku;
    }
    final cache = app.settings.readJson<Map>('barcodeSku') ?? {};
    if (cache[code] != null) return '${cache[code]}';
    try {
      final item = await app.api.query('/v0/item/any', params: {'q': code});
      final unid = item is Map ? asStr(item['unid']) : '';
      if (unid.isEmpty) return null;
      final m = Map<String, dynamic>.from(cache);
      if (m.length > 3000) m.clear();
      m[code] = unid;
      await app.settings.writeJson('barcodeSku', m);
      return unid;
    } on ApiException catch (e) {
      if (e.kind == FailKind.business) return null;
      rethrow;
    }
  }

  Future<void> _pick(String code) async {
    try {
      final sku = await _resolveSku(code);
      if (sku == null) {
        app.device.error();
        _show(Tone.error, tr('common.notFound', {'code': code}));
        log(code, Outcome.error, 'item not found');
        return;
      }
      final open = _lines.where((l) => l.sku == sku && !l.done).toList();
      if (open.isEmpty) {
        app.device.error();
        final inList = _lines.any((l) => l.sku == sku);
        _show(inList ? Tone.warn : Tone.error, tr(inList ? 'pick.lineDone' : 'pick.notInList', {'sku': sku}));
        log(code, inList ? Outcome.warn : Outcome.error, sku);
        return;
      }
      final next = _nextLine;
      final line = (next != null && next.sku == sku) ? next : open.first;
      line.picked++;
      _undo.add(line.index);
      _save();
      log(code, Outcome.ok, '$sku @ ${line.location}');
      if (_allDone) {
        app.device.ok();
        _show(Tone.ok, tr('pick.done'), asStr(_list['unid']));
      } else if (next != null && next.sku != sku) {
        app.device.warn();
        _show(Tone.warn, tr('pick.picked', {'sku': sku, 'loc': line.location}), tr('pick.wrongLocation', {'sku': sku, 'loc': line.location}));
      } else {
        app.device.ok();
        _show(Tone.ok, tr('pick.picked', {'sku': sku, 'loc': line.location}), '${line.picked}/${line.qty}');
      }
    } catch (e) {
      app.device.error();
      _show(Tone.error, errorText(e), code);
      log(code, outcomeOf(e), errorText(e));
    }
  }

  _Line? get _nextLine {
    for (final l in _lines) {
      if (!l.done) return l;
    }
    return null;
  }

  bool get _allDone => _lines.isNotEmpty && _lines.every((l) => l.done);

  void _save() {
    app.settings.writeJson('pick:$_id', {for (final l in _lines) if (l.picked > 0) '${l.index}': l.picked});
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    final idx = _undo.removeLast();
    final l = _lines.firstWhere((x) => x.index == idx);
    if (l.picked > 0) l.picked--;
    _save();
    setState(() {});
  }

  Future<void> _resetProgress() async {
    if (!await confirm(context, '${tr('pick.reset')}?')) return;
    for (final l in _lines) {
      l.picked = 0;
    }
    _undo.clear();
    _save();
    setState(() {});
  }

  void _show(Tone t, String title, [String sub = '']) => setState(() {
        _tone = t;
        _title = title;
        _sub = sub;
      });

  void _changeList() => setState(() {
        _list = {};
        _lines = [];
        _undo.clear();
        _title = '';
        _sub = '';
      });

  @override
  Widget build(BuildContext context) {
    final total = _lines.fold<int>(0, (a, l) => a + l.qty);
    final picked = _lines.fold<int>(0, (a, l) => a + (l.picked > l.qty ? l.qty : l.picked));
    final next = _nextLine;
    return ScanScaffold(
      title: tr('mod.pick'),
      prompt: _id == 0 ? tr('pick.scanList') : tr('pick.scanItem'),
      busy: busy,
      onManual: manualEntry,
      actions: [
        if (_id != 0) ...[
          IconButton(onPressed: _undo.isEmpty ? null : _undoLast, icon: const Icon(Icons.undo), tooltip: tr('pick.undo')),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'reset' ? _resetProgress() : _changeList(),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'reset', child: Text(tr('pick.reset'))),
              PopupMenuItem(value: 'change', child: Text(tr('common.restart'))),
            ],
          ),
        ],
      ],
      children: [
        StatusCard(
          tone: _title.isEmpty ? Tone.info : _tone,
          title: _title.isEmpty ? tr('common.waitScan') : _title,
          subtitle: _title.isEmpty ? tr('pick.scanList') : _sub,
        ),
        if (_id != 0) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('pick.progress', {'a': picked, 'b': total}), style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: total == 0 ? 0 : picked / total, minHeight: 8),
              const SizedBox(height: 4),
              Text(tr('pick.localOnly'), style: const TextStyle(fontSize: 11.5, color: Color(0xFF777777))),
            ]),
          ),
          if (next != null)
            Container(
              margin: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFF2E7D32), borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('pick.next'), style: const TextStyle(color: Colors.white70)),
                Text(next.location.isEmpty ? '—' : next.location,
                    style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
                Text('${next.sku}  ×${next.qty - next.picked}',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                if (next.batch.isNotEmpty) Text('${tr('common.batch')}: ${next.batch}', style: const TextStyle(color: Colors.white)),
                if (next.name.isNotEmpty)
                  Text(next.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
              ]),
            ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Column(children: [
              for (final l in _lines)
                ListTile(
                  dense: true,
                  leading: Icon(l.done ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: l.done ? const Color(0xFF2E7D32) : Colors.grey),
                  title: Text('${l.location.isEmpty ? '—' : l.location}   ${l.sku}',
                      style: TextStyle(
                        fontWeight: identical(l, next) ? FontWeight.bold : FontWeight.normal,
                        decoration: l.done ? TextDecoration.lineThrough : null,
                      )),
                  subtitle: Text([if (l.batch.isNotEmpty) l.batch, l.name].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text('${l.picked}/${l.qty}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
            ]),
          ),
        ],
      ],
    );
  }
}
