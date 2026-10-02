import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mic_pda/pages/picklist/picklist_service.dart';

/// The label selection of Pick Scan Batch must behave exactly like the web
/// (packScanBatch.vue). The JS code is run with Node on the same random inputs.
void main() {
  final node = Process.runSync('which', ['node']).stdout.toString().trim();

  test('buildBatchPrintlist == packScanBatch.vue processItem (500 random picklists)', () {
    final rnd = Random(42);
    final skus = ['A', 'B', 'C'];
    final cases = <Map<String, dynamic>>[];
    for (var c = 0; c < 500; c++) {
      final orders = <Map<String, dynamic>>[];
      for (var o = 0; o < 1 + rnd.nextInt(6); o++) {
        final items = <Map<String, dynamic>>[];
        for (final s in skus) {
          if (rnd.nextBool()) items.add({'sku': s, 'qty': 1 + rnd.nextInt(3)});
        }
        final order = <String, dynamic>{'UNID': 'MO$c-$o', 'ID': c * 100 + o, 'items': items};
        if (rnd.nextInt(5) == 0 && items.isNotEmpty) {
          // some orders carry explicit itemPacks
          order['itemPacks'] = [
            {'sku': items.first['sku'], 'lblIdx': List.generate(items.first['qty'] as int, (i) => i + 10)}
          ];
        }
        orders.add(order);
      }
      final sku = skus[rnd.nextInt(3)];
      final total = orders.fold<int>(0, (a, o) {
        final packs = o['itemPacks'] as List?;
        final p = packs?.where((x) => x['sku'] == sku).toList() ?? const [];
        if (p.isNotEmpty) return a + (p.first['lblIdx'] as List).length;
        final it = (o['items'] as List).where((x) => x['sku'] == sku).toList();
        return a + (it.isEmpty ? 0 : it.first['qty'] as int);
      });
      if (total == 0) continue;
      final already = rnd.nextInt(total);
      final qty = 1 + rnd.nextInt(total - already);
      cases.add({'orders': orders, 'sku': sku, 'qty': qty, 'materials': ['BOX-S'], 'alreadyPrinted': already});
    }

    final p = Process.start(node, ['test/fixtures/pack_scan_batch_ref.js']);
    final result = p.then((proc) async {
      proc.stdin.write(jsonEncode(cases));
      await proc.stdin.close();
      return proc.stdout.transform(utf8.decoder).join();
    });
    return result.then((out) {
      final expected = jsonDecode(out) as List;
      for (var i = 0; i < cases.length; i++) {
        final c = cases[i];
        final got = buildBatchPrintlist(
          orders: (c['orders'] as List).cast<Map<String, dynamic>>(),
          sku: c['sku'] as String,
          alreadyPrinted: c['alreadyPrinted'] as int,
          qty: c['qty'] as int,
          materials: ['BOX-S'],
        );
        expect(jsonDecode(jsonEncode(got)), expected[i], reason: 'case $i: ${jsonEncode(c)}');
      }
    });
  }, skip: node.isEmpty ? 'node not installed' : false);

  test('composeCarrierConfig == utils/auth.js composeCarrierConfig', () {
    expect(composeCarrierConfig('[{"sku":"B","qty":2},{"sku":"A","qty":1}]', 'AT'), 'A:1:B:2:AT');
    expect(composeCarrierConfig([{'sku': 'X', 'qty': 3}], ''), 'X:3:DE');
    expect(composeCarrierConfig('', 'DE'), '');
  });
}
