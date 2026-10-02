import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/device.dart';
import '../core/history.dart';
import '../core/i18n.dart';
import '../ui/widgets.dart';

/// Return receiving (web: views/warehouse/receivingScan.vue, API /v0/r7greceiving/scan).
///
/// 1. scan the return / shipment number twice (confirmation, like the web's requiredScans=2)
/// 2. scan each returned item - every scan adds 1 to the item's quantity on the server
class ReceivingScanPage extends StatefulWidget {
  const ReceivingScanPage({super.key});

  @override
  State<ReceivingScanPage> createState() => _ReceivingScanPageState();
}

class _ReceivingScanPageState extends State<ReceivingScanPage> with ScanPageMixin {
  @override
  String get moduleName => 'mod.receiving';

  Map<String, dynamic> _rec = {};
  String _pendingConfirm = '';
  Tone _tone = Tone.info;
  String _title = '';
  String _sub = '';
  List<MapEntry<String, int>> _businessTypes = [];
  int _businessType = 2;

  int get _id => asInt(_rec['id']);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBusinessTypes());
  }

  Future<void> _loadBusinessTypes() async {
    final cached = app.settings.readJson<Map>('rmaBusinessType');
    if (cached != null) _setTypes(cached);
    try {
      final data = await app.api.query('/v0/settings/config', params: {'q': 'map:rma:businessType'});
      if (data is Map) {
        await app.settings.writeJson('rmaBusinessType', data);
        _setTypes(data);
      }
    } catch (_) {}
  }

  void _setTypes(Map m) {
    if (!mounted) return;
    setState(() => _businessTypes = [for (final e in m.entries) MapEntry('${e.key}', asInt(e.value))]);
  }

  @override
  Future<void> onScan(String code) async {
    if (_id == 0) {
      // first scan must be confirmed by scanning the same code again
      if (_pendingConfirm.isEmpty) {
        app.device.ok();
        setState(() {
          _pendingConfirm = code;
          _tone = Tone.info;
          _title = tr('rcv.scanAgain', {'code': code});
          _sub = '';
        });
        return;
      }
      if (_pendingConfirm != code) {
        app.device.feedback(Beep.double);
        setState(() {
          _pendingConfirm = '';
          _tone = Tone.error;
          _title = tr('rcv.mismatch');
          _sub = code;
        });
        return;
      }
      _pendingConfirm = '';
    }
    await _submit(code);
  }

  Future<void> _submit(String code) async {
    final firstScan = _id == 0;
    try {
      final data = await app.api.command('GET', '/v0/r7greceiving/scan',
          params: {'id': _id, 'q': code, 'businessType': _businessType});
      if (data is! Map || asInt(data['id']) == 0) {
        app.device.error();
        _show(Tone.error, tr('common.notFound', {'code': code}));
        log(code, Outcome.error, 'not found');
        return;
      }
      _rec = Map<String, dynamic>.from(data);
      app.device.ok();
      if (firstScan) {
        _show(Tone.ok, app.session.customerName(asStr(_rec['agentGUID'])), tr('rcv.confirmInfo'));
      } else {
        _show(Tone.ok, tr('rcv.gotItem', {'code': code}));
      }
      log(code, Outcome.ok, firstScan ? asStr(_rec['originSN']) : 'item');
    } catch (e) {
      app.device.error();
      final unknown = e is ApiException && e.kind == FailKind.unknown;
      _show(unknown ? Tone.unknown : Tone.error, errorText(e), code);
      log(code, outcomeOf(e), errorText(e));
      if (unknown && !firstScan) await _reload();
    }
  }

  /// Re-read the receiving record so the operator sees whether the item was counted.
  Future<void> _reload() async {
    try {
      final data = await app.api.query('/v0/r7greceiving/', params: {'q': _id});
      if (data is Map && asInt(data['id']) != 0) {
        setState(() {
          _rec = Map<String, dynamic>.from(data);
          _sub = '${_sub.isEmpty ? '' : '$_sub\n'}${tr('err.unknownCheck')}';
        });
      }
    } catch (_) {}
  }

  void _show(Tone t, String title, [String sub = '']) => setState(() {
        _tone = t;
        _title = title;
        _sub = sub;
      });

  void _next() => setState(() {
        _rec = {};
        _pendingConfirm = '';
        _tone = Tone.info;
        _title = '';
        _sub = '';
      });

  @override
  Widget build(BuildContext context) {
    final items = jsonList(_rec['items']);
    final dispose = asStr(_rec['dispose']);
    return ScanScaffold(
      title: tr('mod.receiving'),
      prompt: _id == 0 ? tr('rcv.scanReturn') : tr('rcv.scanItem'),
      busy: busy,
      onManual: manualEntry,
      bottom: _id == 0
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: busy ? null : _next,
                  icon: const Icon(Icons.skip_next),
                  label: Text(tr('rcv.nextPacket'), style: const TextStyle(fontSize: 17)),
                ),
              ),
            ),
      children: [
        StatusCard(
          tone: _title.isEmpty ? Tone.info : _tone,
          title: _title.isEmpty ? tr('common.waitScan') : _title,
          subtitle: _title.isEmpty ? tr('rcv.scanReturn') : _sub,
        ),
        if (_id == 0 && _businessTypes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(children: [
              Text('${tr('rcv.businessType')}: '),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: _businessTypes.any((e) => e.value == _businessType) ? _businessType : null,
                  items: [for (final e in _businessTypes) DropdownMenuItem(value: e.value, child: Text(e.key))],
                  onChanged: (v) => setState(() => _businessType = v ?? _businessType),
                ),
              ),
            ]),
          ),
        if (dispose.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            padding: const EdgeInsets.all(12),
            color: dispose == 'REPAIR' ? const Color(0xFF1565C0) : const Color(0xFF2E7D32),
            child: Row(children: [
              Icon(dispose == 'REPAIR' ? Icons.build : Icons.inventory, color: Colors.white, size: 30),
              const SizedBox(width: 12),
              Text('${tr('rcv.dispose')}: $dispose',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2)),
            ]),
          ),
        if (_rec.isNotEmpty) ...[
          InfoSection(rows: [
            (tr('common.customer'), app.session.customerName(asStr(_rec['agentGUID']))),
            (tr('common.trackingNo'), asStr(_rec['shipSN'])),
            (tr('common.refNo'), asStr(_rec['originSN'])),
            (tr('common.country'), asStr(_rec['originCountry'])),
            (tr('rcv.firstScanned'), fmtTime(_rec['createdAt'])),
            (tr('rcv.origItems'), asStr(_rec['itemStrOrigin'])),
          ]),
          InfoSection(
            title: tr('common.items'),
            rows: items.isEmpty
                ? [(tr('common.empty'), '—')]
                : [for (final it in items) (asStr(it['itemId'] ?? it['sku']), '× ${asStr(it['qty'])}')],
          ),
        ],
      ],
    );
  }
}
