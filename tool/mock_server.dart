// Local mock of the MICLinker Go backend for end-to-end testing of the PDA app.
//
//   dart run tool/mock_server.dart            (listens on :8787)
//   Android emulator -> server URL http://10.0.2.2:8787
//
// Mirrors the real contracts (see ~/go/src/erp): {code,data} envelope, HTTP 200 with
// code != OK for business errors, 403 without a valid X-Token, 400 without an
// allow-listed Origin header, socket.io (EIO=4) at /ws/.
//
// Mock login: account "pda@mock.local", password "mock-pass", captcha "1234".
//
// Network fault injection (for weak-Wi-Fi tests):
//   GET /__mock/delay?ms=30000   -> every API response is delayed (timeouts)
//   GET /__mock/delay?ms=0       -> back to normal
//   GET /__mock/offline?sec=20   -> refuse all connections for 20 s (keeps state)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const allowedOrigins = {'miclinker.com', 'localhost:9527'};
const mockAccount = 'pda@mock.local';
const mockPassword = 'mock-pass';
const mockCaptcha = '1234';

int delayMs = 0;
final tokens = <String>{};
final log = <String>[];

// 1x1 PNG
const png1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

final customers = [
  {'guid': 'C001', 'fullName': 'Anker Innovations DE'},
  {'guid': 'C002', 'fullName': 'EcoFlow Europe'},
];

final items = {
  'SKU-A': {'guid': 'I-A', 'unid': 'SKU-A', 'name': 'Power Bank 20000mAh', 'barcode': '4006381333931', 'agentGUID': 'C001', 'weight': 0.45},
  'SKU-B': {'guid': 'I-B', 'unid': 'SKU-B', 'name': 'USB-C Cable 1m', 'barcode': '4006381333948', 'agentGUID': 'C001', 'weight': 0.05},
  'SKU-C': {'guid': 'I-C', 'unid': 'SKU-C', 'name': 'Portable Station', 'barcode': '6970000000011', 'agentGUID': 'C002', 'weight': 9.8},
};

Map<String, dynamic>? findItem(String q) {
  for (final i in items.values) {
    if (i['unid'] == q || i['barcode'] == q) return i;
  }
  return null;
}

final compartments = {
  'A-01-01': {'guid': 'L-A0101', 'name': 'A-01-01', 'warehouseUNID': 'DE01', 'zoneCode': 'A', 'pickingPriority': 1},
  'A-02-03': {'guid': 'L-A0203', 'name': 'A-02-03', 'warehouseUNID': 'DE01', 'zoneCode': 'A', 'pickingPriority': 2},
  'B-10-01': {'guid': 'L-B1001', 'name': 'B-10-01', 'warehouseUNID': 'DE01', 'zoneCode': 'B', 'pickingPriority': 5},
};

final inventory = [
  {'id': 1, 'itemUnid': 'SKU-A', 'itemName': 'Power Bank 20000mAh', 'compartment': 'A-01-01', 'locationGuid': 'L-A0101', 'warehouse': 'DE01', 'itemBatch': 'B2409', 'quantity': 120, 'lockedQty': 10, 'status': 10, 'customer': 'Anker Innovations DE'},
  {'id': 2, 'itemUnid': 'SKU-A', 'itemName': 'Power Bank 20000mAh', 'compartment': 'B-10-01', 'locationGuid': 'L-B1001', 'warehouse': 'DE01', 'itemBatch': 'B2410', 'quantity': 40, 'lockedQty': 0, 'status': 10, 'customer': 'Anker Innovations DE'},
  {'id': 3, 'itemUnid': 'SKU-B', 'itemName': 'USB-C Cable 1m', 'compartment': 'A-01-01', 'locationGuid': 'L-A0101', 'warehouse': 'DE01', 'itemBatch': '', 'quantity': 500, 'lockedQty': 0, 'status': 10, 'customer': 'Anker Innovations DE'},
  {'id': 4, 'itemUnid': 'SKU-C', 'itemName': 'Portable Station', 'compartment': 'A-02-03', 'locationGuid': 'L-A0203', 'warehouse': 'DE01', 'itemBatch': '', 'quantity': 3, 'lockedQty': 0, 'status': 2, 'customer': 'EcoFlow Europe'},
];

