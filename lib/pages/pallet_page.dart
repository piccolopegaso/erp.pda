import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/history.dart';
import '../core/i18n.dart';
import '../ui/el.dart';
import '../ui/widgets.dart';

class _Pending {
  _Pending(this.trackingNo, {this.error = ''});

  final String trackingNo;
  String error;

  Map<String, dynamic> toJson() => {'t': trackingNo, 'e': error};

  static _Pending fromJson(Map j) => _Pending('${j['t'] ?? ''}', error: '${j['e'] ?? ''}');
}

/// Pallet loading / carrier handover (web: views/wms/palletHandover.vue).
///
/// Weak-network design:
///  - every scanned tracking number goes into a queue persisted on the device (per pallet)
///  - the queue is submitted one number at a time (same as the web's flush loop)
///  - a business error pauses the queue until the operator retries or removes the number
///  - a network error keeps everything queued; it resumes automatically when the network is back
///  - after an *unknown* outcome the server list is re-read first, so nothing is submitted twice
class PalletPage extends StatefulWidget {
  const PalletPage({super.key});

  @override
  State<PalletPage> createState() => _PalletPageState();
}

class _PalletPageState extends State<PalletPage> with ScanPageMixin {
  @override
  String get moduleName => 'mod.pallet';

  Map<String, dynamic>? _pallet;
  List<Map<String, dynamic>> _serverRows = [];
  List<_Pending> _queue = [];
  bool _flushing = false;
  bool _paused = false;
  bool _needsReconcile = false;
  ElType _tone = ElType.info;
  String _title = '';
  String _sub = '';
  StreamSubscription<void>? _netSub;
  Timer? _retryTimer;
  Timer? _refreshTimer;

  String get _code => asStr(_pallet?['palletCode']);

