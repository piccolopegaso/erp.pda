import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/history.dart';
import '../../core/i18n.dart';
import '../../ui/el.dart';
import '../../ui/widgets.dart';
import 'rma_service.dart';

/// Inbound an RMA: every line gets a location (scan the compartment), then
/// POST /v0/r7greceiving/inbound books the stock (status by item condition) and
/// sets the RMA to "Inbounded". Returns true when done.
class RmaInboundPage extends StatefulWidget {
  const RmaInboundPage({super.key, required this.record});

  final Map<String, dynamic> record;

  @override
  State<RmaInboundPage> createState() => _RmaInboundPageState();
}

class _RmaInboundPageState extends State<RmaInboundPage> with ScanPageMixin {
  @override
  String get moduleName => 'common.inbound';

  late final RmaService svc = RmaService(app);
  late final List<Map<String, dynamic>> lines = [for (final i in jsonList(widget.record['items'])) Map<String, dynamic>.from(i)];

  /// selected line: the next location scan goes to this line only
  int? selected;
  String notice = '';
  ElType noticeType = ElType.info;
  bool submitting = false;

  int get id => asInt(widget.record['id']);

  bool get complete => lines.isNotEmpty && lines.every((l) => asStr(l['compartmentGUID']).isNotEmpty);

  @override
  Future<void> onScan(String code) async {
    Map<String, dynamic>? loc;
    try {
      final d = await app.api.query('/v0/compartment/any', params: {'q': code});
      if (d is Map && asStr(d['guid']).isNotEmpty) loc = Map<String, dynamic>.from(d);
    } on ApiException catch (e) {
      if (e.kind != FailKind.business) {
        app.device.error();
        _notice(errorText(e), ElType.danger);
        return;
      }
    }
    if (loc == null) {
      app.device.error();
      _notice('${tr('common.location')}: ${tr('pda.notFound', {'code': code})}', ElType.danger);
      log(code, Outcome.error, 'location not found');
      return;
    }
    final name = '${asStr(loc['warehouseUNID'])} » ${asStr(loc['name'])}';
    setState(() {
      if (selected != null) {
        lines[selected!]['compartmentGUID'] = asStr(loc!['guid']);
        lines[selected!]['location'] = name;
        selected = null;
      } else {
        for (final l in lines) {
          if (asStr(l['compartmentGUID']).isEmpty) {
            l['compartmentGUID'] = asStr(loc!['guid']);
            l['location'] = name;
          }
        }
      }
    });
    app.device.ok();
    _notice(name, ElType.success);
    log(code, Outcome.ok, name);
  }

  void _notice(String m, ElType t) => setState(() {
        notice = m;
        noticeType = t;
      });

  Future<void> _submit() async {
    if (!complete) {
      _notice(tr('pda.rma.locationRequired'), ElType.warning);
      return;
    }
    if (!await confirm(context, tr('pda.rma.inboundConfirm', {'n': lines.fold<int>(0, (a, l) => a + asInt(l['qty']))}), title: tr('common.inbound'))) return;
    setState(() => submitting = true);
    try {
      await svc.inbound(id, lines);
      app.device.ok();
      log(asStr(widget.record['shipSN']), Outcome.ok, tr('wms.taskInbounded'));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (isUnknown(e)) {
        // never resend an inbound blindly: check whether it went through
        try {
          final r = await svc.one(id);
          if (asInt(r['status']) >= 100) {
            log(asStr(widget.record['shipSN']), Outcome.ok, tr('wms.taskInbounded'));
            if (mounted) Navigator.of(context).pop(true);
            return;
          }
        } catch (_) {}
      }
      app.device.error();
      log(asStr(widget.record['shipSN']), outcomeOf(e), errorText(e));
      _notice(errorText(e), ElType.danger);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScanScaffold(
      title: '${tr('common.inbound')} · ${asStr(widget.record['shipSN'])}',
      placeholder: selected == null ? tr('pda.rma.scanLocationAll') : tr('pda.rma.scanLocationOne', {'sku': asStr(lines[selected!]['itemId'])}),
      busy: busy || submitting,
      onManual: manualEntry,
      bottom: ElBottomBar(children: [
        FilledButton.icon(
          style: elButton(ElType.success),
          onPressed: submitting || !complete ? null : _submit,
          icon: const Icon(Icons.check_box_outlined, size: 18),
          label: Text(tr('common.inbound')),
        ),
      ]),
      children: [
        if (notice.isNotEmpty) ElAlert(type: noticeType, title: notice),
        ElAlert(type: ElType.info, title: tr('pda.rma.inboundHint')),
        for (var i = 0; i < lines.length; i++)
          ElCard(
            highlight: selected == i ? El.primary : null,
            onTap: () => setState(() => selected = selected == i ? null : i),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${asStr(lines[i]['itemId'])}${asStr(lines[i]['itemBatch']).isNotEmpty ? ' (${asStr(lines[i]['itemBatch'])})' : ''}  × ${asInt(lines[i]['qty'])}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Row(children: [
                    ElTag(rmaItemValid[asInt(lines[i]['valid'])] ?? '${lines[i]['valid']}',
                        type: asInt(lines[i]['valid']) == 1 ? ElType.success : ElType.danger),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        asStr(lines[i]['location']).isEmpty ? '${tr('common.location')}: —' : asStr(lines[i]['location']),
                        style: TextStyle(color: asStr(lines[i]['compartmentGUID']).isEmpty ? El.danger : El.primary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                ]),
              ),
              Icon(selected == i ? Icons.radio_button_checked : Icons.radio_button_off, color: selected == i ? El.primary : El.border),
            ]),
          ),
      ],
    );
  }
}
