import 'dart:convert';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../ui/el.dart';
import '../../ui/widgets.dart';

/// web: mixin/listScan.js tagStatus
String rmaStatusLabel(int s) => switch (s) {
      0 => 'Received',
      1 => tr('pda.rma.st1'),
      2 => tr('pda.rma.st2'),
      3 => tr('wms.taskReadyToSwap'),
      4 => tr('wms.taskReadyToPack'),
      8 => tr('pda.rma.st8'),
      9 => 'Shipment Pending',
      10 => tr('pda.rma.st10'),
      99 => tr('wms.taskInboundedPartially'),
      100 => tr('wms.taskInbounded'),
      120 => 'Canceled',
      126 => 'In Transit',
      127 => 'Received',
      _ => '$s',
    };

ElType rmaStatusType(int s) => switch (s) {
      2 => ElType.danger,
      10 || 100 || 101 || 102 || 120 || 126 || 127 => ElType.success,
      8 || 9 => ElType.primary,
      _ => ElType.warning,
    };

/// web: mixin/listScan.js RMATypeStatus (Type)
const rmaBusinessTypes = {1: 'Original', 2: 'Customer Retour', 3: 'From FBA', 4: 'Undeliverable'};

/// web: mixin/listScan.js packageStatus (Package Status)
const rmaPackageStatus = {0: 'Not set', 1: 'Normal', 2: 'Damaged', 3: 'Lost'};

/// Item condition ("valid") -> inventory status at inbound
/// (backend returnedItemInventoryStatus: 2 = damaged, >0 = available, else invalid).
const rmaItemValid = {1: 'Valid', 2: 'Damaged', 0: 'Invalid', -1: 'Unchecked', -2: 'Scrapped'};

/// statuses not inbounded yet
const rmaOpenStatuses = [0, 1, 2, 3, 4, 8, 9, 10, 99];

/// RMA = r7g receiving records (web: views/receiving/received.vue, Mask "r7g.received.list").
class RmaService {
  RmaService(this.app);

  final AppState app;

  /// GET /v0/r7greceiving/list - paged by ID (o = last ID of previous page, 0 = first page)
  Future<(List<Map<String, dynamic>>, int, int)> list({int offsetId = 0, String search = '', List<int> statuses = const [], int limit = 20}) async {
    final params = <String, dynamic>{'l': limit, 'o': offsetId, 'q': search};
    if (statuses.isNotEmpty) params['Status[]'] = statuses;
    final d = await app.api.query('/v0/r7greceiving/list', params: params);
    if (d is! Map) return (<Map<String, dynamic>>[], 0, 0);
    final rows = (d['data'] as List? ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    return (rows, asInt(d['total']), asInt(d['next']));
  }

  Future<Map<String, dynamic>> one(int id) async {
    final d = await app.api.query('/v0/r7greceiving/', params: {'q': id});
    if (d is! Map || asInt(d['id']) == 0) throw ApiException(FailKind.business, 'receiving not found');
    return Map<String, dynamic>.from(d);
  }

  /// Exact match on the tracking number (the list search is a LIKE).
  Future<Map<String, dynamic>?> findByShipSN(String shipSN) async {
    final (rows, _, _) = await list(search: shipSN, limit: 10);
    for (final r in rows) {
      if (asStr(r['shipSN']).toUpperCase() == shipSN.toUpperCase()) return r;
    }
    return null;
  }

  /// POST /v0/r7greceiving/ (web: New). The API returns no id, so the record is looked up again.
  Future<Map<String, dynamic>> create(Map<String, dynamic> data) async {
    ApiException? failure;
    try {
      await app.api.command('POST', '/v0/r7greceiving/', data: data);
    } on ApiException catch (e) {
      // timeout: the record may have been created; duplicate tracking no.: it exists already
      failure = e;
    }
    final created = await findByShipSN(asStr(data['shipSN']));
    if (created == null) {
      if (failure != null && !failure.isNetwork) throw failure;
      throw ApiException(FailKind.business, tr('pda.rma.createFailed'));
    }
    return one(asInt(created['id']));
  }

  /// PUT /v0/r7greceiving/ with the full record (web: Edit). Absolute values -> safe to resend.
  Future<void> update(Map<String, dynamic> record) async {
    for (var attempt = 1;; attempt++) {
      try {
        await app.api.command('PUT', '/v0/r7greceiving/', data: record);
        return;
      } on ApiException catch (e) {
        if (!e.isNetwork || attempt >= 3) rethrow;
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
  }

  /// POST /v0/r7greceiving/inbound {id, items}: books the items into stock at their locations
  /// and sets the RMA to "Inbounded" (100). NOT idempotent - never resent blindly.
  Future<void> inbound(int id, List<Map<String, dynamic>> items) async {
    await app.api.command('POST', '/v0/r7greceiving/inbound', data: {'id': id, 'items': jsonEncode(items)});
  }

  /// Original outbound order for a return parcel (matches tracking / return label / order number).
  Future<Map<String, dynamic>?> findOrder(String code) async {
    try {
      final d = await app.api.query('/v0/p11yorders/list', params: {'l': 5, 'o': 0, 'q': code});
      final rows = d is Map ? (d['data'] as List? ?? const []) : const [];
      final maps = rows.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      if (maps.isEmpty) return null;
      final exact = maps.where((o) => [o['shipSN'], o['retourSN'], o['unid'], o['originSN']].any((v) => asStr(v).toUpperCase() == code.toUpperCase()));
      return exact.isNotEmpty ? exact.first : (maps.length == 1 ? maps.first : null);
    } catch (_) {
      return null;
    }
  }

  /// POST /v0/statics/upload/image (field "upload") -> stored file url
  Future<String> uploadImage(String path) async {
    final d = await app.api.upload('/v0/statics/upload/image', path);
    final url = d is String ? d : asStr(d is Map ? d['url'] : d);
    if (url.isEmpty) throw ApiException(FailKind.business, 'upload failed');
    return url;
  }

  /// web composeStaticUrl
  String staticUrl(String uri) {
    final base = app.settings.server;
    if (uri.length == 32 && !uri.contains('PDF')) return '$base/v0/static/$uri';
    if (uri.startsWith('base:')) return base + uri.substring(5);
    if (uri.startsWith('local:')) return base + uri.substring(6);
    return uri;
  }

  static List<String> imagesOf(Map<String, dynamic> rec) {
    final v = jsonAny(rec['image']);
    final list = v is Map ? (v['img'] as List? ?? const []) : (v is List ? v : const []);
    return [for (final i in list) if (i is Map && asStr(i['url']).isNotEmpty) asStr(i['url'])];
  }
}