  static const _queuePrefix = 'pltq:';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _netSub = app.net.onRecovered.listen((_) => _flush());
      setState(() {});
    });
  }

  @override
  void dispose() {
    _netSub?.cancel();
    _retryTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  // ---------------- persistence ----------------

  void _saveQueue() {
    if (_code.isEmpty) return;
    app.settings.writeJson('$_queuePrefix$_code', _queue.isEmpty ? null : _queue.map((e) => e.toJson()).toList());
  }

  List<_Pending> _loadQueue(String code) {
    final raw = app.settings.readJson<List>('$_queuePrefix$code') ?? const [];
    return raw.whereType<Map>().map(_Pending.fromJson).where((p) => p.trackingNo.isNotEmpty).toList();
  }

  /// Pallets that still have unsent scans on this device.
  Map<String, int> _palletsWithQueue() {
    final out = <String, int>{};
    for (final k in app.settings.prefs.getKeys()) {
      if (!k.startsWith('json:$_queuePrefix')) continue;
      final code = k.substring('json:$_queuePrefix'.length);
      final n = _loadQueue(code).length;
      if (n > 0) out[code] = n;
    }
    return out;
  }

  // ---------------- scanning ----------------

  @override
  Future<void> onScan(String code) async {
    if (_pallet == null) {
      await _loadPallet(code);
      return;
    }
    if (code.toUpperCase() == _code.toUpperCase()) {
      await _refreshServer();
      app.device.ok();
      _show(ElType.success, '${tr('wms.palletCurrentLoading')}: $_code', tr('pda.plt.loaded', {'n': _serverRows.length}));
      return;
    }
    _enqueue(code);
  }

  Future<void> _loadPallet(String scan) async {
    try {
      final data = await app.api.command('POST', '/v0/wms/pallets/handover/scan', data: {'scan': scan});
      final row = data is Map ? data['pallet'] : null;
      if (row is! Map) {
        app.device.error();
        _show(ElType.danger, tr('wms.palletLoadNotFound', {'value': scan}));
        log(scan, Outcome.error, 'pallet not found');
        return;
      }
      _pallet = Map<String, dynamic>.from(row);
      _queue = _loadQueue(_code);
      _paused = _queue.any((p) => p.error.isNotEmpty);
      _needsReconcile = _queue.isNotEmpty;
      await _refreshServer();
      app.device.ok();
      _show(ElType.success, '${tr('wms.palletCurrentLoading')}: $_code',
          data['ambiguous'] == true ? tr('wms.palletPlateLoadAmbiguous', {'code': _code}) : tr('wms.palletScanTracking'));
      log(scan, Outcome.ok, _code);
      final note = asStr(_pallet!['importantNote']);
      if (note.isNotEmpty && mounted) {
        app.device.warn();
        // not awaited: the scan handler must finish; scans are ignored while the dialog is on top
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('wms.palletImportantNote')),
            content: Text(note, style: const TextStyle(fontSize: 17)),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('common.confirmButtonText')))],
          ),
        );
      }
      _flush();
    } catch (e) {
      app.device.error();
      _show(e is ApiException && e.kind == FailKind.unknown ? ElType.warning : ElType.danger, errorText(e), scan);
      log(scan, outcomeOf(e), errorText(e));
    }
  }

  String _trackingOf(Map r) {
    final direct = asStr(r['trackingNo']);
    if (direct.isNotEmpty) return direct;
    return asStr(_meta(r)['rawScan']);
  }

  Map _meta(Map r) {
    final m = r['meta'];
    if (m is Map) return m;
    if (m is String && m.isNotEmpty) {
      try {
        final d = jsonDecode(m);
        if (d is Map) return d;
      } catch (_) {}
    }
    return const {};
  }

  void _enqueue(String raw) {
    final parts = raw.split(RegExp(r'[\s,;]+')).map((e) => e.trim()).where((e) => e.isNotEmpty);
    var added = 0, dupPending = 0, dupServer = 0;
    for (final t in parts) {
      if (_queue.any((p) => p.trackingNo == t)) {
        dupPending++;
      } else if (_serverRows.any((r) => _trackingOf(r) == t)) {
        dupServer++;
      } else {
        _queue.add(_Pending(t));
        added++;
        log(t, Outcome.queued, _code);
      }
    }
    if (added > 0) {
      _saveQueue();
      if (_paused) {
        app.device.warn();
        _show(ElType.warning, tr('pda.plt.queued', {'code': raw}), tr('wms.palletScanQueueInterrupted'));
      } else {
        app.device.ok();
        _show(ElType.success, tr('pda.plt.queued', {'code': raw}), tr('pda.plt.pending', {'n': _queue.length}));
      }
      _flush();
    } else if (dupPending > 0) {
      app.device.error();
      _show(ElType.warning, tr('wms.palletDupPending'), raw);
    } else if (dupServer > 0) {
      app.device.error();
      _show(ElType.warning, tr('wms.palletDupServer'), raw);
    }
  }

  // ---------------- queue flushing ----------------

  Future<void> _flush({bool manual = false}) async {
    if (_flushing || _pallet == null || _queue.isEmpty) return;
    if (_paused && !manual) return;
    final code = _code;
    _retryTimer?.cancel();
    setState(() {
      _flushing = true;
      _paused = false;
    });
    try {
      if (_needsReconcile) {
        await _refreshServer();
        final onServer = _serverRows.map(_trackingOf).toSet();
        _queue.removeWhere((p) => onServer.contains(p.trackingNo));
        _saveQueue();
        _needsReconcile = false;
      }
      while (_queue.isNotEmpty && mounted && _code == code) {
        final head = _queue.first;
        try {
          await app.api.command('POST', '/v0/wms/pallets/${Uri.encodeComponent(code)}/tracking/flush', data: {
            'reason': 'scan',
            'items': [
              {'trackingNo': head.trackingNo, 'carrier': '', 'trackingNoNorm': ''}
            ],
          });
          _queue.removeAt(0);
          _saveQueue();
          log(head.trackingNo, Outcome.ok, code);
          if (mounted) setState(() {});
          _scheduleRefresh();
        } on ApiException catch (e) {
          if (e.kind == FailKind.business || e.kind == FailKind.server) {
            head.error = errorText(e);
            _saveQueue();
            _paused = true;
            app.device.error();
            log(head.trackingNo, Outcome.error, head.error);
            _show(ElType.danger, tr('pda.plt.flushError', {'msg': head.error}), head.trackingNo);
            return;
          }
          // network or session problem: keep everything queued
          if (e.kind == FailKind.unknown) _needsReconcile = true;
          app.device.warn();
          log(head.trackingNo, Outcome.queued, errorText(e));
          _show(ElType.warning, tr('pda.plt.offlineQueued'), tr('pda.plt.pending', {'n': _queue.length}));
          _retryTimer = Timer(const Duration(seconds: 15), _flush);
          return;
        }
      }
      if (_queue.isEmpty) {
        await _refreshServer();
        _show(ElType.success, tr('pda.plt.loaded', {'n': _serverRows.length}), code);
      }
    } finally {
      if (mounted) setState(() => _flushing = false);
    }
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(seconds: 1), _refreshServer);
  }

  Future<void> _refreshServer() async {
    if (_pallet == null) return;
    try {
      final data = await app.api.query('/v0/wms/pallets/${Uri.encodeComponent(_code)}/tracking');
      if (data is List && mounted) {
        setState(() => _serverRows = data.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList());
      }
    } catch (_) {}
  }

  Future<void> _removePending(_Pending p) async {
    if (!await confirm(context, tr('pda.plt.removePending', {'code': p.trackingNo}))) return;
    setState(() {
      _queue.remove(p);
      _paused = _queue.any((q) => q.error.isNotEmpty);
    });
    _saveQueue();
    _flush();
  }

  Future<void> _removeServer(Map r) async {
    final t = _trackingOf(r);
    if (t.isEmpty || !await confirm(context, tr('pda.plt.removeConfirm', {'code': t}))) return;
    try {
      await app.api.command('POST', '/v0/wms/pallets/${Uri.encodeComponent(_code)}/tracking/remove', data: {'trackingNo': t});
      log(t, Outcome.ok, 'removed from $_code');
      await _refreshServer();
    } catch (e) {
      app.device.error();
      if (mounted) toast(context, errorText(e), type: ElType.danger);
    }
  }

  Future<void> _closePallet() async {
    if (_queue.isNotEmpty && !await confirm(context, tr('pda.plt.switchConfirm', {'n': _queue.length}))) return;
    _retryTimer?.cancel();
    setState(() {
      _pallet = null;
      _serverRows = [];
      _queue = [];
      _paused = false;
      _title = '';
      _sub = '';
    });
  }

  void _show(ElType t, String title, [String sub = '']) {
    if (!mounted) return;
    setState(() {
      _tone = t;
      _title = title;
      _sub = sub;
    });
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final p = _pallet;
    return ScanScaffold(
      title: tr('wms.palletHandover'),
      placeholder: p == null ? tr('wms.palletLoadScanPh') : tr('wms.palletScanTracking'),
      busy: busy,
      onManual: manualEntry,
      actions: [
        if (p != null) IconButton(onPressed: _closePallet, icon: const Icon(Icons.logout), tooltip: tr('wms.palletClearSession')),
      ],
      children: p == null ? _landing() : _loaded(p),
    );
  }

  List<Widget> _landing() {
    final waiting = _palletsWithQueue();
    return [
      _title.isEmpty
          ? ElResult(type: ElType.info, title: tr('wms.palletLoadResultTitle'), subTitle: tr('wms.palletLoadResultSub'))
          : ElResult(type: _tone, title: _title, subTitle: _sub),
      if (waiting.isNotEmpty)
        ElCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final e in waiting.entries)
              ListTile(
                leading: const Icon(Icons.cloud_upload, color: Color(0xFFEF6C00)),
                title: Text(e.key),
                subtitle: Text(tr('pda.plt.pending', {'n': e.value})),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy ? null : () => _loadPallet(e.key),
              ),
          ]),
        ),
    ];
  }

  List<Widget> _loaded(Map<String, dynamic> p) {
    final unit = asStr(p['unitStr']);
    final unitText = unit == 'Box' ? tr('wms.palletUnitBox') : (unit == 'Pallet' ? tr('wms.palletUnitPallet') : unit);
    return [
      ElCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('wms.palletCurrentLoading'), style: const TextStyle(color: El.textSecondary, fontSize: 13)),
          Text(_code, style: const TextStyle(color: El.textPrimary, fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            ElTag(tr('pda.plt.loaded', {'n': _serverRows.length}), type: ElType.success),
            if (_queue.isNotEmpty) ElTag(tr('pda.plt.pending', {'n': _queue.length}), type: ElType.warning),
            if (unitText.isNotEmpty) ElTag(unitText, type: ElType.info),
            if (asStr(p['pickupCarrier']).isNotEmpty) ElTag(asStr(p['pickupCarrier']), type: ElType.info),
            if (asStr(p['plateNumber2']).isNotEmpty) ElTag('${tr('wms.palletPlateNumber2')}: ${asStr(p['plateNumber2'])}', type: ElType.info),
            if (asStr(p['pickupDate']).isNotEmpty) ElTag('${tr('wms.palletPickupDate')}: ${asStr(p['pickupDate'])}', type: ElType.info),
          ]),
        ]),
      ),
      if (_title.isNotEmpty) ElAlert(type: _tone, title: _title, description: _sub),
      if (asStr(p['importantNote']).isNotEmpty)
        ElAlert(type: ElType.warning, title: tr('wms.palletImportantNote'), description: asStr(p['importantNote'])),
      if (_queue.isNotEmpty)
        ElCard(
          padding: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text('${tr('wms.palletPendingList')} (${_queue.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: FilledButton.icon(
                style: elButton(ElType.warning, plain: true),
                onPressed: _flushing ? null : () => _flush(manual: true),
                icon: _flushing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 18),
                label: Text(tr('wms.palletRetryPendingScans')),
              ),
            ),
            if (_paused)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(tr('wms.palletScanQueueInterrupted'), style: const TextStyle(color: El.danger)),
              ),
            for (final q in _queue)
              ListTile(
                dense: true,
                leading: Icon(q.error.isEmpty ? Icons.schedule : Icons.error, color: q.error.isEmpty ? Colors.orange : Colors.red),
                title: Text(q.trackingNo),
                subtitle: q.error.isEmpty ? null : Text(q.error, style: const TextStyle(color: El.danger)),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _removePending(q)),
              ),
          ]),
        ),
      ElCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
            child: Row(children: [
              Expanded(
                child: Text('${tr('wms.palletServerList')} (${_serverRows.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              IconButton(onPressed: _refreshServer, icon: const Icon(Icons.refresh)),
            ]),
          ),
          if (_serverRows.isEmpty)
            Padding(padding: const EdgeInsets.all(12), child: Text(tr('wms.palletNoTrackingYet'))),
          for (final r in _serverRows.reversed) _serverTile(r),
        ]),
      ),
    ];
  }

  Widget _serverTile(Map<String, dynamic> r) {
    final meta = _meta(r);
    var st = asStr(meta['resolveStatus']);
    if (st.isEmpty) st = asStr(r['outboundUNID']).isNotEmpty ? 'resolved' : 'unknown';
    final color = switch (st) {
      'resolved' => El.success,
      'pending' => El.warning,
      'error' => El.danger,
      _ => El.info,
    };
    final err = asStr(meta['resolveError']);
    return ListTile(
      dense: true,
      title: Text(_trackingOf(r), style: const TextStyle(fontSize: 15)),
      subtitle: Text([
        asStr(r['outboundUNID']),
        asStr(r['carrier']),
        _resolveText(st),
        if (err.isNotEmpty) err,
      ].where((s) => s.isNotEmpty).join(' · '), style: TextStyle(color: color)),
      trailing: IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => _removeServer(r)),
    );
  }

  String _resolveText(String st) => switch (st) {
        'resolved' => tr('wms.palletResolveResolved'),
        'pending' => tr('wms.palletResolvePending'),
        'not_found' => tr('wms.palletResolveNotFound'),
        'error' => tr('wms.palletResolveError'),
        _ => tr('wms.palletResolveUnknown'),
      };

}
