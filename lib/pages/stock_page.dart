import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/history.dart';
import '../core/i18n.dart';
import '../ui/el.dart';
import '../ui/widgets.dart';

enum _Kind { location, item, search }

/// Stock lookup: scan a location, an item barcode/SKU, or anything else.
/// Read-only (APIs /v0/compartment/any, /v0/item/any, /v0/inventory/list).
class StockPage extends StatefulWidget {
  const StockPage({super.key});

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> with ScanPageMixin {
  @override
  String get moduleName => 'wms.inventory';

  _Kind? _kind;
  String _query = '';
  Map<String, dynamic> _head = {};
  List<Map<String, dynamic>> _rows = [];
  int _total = 0;
  dynamic _next;
  bool _loadingMore = false;
  String _error = '';

  static const _epoch = '1970-01-01T00:00:00.000Z';

  @override
  Future<void> onScan(String code) async {
    setState(() {
      _error = '';
      _rows = [];
      _head = {};
      _kind = null;
      _total = 0;
      _next = null;
    });
    try {
      // 1. location?
      final loc = await _tryQuery('/v0/compartment/any', {'q': code});
      if (loc is Map && asStr(loc['guid']).isNotEmpty) {
        _kind = _Kind.location;
        _head = Map<String, dynamic>.from(loc);
        _query = asStr(loc['name']);
        await _loadRows(reset: true, extra: {'LocationGUID': asStr(loc['guid'])});
        app.device.ok();
        log(code, Outcome.ok, 'location');
        return;
      }
      // 2. item?
      final item = await _tryQuery('/v0/item/any', {'q': code});
      if (item is Map && asStr(item['unid']).isNotEmpty) {
        _kind = _Kind.item;
        _head = Map<String, dynamic>.from(item);
        _query = asStr(item['unid']);
        await _loadRows(reset: true);
        app.device.ok();
        log(code, Outcome.ok, 'item ${_head['unid']}');
        return;
      }
      // 3. free search (batch, partial SKU, ...)
      _kind = _Kind.search;
      _query = code;
      await _loadRows(reset: true);
      if (_rows.isEmpty) {
        app.device.error();
        _error = tr('pda.notFound', {'code': code});
        log(code, Outcome.warn, 'nothing found');
      } else {
        app.device.ok();
        log(code, Outcome.ok, 'search');
      }
    } catch (e) {
      app.device.error();
      _error = errorText(e);
      log(code, outcomeOf(e), _error);
    } finally {
      if (mounted) setState(() {});
    }
  }

  /// A lookup that answers "not found" with a business error is not an error for us.
  Future<dynamic> _tryQuery(String path, Map<String, dynamic> params) async {
    try {
      return await app.api.query(path, params: params);
    } on ApiException catch (e) {
      if (e.kind == FailKind.business) return null;
      rethrow;
    }
  }

  Map<String, dynamic> _extra = {};

  Future<void> _loadRows({bool reset = false, Map<String, dynamic>? extra}) async {
    if (reset) {
      _extra = extra ?? {};
      _next = null;
      _rows = [];
    }
    final data = await app.api.query('/v0/inventory/list', params: {
      'l': 100,
      'o': _next == null ? _epoch : '$_next',
      'q': _query,
      ..._extra,
    });
    if (data is Map) {
      var rows = (data['data'] as List? ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      if (_kind == _Kind.item) {
        // the list search is a LIKE: keep only the exact SKU
        rows = rows.where((r) => asStr(r['itemUnid']).toLowerCase() == _query.toLowerCase()).toList();
      }
      _rows.addAll(rows);
      _total = asInt(data['total']);
      final raw = (data['data'] as List? ?? const []);
      _next = raw.length >= 100 ? data['next'] : null;
    }
  }

  Future<void> _more() async {
    setState(() => _loadingMore = true);
    try {
      await _loadRows();
    } catch (e) {
      if (mounted) toast(context, errorText(e), type: ElType.danger);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  String _statusText(dynamic s) {
    final v = asInt(s);
    if (v <= 1) return 'Invalid';
    if (v == 2) return 'Damaged';
    if (v == 5) return 'Receiving';
    if (v == 10) return 'Valid';
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final sum = _rows.fold<int>(0, (a, r) => a + asInt(r['quantity']));
    final locked = _rows.fold<int>(0, (a, r) => a + asInt(r['lockedQty']));
    return ScanScaffold(
      title: tr('wms.inventory'),
      placeholder: tr('pda.stk.scan'),
      busy: busy,
      onManual: manualEntry,
      children: [
        if (_error.isNotEmpty) ElResult(type: ElType.danger, title: _error),
        if (_kind == null && _error.isEmpty) ElResult(type: ElType.info, title: tr('pda.stk.scan')),
        if (_kind == _Kind.location)
          ElAlert(
            type: ElType.success,
            title: '${tr('common.location')}: ${asStr(_head['name'])}',
            description: [
              asStr(_head['warehouseUNID']),
              if (asStr(_head['zoneCode']).isNotEmpty) 'Zone: ${asStr(_head['zoneCode'])}',
              '${tr('common.quantity')}: $sum',
            ].where((s) => s.isNotEmpty).join(' · '),
          ),
        if (_kind == _Kind.item) ...[
          ElAlert(type: ElType.success, title: '${tr('common.item')}: ${asStr(_head['unid'])}', description: asStr(_head['name'])),
          ElDescriptions(items: [
            (tr('common.customer'), app.session.customerName(asStr(_head['agentGUID']))),
            ('Barcode', asStr(_head['barcode'])),
            ('Weight', asStr(_head['weight']).isEmpty ? '' : '${asStr(_head['weight'])} kg'),
            (tr('common.quantity'), '$sum  (Locked: $locked)'),
          ]),
        ],
        if (_kind == _Kind.search) ElAlert(type: ElType.info, title: '${tr('common.search')}: $_query', description: '${tr('common.quantity')}: $sum'),
        if (_rows.isNotEmpty)
          ElCard(
            padding: EdgeInsets.zero,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Text('${tr('wms.inventory')} · ${tr('pda.total', {'n': _kind == _Kind.item ? _rows.length : _total})}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              for (final r in _rows) _row(r),
              if (_next != null)
                TextButton(
                  onPressed: _loadingMore ? null : _more,
                  child: _loadingMore
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(tr('pda.loadMore')),
                ),
            ]),
          ),
      ],
    );
  }

  Widget _row(Map<String, dynamic> r) {
    final showItem = _kind != _Kind.item;
    final showLoc = _kind != _Kind.location;
    final st = asInt(r['status']);
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEEEEE)))),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (showItem) Text(asStr(r['itemUnid']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            if (showItem && asStr(r['itemName']).isNotEmpty)
              Text(asStr(r['itemName']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            if (showLoc)
              Text('${asStr(r['warehouse'])} » ${asStr(r['compartment'])}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: El.primary)),
            Text(
              [
                if (asStr(r['itemBatch']).isNotEmpty) 'Batch: ${asStr(r['itemBatch'])}',
                _statusText(st),
                if (asStr(r['customer']).isNotEmpty) asStr(r['customer']),
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: st == 10 ? El.textSecondary : El.danger),
            ),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${asInt(r['quantity'])}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          if (asInt(r['lockedQty']) > 0)
            Text('Locked: ${asInt(r['lockedQty'])}', style: const TextStyle(fontSize: 11, color: Color(0xFFEF6C00))),
        ]),
      ]),
    );
  }
}
