import 'package:flutter/foundation.dart';

import 'settings.dart';

enum Outcome { ok, warn, error, unknown, queued }

class HistoryEntry {
  HistoryEntry({
    required this.time,
    required this.module,
    required this.code,
    required this.outcome,
    this.message = '',
  });

  final DateTime time;
  final String module;
  final String code;
  final Outcome outcome;
  final String message;

  Map<String, dynamic> toJson() => {
        't': time.millisecondsSinceEpoch,
        'm': module,
        'c': code,
        'o': outcome.name,
        'x': message,
      };

  static HistoryEntry fromJson(Map j) => HistoryEntry(
        time: DateTime.fromMillisecondsSinceEpoch((j['t'] ?? 0) as int),
        module: '${j['m'] ?? ''}',
        code: '${j['c'] ?? ''}',
        outcome: Outcome.values.firstWhere((o) => o.name == j['o'], orElse: () => Outcome.unknown),
        message: '${j['x'] ?? ''}',
      );
}

/// Local, per-device log of every scan and its result.
/// On weak Wi-Fi this is how an operator checks what really went through.
class ScanHistory extends ChangeNotifier {
  ScanHistory(this.settings) {
    final raw = settings.readJson<List>('history') ?? const [];
    entries = raw.whereType<Map>().map(HistoryEntry.fromJson).toList();
  }

  static const int maxEntries = 500;

  final AppSettings settings;
  late List<HistoryEntry> entries;

  void add(String module, String code, Outcome outcome, [String message = '']) {
    entries.insert(
      0,
      HistoryEntry(time: DateTime.now(), module: module, code: code, outcome: outcome, message: message),
    );
    if (entries.length > maxEntries) entries.removeRange(maxEntries, entries.length);
    settings.writeJson('history', entries.map((e) => e.toJson()).toList());
    notifyListeners();
  }

  void clear() {
    entries.clear();
    settings.writeJson('history', null);
    notifyListeners();
  }
}