// ---------------- outbound orders ----------------
final orders = <String, Map<String, dynamic>>{
  'MO20260001': {
    'id': 101, 'unid': 'MO20260001', 'originSN': 'AMZ-305-111', 'agentGUID': 'C001', 'carrier': 'DHL',
    'recName1': 'Max Mustermann', 'recCountry': 'DE', 'shipQty': 2, 'shipBundle': 'TRK1001\nTRK1002',
    'shipBundleSent': <String>[], 'status': 90, 'items': jsonEncode([{'sku': 'SKU-A', 'qty': 2}]),
    'note': 'Fragile', 'noteInner': '',
  },
  'MO20260002': {
    'id': 102, 'unid': 'MO20260002', 'originSN': 'EBAY-777', 'agentGUID': 'C002', 'carrier': 'UPS',
    'recName1': 'Erika Musterfrau', 'recCountry': 'AT', 'shipQty': 1, 'shipBundle': 'TRK2001',
    'shipBundleSent': <String>[], 'status': 90, 'items': jsonEncode([{'sku': 'SKU-C', 'qty': 1}, {'sku': 'SKU-B', 'qty': 1}]),
    'noteInner': 'Check the SN sticker!',
    // QC requirements
    'skuQCRequired': ['SKU-C', 'SKU-B'], 'skuQCDone': <String>[], 'snRequired': 1, 'snDone': <Map>[],
  },
  'MO20260099': {
    'id': 199, 'unid': 'MO20260099', 'agentGUID': 'C001', 'shipQty': 1, 'shipBundle': 'CANCEL1',
    'shipBundleSent': <String>[], 'status': 120, 'items': '[]',
  },
};

Map<String, dynamic>? orderByAny(String q) {
  for (final o in orders.values) {
    if (o['unid'] == q || (o['shipBundle'] as String).split('\n').contains(q)) return o;
  }
  return null;
}

Map<String, dynamic> orderJson(Map<String, dynamic> o) {
  final r = Map<String, dynamic>.from(o)
    ..remove('skuQCRequired')
    ..remove('skuQCDone')
    ..remove('snRequired')
    ..remove('snDone');
  if (o['skuQCRequired'] != null) {
    final req = (o['skuQCRequired'] as List).length;
    final done = (o['skuQCDone'] as List).length;
    r['skuQCRequiredQty'] = req;
    r['skuQCScannedQty'] = done;
    r['skuQCRemainingQty'] = req - done;
    r['skuQCCurrentItemID'] = done < req ? (o['skuQCRequired'] as List)[done] : '';
    r['shippingScanSKUQC'] = jsonEncode([for (final s in o['skuQCDone'] as List) {'sku': s}]);
    final snReq = o['snRequired'] as int;
    final snDone = (o['snDone'] as List).length;
    r['snRequiredQty'] = snReq;
    r['snScannedQty'] = snDone;
    r['snRemainingQty'] = snReq - snDone;
    r['snCurrentItemID'] = 'SKU-C';
    r['itemSN'] = jsonEncode(o['snDone']);
  }
  return r;
}

Map<String, dynamic> skuQCResp(Map<String, dynamic> o) {
  final j = orderJson(o);
  return {
    'id': o['id'], 'unid': o['unid'], 'status': o['status'], 'shippingScanSKUQC': j['shippingScanSKUQC'],
    'itemID': j['skuQCCurrentItemID'], 'requiredSKUQCQty': j['skuQCRequiredQty'], 'scannedSKUQCQty': j['skuQCScannedQty'],
    'remainingSKUQCQty': j['skuQCRemainingQty'], 'skuQCCompleted': j['skuQCRemainingQty'] == 0,
    'requiredSNQty': j['snRequiredQty'], 'scannedSNQty': j['snScannedQty'], 'remainingSNQty': j['snRemainingQty'],
    'snRequired': (j['snRequiredQty'] as int) > 0, 'snCompleted': j['snRemainingQty'] == 0,
  };
}

