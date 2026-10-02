import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mic_pda/core/i18n.dart';

void main() {
  test('every translation has en, zh and de', () {
    for (final e in translationTable.entries) {
      for (final lang in supportedLanguages.keys) {
        expect(e.value[lang], isNotNull, reason: '${e.key} is missing "$lang"');
        expect(e.value[lang]!.trim(), isNotEmpty, reason: '${e.key} has empty "$lang"');
      }
    }
  });

  test('every literal tr() key used in lib/ exists (run tool/sync_web_locale.py after adding web keys)', () {
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

  test('keys built at runtime exist', () {
    for (final k in [
      'pda.net.offline',
      'pda.net.slow',
      'pda.pickScanBatch',
      'pda.packScanOrder',
      'wms.picklist',
      'wms.shippingScan',
      'wms.loggingScan',
      'wms.snScan',
      'wms.palletHandover',
      'wms.inventory',
      'common.rma',
      'common.inbound',
    ]) {
      expect(translationTable.containsKey(k), isTrue, reason: k);
    }
  });

  test('English is the default and web wording is used', () {
    setLanguage('xx');
    expect(currentLanguage, 'en');
    expect(tr('wms.picklist'), 'Picklist');
    expect(tr('wms.palletHandover'), 'Loading Scan');
    setLanguage('zh');
    expect(tr('wms.picklist'), '拣料操作');
    expect(tr('pda.total', {'n': 3}), '共 3 条');
    setLanguage('en');
  });
}
