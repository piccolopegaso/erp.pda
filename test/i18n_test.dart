import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mic_pda/core/history.dart';
import 'package:mic_pda/core/i18n.dart';

void main() {
  test('every translation has zh, en and de', () {
    for (final e in translationTable.entries) {
      for (final lang in supportedLanguages.keys) {
        expect(e.value[lang], isNotNull, reason: '${e.key} is missing "$lang"');
        expect(e.value[lang]!.trim(), isNotEmpty, reason: '${e.key} has empty "$lang"');
      }
    }
  });

  test('every literal tr() key used in lib/ exists', () {
    final re = RegExp(r"""(?<![A-Za-z0-9_])tr\(\s*'([a-zA-Z0-9_.]+)'""");
    final missing = <String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('i18n.dart')) continue;
      for (final m in re.allMatches(f.readAsStringSync())) {
        if (!translationTable.containsKey(m.group(1))) missing.add('${m.group(1)} (${f.path})');
      }
    }
    expect(missing, isEmpty);
  });

  test('dynamic keys exist', () {
    for (final o in Outcome.values) {
      expect(translationTable.containsKey('his.${o.name}'), isTrue, reason: 'his.${o.name}');
    }
    for (final m in ['shipping', 'pallet', 'pick', 'logging', 'receiving', 'snswap', 'stock', 'history', 'settings']) {
      expect(translationTable.containsKey('mod.$m'), isTrue);
      expect(translationTable.containsKey('mod.$m.desc'), isTrue);
    }
    for (final s in ['resolved', 'pending', 'not_found', 'error', 'unknown']) {
      expect(translationTable.containsKey('plt.resolve.$s'), isTrue);
    }
  });

  test('placeholders are substituted', () {
    setLanguage('en');
    expect(tr('pick.progress', {'a': 2, 'b': 5}), 'Picked 2/5');
    setLanguage('zh');
    expect(tr('pick.progress', {'a': 2, 'b': 5}), '已拣 2/5');
  });
}