Map<String, dynamic> snResp(Map<String, dynamic> o, [String sn = '']) {
  final j = orderJson(o);
  return {
    'id': o['id'], 'unid': o['unid'], 'status': o['status'], 'sn': sn, 'itemSN': j['itemSN'], 'itemID': 'SKU-C',
    'requiredSNQty': j['snRequiredQty'], 'scannedSNQty': j['snScannedQty'], 'remainingSNQty': j['snRemainingQty'],
    'completed': j['snRemainingQty'] == 0,
  };
}

// ---------------- returns ----------------
final receivings = <int, Map<String, dynamic>>{};
int receivingSeq = 500;

// ---------------- swap SN ----------------
final swapState = <int, List<String>>{};
int snSeq = 1;

// ---------------- pallets ----------------
final pallets = {
  'LD20260001': {
    'guid': 'P1', 'palletCode': 'LD20260001', 'pickupCarrier': 'DHL Freight', 'unitStr': 'Pallet',
    'plateNumber2': 'B-AB 1234', 'pickupDate': '2026-10-02', 'importantNote': 'Max. 30 Pakete pro Palette', 'trackingCount': 0,
  },
};
final palletTracking = <String, List<Map<String, dynamic>>>{'LD20260001': []};

// ---------------- picklists ----------------
final picklists = {
  'PL20260001': {
    'id': 301, 'unid': 'PL20260001', 'type': 100, 'status': 50, 'itemQty': 6, 'itemQtyPicked': 0,
    'items': jsonEncode([
      {'sku': 'SKU-A', 'itemName': 'Power Bank 20000mAh', 'itemBatch': 'B2410', 'qty': 2, 'inventoryName': 'B-10-01'},
      {'sku': 'SKU-B', 'itemName': 'USB-C Cable 1m', 'itemBatch': '', 'qty': 3, 'inventoryName': 'A-01-01'},
      {'sku': 'SKU-C', 'itemName': 'Portable Station', 'itemBatch': '', 'qty': 1, 'inventoryName': 'A-02-03'},
    ]),
  },
};

// =====================================================================

late int port;
HttpServer? server;

Future<void> listen() async {
  server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('mock backend on :$port');
  server!.listen((req) => unawaited(handle(req)));
}

Future<void> main(List<String> args) async {
  port = args.isNotEmpty ? int.parse(args.first) : 8787;
  await listen();
}

