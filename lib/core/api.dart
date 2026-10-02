import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'settings.dart';

/// How a request failed. The distinction matters on weak Wi-Fi:
/// many warehouse endpoints are NOT idempotent (each scan increments a counter),
/// so we may only retry automatically when the request provably never reached the server.
enum FailKind {
  /// Server answered with code != OK (business rule, validation, not found ...).
  business,

  /// Request never left the device (no connection / DNS / refused). Safe to retry.
  notSent,

  /// Request may or may not have been processed (timeout while waiting, connection dropped).
  unknown,

  /// Session expired / not logged in (HTTP 403 from TokenControl).
  auth,

  /// Unexpected HTTP status from server / proxy.
  server,
}

class ApiException implements Exception {
  ApiException(this.kind, this.message, {this.code = ''});

  final FailKind kind;
  final String code;
  final String message;

  bool get isNetwork => kind == FailKind.notSent || kind == FailKind.unknown;

  @override
  String toString() => code.isEmpty ? message : '$code: $message';
}

/// Called whenever a request completes, so the UI can show network quality.
typedef NetObserver = void Function(bool ok, int latencyMs, FailKind? kind);

class Api {
  Api(this.settings) {
    _dio = Dio();
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      o.baseUrl = settings.server;
      o.connectTimeout = Duration(seconds: settings.connectTimeout);
      o.sendTimeout = Duration(seconds: settings.receiveTimeout);
      o.receiveTimeout = Duration(seconds: settings.receiveTimeout);
      o.headers['Origin'] = settings.origin;
      final token = settings.token;
      if (token.isNotEmpty) o.headers['X-Token'] = token;
      h.next(o);
    }));
  }

  final AppSettings settings;
  late final Dio _dio;

  NetObserver? observer;

  /// Invoked on HTTP 403 so the app can show the re-login dialog.
  void Function()? onAuthExpired;

  /// GET for read-only endpoints: retried on any network failure.
  Future<dynamic> query(String path, {Map<String, dynamic>? params}) {
    return _send('GET', path, params: params, idempotent: true);
  }

  /// Any call that changes server state (note: several of them are HTTP GET, e.g. /p11yorders/scanShipSN).
  /// Only retried when the request never left the device.
  Future<dynamic> command(String method, String path, {Map<String, dynamic>? params, Object? data}) {
    return _send(method, path, params: params, data: data, idempotent: false);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? params,
    Object? data,
    required bool idempotent,
  }) async {
    const maxAttempts = 3;
    for (var attempt = 1;; attempt++) {
      final sw = Stopwatch()..start();
      try {
        final resp = await _dio.request<dynamic>(
          path,
          queryParameters: params,
          data: data,
          options: Options(method: method, responseType: ResponseType.json, validateStatus: (_) => true),
        );
        observer?.call(true, sw.elapsedMilliseconds, null);
        return _unwrap(resp);
      } on DioException catch (e) {
        final kind = _classify(e);
        observer?.call(false, sw.elapsedMilliseconds, kind);
        final retryable = kind == FailKind.notSent || (idempotent && kind == FailKind.unknown);
        if (retryable && attempt < maxAttempts) {
          await Future.delayed(Duration(milliseconds: 600 * attempt));
          continue;
        }
        throw ApiException(kind, _describe(e));
      }
    }
  }

  dynamic _unwrap(Response<dynamic> resp) {
    final status = resp.statusCode ?? 0;
    if (status == 403 || status == 401) {
      onAuthExpired?.call();
      throw ApiException(FailKind.auth, 'Session expired', code: 'SessionExpired');
    }
    if (status >= 500 || status == 0) {
      // the server (or a proxy) failed - the request may still have been processed
      throw ApiException(FailKind.unknown, 'HTTP $status', code: 'HTTP$status');
    }
    if (status >= 400) {
      throw ApiException(FailKind.server, 'HTTP $status', code: 'HTTP$status');
    }
    final body = resp.data;
    if (body is Map) {
      final code = (body['code'] ?? '').toString();
      if (code == 'OK' || code == 'ContinueWithoutOK') {
        return body['data'];
      }
      if (code.isNotEmpty) {
        throw ApiException(FailKind.business, _messageOf(body['data'], body['error'], code), code: code);
      }
      return body;
    }
    if (body is String && body.trim().isEmpty) return null;
    return body;
  }

  static String _messageOf(dynamic data, dynamic error, String code) {
    String fmt(dynamic d) {
      if (d == null) return '';
      if (d is String) return d;
      if (d is Map) {
        final parts = <String>[];
        if (d['message'] != null) parts.add('${d['message']}');
        if (d['field'] != null) parts.add('Field: ${d['field']}');
        if (d['value'] != null) parts.add('Value: ${d['value']}');
        return parts.isNotEmpty ? parts.join('\n') : d.toString();
      }
      return d.toString();
    }

    final m = fmt(data);
    if (m.isNotEmpty) return m;
    final e = fmt(error);
    if (e.isNotEmpty) return e;
    return code;
  }

  static FailKind _classify(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return FailKind.notSent;
      case DioExceptionType.connectionError:
        final err = e.error;
        if (err is SocketException) {
          final msg = err.message.toLowerCase();
          final os = err.osError?.message.toLowerCase() ?? '';
          final txt = '$msg $os';
          if (txt.contains('failed host lookup') ||
              txt.contains('connection refused') ||
              txt.contains('network is unreachable') ||
              txt.contains('no route to host') ||
              txt.contains('connection failed')) {
            return FailKind.notSent;
          }
        }
        if (err is HandshakeException) return FailKind.notSent;
        return FailKind.unknown;
      case DioExceptionType.cancel:
        return FailKind.notSent;
      case DioExceptionType.badCertificate:
        return FailKind.notSent;
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        return FailKind.unknown;
    }
  }

  static String _describe(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return 'connect timeout';
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'response timeout';
      default:
        final err = e.error;
        if (err is SocketException) return err.message;
        return e.message ?? e.type.name;
    }
  }
}
