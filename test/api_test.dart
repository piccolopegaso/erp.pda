import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mic_pda/core/api.dart';
import 'package:mic_pda/core/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late HttpServer server;
  late AppSettings settings;
  late Api api;
  final hits = <String, int>{};
  String? lastOrigin;
  String? lastToken;

  setUp(() async {
    hits.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      hits[req.uri.path] = (hits[req.uri.path] ?? 0) + 1;
      lastOrigin = req.headers.value('origin');
      lastToken = req.headers.value('x-token');
      final res = req.response..headers.contentType = ContentType.json;
      switch (req.uri.path) {
        case '/ok':
          res.write(jsonEncode({'code': 'OK', 'data': {'id': 7}}));
        case '/biz':
          res.write(jsonEncode({'code': 'InternalError', 'data': 'item not in original order'}));
        case '/forbidden':
          res.statusCode = 403;
        case '/boom':
          res.statusCode = 502;
        case '/slow':
          await Future.delayed(const Duration(seconds: 3));
          res.write(jsonEncode({'code': 'OK', 'data': 1}));
      }
      await res.close();
    });
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
    settings.server = 'http://127.0.0.1:${server.port}';
    settings.token = 'tok123';
    settings.connectTimeout = 2;
    settings.receiveTimeout = 1;
    api = Api(settings);
  });

  tearDown(() async => server.close(force: true));

  test('unwraps OK envelope and sends Origin + X-Token', () async {
    final d = await api.query('/ok');
    expect(d, {'id': 7});
    expect(lastOrigin, kDefaultOrigin);
    expect(lastToken, 'tok123');
  });

  test('business error carries server message', () async {
    await expectLater(
      api.command('GET', '/biz'),
      throwsA(isA<ApiException>()
          .having((e) => e.kind, 'kind', FailKind.business)
          .having((e) => e.message, 'message', 'item not in original order')),
    );
  });

  test('403 -> auth + callback', () async {
    var called = 0;
    api.onAuthExpired = () => called++;
    await expectLater(api.query('/forbidden'), throwsA(isA<ApiException>().having((e) => e.kind, 'kind', FailKind.auth)));
    expect(called, 1);
  });

  test('5xx is an unknown outcome and a command is NOT retried', () async {
    await expectLater(api.command('GET', '/boom'), throwsA(isA<ApiException>().having((e) => e.kind, 'kind', FailKind.unknown)));
    expect(hits['/boom'], 1);
  });

  test('receive timeout: command not retried (could double count), query retried', () async {
    await expectLater(api.command('GET', '/slow'), throwsA(isA<ApiException>().having((e) => e.kind, 'kind', FailKind.unknown)));
    expect(hits['/slow'], 1);
    hits.clear();
    await expectLater(api.query('/slow'), throwsA(isA<ApiException>()));
    expect(hits['/slow'], 3);
  });

  test('connection refused -> notSent, safe to retry even for commands', () async {
    final port = server.port;
    await server.close(force: true);
    settings.server = 'http://127.0.0.1:$port';
    await expectLater(api.command('POST', '/x'), throwsA(isA<ApiException>().having((e) => e.kind, 'kind', FailKind.notSent)));
  });
}
