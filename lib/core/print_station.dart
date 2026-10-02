import 'dart:convert';

import 'package:dio/dio.dart';

import 'api.dart';
import 'settings.dart';

class PrintStationException implements Exception {
  PrintStationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Prints label PDFs on the packing-station PC through PrintBridge
/// (~/projects/PrintBridge, HTTP :9100, same service the web uses for "DHL Printer").
///
/// Web flow: CarrierGate returns a PDF URL -> browser prints it.
/// PDA flow: CarrierGate returns a PDF URL -> PDA downloads it -> POST base64 to PrintBridge.
class PrintStation {
  PrintStation(this.settings, this.api);

  final AppSettings settings;
  final Api api;

  final Dio _lan = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout: const Duration(seconds: 60),
  ));

  bool get configured => settings.printBridgeUrl.isNotEmpty;

  Future<List<String>> printers() async {
    final base = settings.printBridgeUrl;
    if (base.isEmpty) throw PrintStationException('not configured');
    try {
      final r = await _lan.get<dynamic>('$base/printers');
      final list = (r.data is Map ? r.data['printers'] : null) as List? ?? const [];
      return list.map((e) => '$e').toList();
    } on DioException catch (e) {
      throw PrintStationException(e.message ?? e.type.name);
    }
  }

  /// Absolute URL for a CarrierGate result (it may be relative).
  String resolveUrl(String url) {
    final u = url.trim();
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    final cg = settings.cgServer;
    return u.startsWith('/') ? '$cg$u' : '$cg/$u';
  }

  /// Download the PDF and send it to the configured printer.
  Future<void> printPdfUrl(String url, {String id = ''}) async {
    final base = settings.printBridgeUrl;
    if (base.isEmpty) throw PrintStationException('not configured');
    final bytes = await api.downloadBytes(resolveUrl(url));
    await printPdfBytes(bytes, id: id);
  }

  Future<void> printPdfBytes(List<int> bytes, {String id = ''}) async {
    final base = settings.printBridgeUrl;
    if (base.isEmpty) throw PrintStationException('not configured');
    try {
      final r = await _lan.post<dynamic>('$base/', data: {
        'printer': settings.printer,
        'data': base64Encode(bytes),
        'id': '${id.isEmpty ? DateTime.now().millisecondsSinceEpoch : id}.pdf',
      }, options: Options(validateStatus: (_) => true));
      if ((r.statusCode ?? 0) >= 300) {
        throw PrintStationException('${r.statusCode} ${r.data}');
      }
    } on DioException catch (e) {
      throw PrintStationException(e.message ?? e.type.name);
    }
  }
}