Future<void> handle(HttpRequest req) async {
  final path = req.uri.path;
  final q = req.uri.queryParameters;
  stdout.writeln('${DateTime.now().toIso8601String().substring(11, 19)} ${req.method} ${req.uri}');

  if (path == '/__mock/offline') {
    // simulate a Wi-Fi dead zone: refuse connections for N seconds, keep all state
    final sec = int.tryParse(q['sec'] ?? '20') ?? 20;
    await send(req, {'code': 'OK', 'data': 'offline for ${sec}s'});
    await server?.close(force: true);
    stdout.writeln('--- offline for ${sec}s');
    Timer(Duration(seconds: sec), listen);
    return;
  }
  if (path == '/__mock/delay') {
    delayMs = int.tryParse(q['ms'] ?? '0') ?? 0;
    return send(req, {'code': 'OK', 'data': 'delay=$delayMs'});
  }

  if (path.startsWith('/ws')) return handleWs(req);

  // accessControl: Origin must be allow-listed
  final origin = req.headers.value('origin');
  final host = origin == null ? null : Uri.tryParse(origin)?.authority;
  if (host == null || !allowedOrigins.contains(host)) {
    req.response.statusCode = 400;
    return req.response.close();
  }

  if (delayMs > 0) await Future.delayed(Duration(milliseconds: delayMs));

  final body = req.method == 'GET' ? null : await utf8.decoder.bind(req).join();
  final json = (body == null || body.isEmpty) ? <String, dynamic>{} : jsonDecode(body) as Map<String, dynamic>;

  // ---- public ----
  if (path == '/v0/version/') return ok(req, {'version': 'mock', 'commit': 'mock'});
  if (path == '/v0/captcha/') return ok(req, {'id': 'cap-${DateTime.now().millisecondsSinceEpoch}', 'image': 'data:image/png;base64,$png1x1'});
  if (path == '/v0/auth/_ci') {
    return json['envId'] == 'ENV-MOCK' ? ok(req, null) : fail(req, 'LoginError', 'LoginError');
  }
  if (path == '/v0/auth/login') {
    if ('${json['xxs']}'.isEmpty) return fail(req, 'IntegrityError', 'IntegrityError');
    final captchaOk = json['captcha'] == mockCaptcha || json['eid'] == 'ENV-MOCK';
    if (!captchaOk) return fail(req, 'CaptchaError', 'CaptchaError');
    if (json['account'] != mockAccount || json['passwd'] != mockPassword) return fail(req, 'LoginError', 'LoginError');
    final t = 'T${DateTime.now().microsecondsSinceEpoch}';
    tokens.add(t);
    return ok(req, {'token': t, 'loginEnvId': 'ENV-MOCK'});
  }

  // ---- TokenControl ----
  final token = req.headers.value('x-token') ?? q['x_token'] ?? '';
  if (!tokens.contains(token)) {
    req.response.statusCode = 403;
    return req.response.close();
  }

  switch (path) {
    case '/v0/__expire':
      tokens.clear();
      return ok(req, 'all sessions expired');
    case '/v0/auth/stat':
      return ok(req, {'account': mockAccount, 'name': 'PDA Tester', 'roles': ['warehouse'], 'token': token});
    case '/v0/auth/logout':
      tokens.remove(token);
      return ok(req, '');
    case '/v0/customer/opts':
      return ok(req, customers);
    case '/v0/settings/config':
      return ok(req, {'B2C': 1, 'RMA': 2, 'Repair': 3});
    case '/v0/masken/':
      return ok(req, {'mask': jsonEncode([{'type': 'printSN'}])});

    // ---------- outbound ----------
    case '/v0/p11yorders/scanShipSN':
      final o = orderByAny(q['q'] ?? '');
      if (o == null) return fail(req, 'InternalError', 'order not found');
      final code = q['q']!;
      final sent = o['shipBundleSent'] as List<String>;
      final already = sent.contains(code) || (code == o['unid'] && sent.isNotEmpty);
      if (!already && o['status'] != 120) {
        sent.add((o['shipBundle'] as String).split('\n').contains(code) ? code : (o['shipBundle'] as String).split('\n').first);
        if (sent.length >= (o['shipQty'] as int)) o['status'] = o['skuQCRequired'] != null ? 95 : 96;
      }
      return ok(req, {...orderJson(o), 'alreadyScanned': already});
    case '/v0/p11yorders/scanItemSKUQC':
      final o = orders.values.firstWhere((x) => '${x['id']}' == q['id'], orElse: () => {});
      if (o.isEmpty) return fail(req, 'InternalError', 'order not found');
      final s = q['q'] ?? '';
      if (s.isNotEmpty) {
        final req0 = o['skuQCRequired'] as List;
        final done = o['skuQCDone'] as List;
        final item = findItem(s);
        if (item == null) return fail(req, 'InternalError', 'item not found: $s');
        if (done.length >= req0.length || req0[done.length] != item['unid']) {
          return fail(req, 'InternalError', 'SKU ${item['unid']} does not match ${done.length < req0.length ? req0[done.length] : '-'}');
        }
        done.add(item['unid']);
      }
      return ok(req, skuQCResp(o));
    case '/v0/p11yorders/scanItemSN':
      final o = orders.values.firstWhere((x) => '${x['id']}' == q['id'], orElse: () => {});
      if (o.isEmpty) return fail(req, 'InternalError', 'order not found');
      final s = q['q'] ?? '';
      if (s.isNotEmpty) {
        final done = o['snDone'] as List;
        if (!s.startsWith('SN')) return fail(req, 'InternalError', 'SN pattern mismatch: $s');
        if (done.any((d) => d['sn'] == s)) return fail(req, 'InternalError', 'SN already used: $s');
        done.add({'sku': 'SKU-C', 'sn': s});
        if (done.length >= (o['snRequired'] as int)) o['status'] = 96;
      }
      return ok(req, snResp(o));
    case '/v0/p11yorders/scanLog':
      final id = int.tryParse(q['id'] ?? '0') ?? 0;
      final code = q['q'] ?? '';
      if (id == 0) {
        final o = orderByAny(code);
        if (o == null) return ok(req, {'id': 0, 'unid': ''});
        return ok(req, orderJson(o));
      }
      final o = orders.values.firstWhere((x) => x['id'] == id);
      final sent = o['shipBundleSent'] as List<String>;
      if (!sent.contains(code)) sent.add(code);
      return ok(req, {...orderJson(o), 'updatedAt': DateTime.now().toUtc().toIso8601String()});
    case '/v0/p11yorders/swapSN':
      final id = int.tryParse(q['id'] ?? '0') ?? 0;
      final code = q['q'] ?? '';
      if (id == 0) {
        final o = orderByAny(code);
        if (o == null) return fail(req, 'InternalError', 'order not found');
        swapState[o['id'] as int] = [];
        return ok(req, {'id': o['id'], 'unid': o['unid'], 'shipBundleSent': o['shipBundleSent'], 'sn': '', 'itemSN': jsonEncode([{'sku': 'SKU-C', 'sn': 'SN-OLD-1'}])});
      }
      final st = swapState[id] ??= [];
      st.add(code);
      var sn = '';
      if (st.length >= 2) {
        sn = 'SN-NEW-${(snSeq++).toString().padLeft(4, '0')}';
        st.clear();
      }
      return ok(req, {'id': id, 'unid': 'MO20260002', 'shipBundleSent': <String>[], 'sn': sn, 'itemSN': jsonEncode([{'sku': 'SKU-C', 'sn': 'SN-OLD-1'}, if (sn.isNotEmpty) {'sku': 'SKU-C', 'sn': sn}])});

    // ---------- returns ----------
    case '/v0/r7greceiving/scan':
      final id = int.tryParse(q['id'] ?? '0') ?? 0;
      final code = q['q'] ?? '';
      if (code.length < 5) return fail(req, 'InternalError', 'invalid number');
      if (id == 0) {
        final o = orderByAny(code);
        if (o == null) return fail(req, 'InternalError', 'order not found');
        final existing = receivings.values.where((r) => r['shipSN'] == code);
        if (existing.isNotEmpty) return ok(req, existing.first);
        final r = {
          'id': ++receivingSeq, 'agentGUID': o['agentGUID'], 'shipSN': code, 'originSN': o['unid'], 'originCountry': o['recCountry'],
          'dispose': code.contains('R') ? 'REPAIR' : 'HOLD', 'items': '[]', 'itemStrOrigin': 'SKU-A:2',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        };
        receivings[r['id'] as int] = r;
        return ok(req, r);
      }
      final r = receivings[id];
      if (r == null) return fail(req, 'InternalError', 'receiving not found');
      final item = findItem(code);
      if (item == null) return fail(req, 'InternalError', 'item not found');
      if (!(r['itemStrOrigin'] as String).contains(item['unid'] as String)) return fail(req, 'InternalError', 'item not in original order');
      final list = (jsonDecode(r['items'] as String) as List).cast<Map>();
      final row = list.where((x) => x['itemId'] == item['unid']);
      if (row.isEmpty) {
        list.add({'itemId': item['unid'], 'qty': 1});
      } else {
        row.first['qty'] = (row.first['qty'] as int) + 1;
      }
      r['items'] = jsonEncode(list);
      return ok(req, r);
    case '/v0/r7greceiving/':
      final r = receivings[int.tryParse(q['q'] ?? '') ?? 0];
      return r == null ? fail(req, 'NotFoundError', 'NotFoundError') : ok(req, r);
    case '/v0/r7gorders/scanLog':
      return ok(req, {'id': 0, 'unid': ''});

    // ---------- stock ----------
    case '/v0/compartment/any':
      final c = compartments[q['q']];
      return ok(req, c == null ? {'guid': '', 'name': ''} : {...c, 'inventory': {}});
    case '/v0/item/any':
      final i = findItem(q['q'] ?? '');
      return ok(req, i ?? {'guid': '', 'unid': ''});
    case '/v0/inventory/list':
      final s = (q['q'] ?? '').toLowerCase();
      final loc = q['LocationGUID'];
      final rows = inventory.where((r) {
        if (loc != null && r['locationGuid'] != loc) return false;
        return '${r['itemUnid']}'.toLowerCase().contains(s) ||
            '${r['compartment']}'.toLowerCase().contains(s) ||
            '${r['itemBatch']}'.toLowerCase().contains(s);
      }).toList();
      return ok(req, {'total': rows.length, 'page': 1, 'next': '2026-01-01T00:00:00Z', 'data': rows});

    // ---------- picklist ----------
    case '/v0/p11y/pick/any':
      final p = picklists[q['q']];
      return p == null ? fail(req, 'NotFoundError', 'NotFoundError') : ok(req, {'id': p['id'], 'type': p['type'], 'unid': p['unid']});
    case '/v0/p11y/pick/':
      final p = picklists.values.firstWhere((x) => '${x['id']}' == q['q'], orElse: () => {});
      return p.isEmpty ? fail(req, 'NotFoundError', 'NotFoundError') : ok(req, p);

    // ---------- pallets ----------
    case '/v0/wms/pallets/handover/scan':
      final scan = '${json['scan']}'.trim().toUpperCase();
      for (final p in pallets.values) {
        if (p['palletCode'] == scan || '${p['plateNumber2']}'.replaceAll(' ', '') == scan.replaceAll(' ', '')) {
          p['trackingCount'] = palletTracking[p['palletCode']]!.length;
          return ok(req, {'scan': scan, 'scanType': 'palletCode', 'ambiguous': false, 'pallet': p});
        }
      }
      return ok(req, {'scan': scan, 'scanType': '', 'ambiguous': false, 'pallet': null});
  }

  final m = RegExp(r'^/v0/wms/pallets/([^/]+)/tracking(/(flush|remove))?$').firstMatch(path);
  if (m != null) {
    final code = Uri.decodeComponent(m.group(1)!);
    final list = palletTracking[code];
    if (list == null) return fail(req, 'NotFoundError', 'loading number not found');
    switch (m.group(3)) {
      case null:
        return ok(req, list);
      case 'flush':
        for (final it in (json['items'] as List)) {
          final t = '${it['trackingNo']}';
          if (t.startsWith('ERR')) return fail(req, 'TrackingConflictError', '$t is already on pallet LD20259999 TrackingConflictError');
          if (!list.any((x) => x['trackingNo'] == t)) {
            final ord = orderByAny(t);
            list.add({
              'id': list.length + 1, 'palletCode': code, 'trackingNo': t, 'outboundUNID': ord?['unid'] ?? '',
              'carrier': ord?['carrier'] ?? '', 'meta': jsonEncode({'resolveStatus': ord == null ? 'not_found' : 'resolved'}),
            });
          }
        }
        return ok(req, {'pairs': []});
      case 'remove':
        list.removeWhere((x) => x['trackingNo'] == json['trackingNo']);
        return ok(req, null);
    }
  }

  return fail(req, 'NotFoundError', 'mock: no route $path');
}

