import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/history.dart';
import '../core/i18n.dart';
import '../ui/widgets.dart';
import '../ui/el.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  Outcome? _filter;

  static const _colors = {
    Outcome.ok: El.success,
    Outcome.warn: El.warning,
    Outcome.error: El.danger,
    Outcome.unknown: Color(0xFF6A1B9A),
    Outcome.queued: El.primary,
  };

  @override
  Widget build(BuildContext context) {
    final h = AppScope.of(context).history;
    return ListenableBuilder(
      listenable: h,
      builder: (context, _) {
        final list = _filter == null ? h.entries : h.entries.where((e) => e.outcome == _filter).toList();
        return Scaffold(
          appBar: elAppBar(tr('pda.history'), actions: [
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: () async {
                if (await confirm(context, tr('pda.his.clearConfirm'))) h.clear();
              },
            ),
          ]),
          body: Column(children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                _chip(null, tr('pda.total', {'n': h.entries.length})),
                for (final o in Outcome.values) _chip(o, _label(o)),
              ]),
            ),
            Expanded(
              child: list.isEmpty
                  ? Center(child: Text(tr('pda.his.empty')))
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = list[i];
                        return ListTile(
                          dense: true,
                          leading: Icon(Icons.circle, size: 14, color: _colors[e.outcome]),
                          title: Text(e.code, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          subtitle: Text('${tr(e.module)} · ${_label(e.outcome)}${e.message.isEmpty ? '' : '\n${e.message}'}'),
                          trailing: Text(fmtTime(e.time.toIso8601String()).split(' ').last),
                        );
                      },
                    ),
            ),
          ]),
        );
      },
    );
  }

  static String _label(Outcome o) => switch (o) {
        Outcome.ok => tr('pda.his.ok'),
        Outcome.warn => tr('pda.his.warn'),
        Outcome.error => tr('pda.his.error'),
        Outcome.unknown => tr('pda.his.unknown'),
        Outcome.queued => tr('pda.his.queued'),
      };

  Widget _chip(Outcome? o, String label) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: _filter == o,
          onSelected: (_) => setState(() => _filter = o),
        ),
      );
}
