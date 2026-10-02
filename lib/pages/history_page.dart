import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/history.dart';
import '../core/i18n.dart';
import '../ui/widgets.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  Outcome? _filter;

  static const _colors = {
    Outcome.ok: Color(0xFF2E7D32),
    Outcome.warn: Color(0xFFEF6C00),
    Outcome.error: Color(0xFFC62828),
    Outcome.unknown: Color(0xFF6A1B9A),
    Outcome.queued: Color(0xFF1565C0),
  };

  @override
  Widget build(BuildContext context) {
    final h = AppScope.of(context).history;
    return ListenableBuilder(
      listenable: h,
      builder: (context, _) {
        final list = _filter == null ? h.entries : h.entries.where((e) => e.outcome == _filter).toList();
        return Scaffold(
          appBar: AppBar(title: Text(tr('mod.history')), actions: [
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: () async {
                if (await confirm(context, tr('his.clearConfirm'))) h.clear();
              },
            ),
          ]),
          body: Column(children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                _chip(null, tr('common.total', {'n': h.entries.length})),
                for (final o in Outcome.values) _chip(o, tr('his.${o.name}')),
              ]),
            ),
            Expanded(
              child: list.isEmpty
                  ? Center(child: Text(tr('his.empty')))
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = list[i];
                        return ListTile(
                          dense: true,
                          leading: Icon(Icons.circle, size: 14, color: _colors[e.outcome]),
                          title: Text(e.code, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          subtitle: Text('${tr(e.module)} · ${tr('his.${e.outcome.name}')}${e.message.isEmpty ? '' : '\n${e.message}'}'),
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

  Widget _chip(Outcome? o, String label) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: _filter == o,
          onSelected: (_) => setState(() => _filter = o),
        ),
      );
}
