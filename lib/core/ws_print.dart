import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'settings.dart';

/// Minimal socket.io (Engine.IO v4, websocket transport) client.
///
/// The PDA only needs to *emit* `print` events: the Go server relays them to the
/// desktop station logged in with the `printShipment` role, which does the actual printing
/// (same mechanism as the web app's RemotePrinter).
class WsPrint {
  WsPrint(this.settings);

  final AppSettings settings;
  WebSocket? _ws;
  bool _ready = false;
  Completer<void>? _connecting;
  final _messages = StreamController<String>.broadcast();

  /// Server notifications such as "Printing!" or "Printer not online!".
  Stream<String> get messages => _messages.stream;

  bool get connected => _ready;

  Future<void> ensureConnected() async {
    if (_ready && _ws != null) return;
    if (_connecting != null) return _connecting!.future;
    final c = Completer<void>();
    _connecting = c;
    try {
      final url = '${settings.wsUrl}?EIO=4&transport=websocket';
      final ws = await WebSocket.connect(url, headers: {'Origin': settings.origin}).timeout(Duration(seconds: settings.connectTimeout + 4));
      ws.pingInterval = null;
      _ws = ws;
      ws.listen(_onData, onDone: _onClosed, onError: (_) => _onClosed(), cancelOnError: true);
      // wait for the namespace connect ack ("40")
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      while (!_ready && DateTime.now().isBefore(deadline) && _ws != null) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (!_ready) throw const SocketException('socket.io handshake failed');
      c.complete();
    } catch (e) {
      _onClosed();
      c.completeError(e);
    } finally {
      _connecting = null;
    }
    return c.future;
  }

  void _onData(dynamic data) {
    if (data is! String || data.isEmpty) return;
    final type = data[0];
    switch (type) {
      case '0': // engine open
        _ws?.add('40');
        break;
      case '2': // ping
        _ws?.add('3');
        break;
      case '4':
        if (data.startsWith('40')) {
          _ready = true;
          _emit('login', {
            'token': settings.token,
            'version': 'pda',
            'userAgent': 'MIC PDA (Flutter)',
            'visitedUrl': 'pda://app',
          });
        } else if (data.startsWith('42')) {
          try {
            final arr = jsonDecode(data.substring(2));
            if (arr is List && arr.isNotEmpty && arr[0] == 'msg' && arr.length > 1) {
              final m = arr[1];
              _messages.add(m is String ? m : jsonEncode(m));
            }
          } catch (_) {}
        }
        break;
    }
  }

  void _onClosed() {
    _ready = false;
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
  }

  void _emit(String event, Object payload) {
    _ws?.add('42${jsonEncode([event, payload])}');
  }

  /// Same payload format as the web app: a JSON *string* {type, sn}.
  Future<void> printLabel(String type, String sn) async {
    await ensureConnected();
    _emit('print', jsonEncode({'type': type, 'sn': sn}));
  }

  void close() => _onClosed();
}