Future<void> send(HttpRequest req, Object body) async {
  req.response.headers.contentType = ContentType.json;
  req.response.write(jsonEncode(body));
  await req.response.close();
}

Future<void> ok(HttpRequest req, Object? data) => send(req, {'code': 'OK', 'data': data});

Future<void> fail(HttpRequest req, String code, String data) => send(req, {'code': code, 'data': data});

// ---------------- socket.io (EIO=4) ----------------
Future<void> handleWs(HttpRequest req) async {
  final origin = req.headers.value('origin');
  if (origin == null || !allowedOrigins.contains(Uri.tryParse(origin)?.authority)) {
    req.response.statusCode = 403;
    return req.response.close();
  }
  final ws = await WebSocketTransformer.upgrade(req);
  ws.add('0${jsonEncode({'sid': 'mock', 'upgrades': [], 'pingInterval': 25000, 'pingTimeout': 20000})}');
  final ping = Timer.periodic(const Duration(seconds: 20), (_) => ws.add('2'));
  ws.listen((data) {
    if (data is! String) return;
    if (data == '40') {
      ws.add('40${jsonEncode({'sid': 'mock-ns'})}');
    } else if (data.startsWith('42')) {
      final arr = jsonDecode(data.substring(2)) as List;
      stdout.writeln('  ws event: ${arr[0]} ${arr.length > 1 ? arr[1] : ''}');
      if (arr[0] == 'print') ws.add('42${jsonEncode(['msg', 'Printing!'])}');
    }
  }, onDone: ping.cancel);
}
