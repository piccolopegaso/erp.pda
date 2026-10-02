import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';

enum NetState { good, slow, offline }

/// Tracks network quality from real request outcomes plus a light probe while offline,
/// so operators see at a glance whether the Wi-Fi in their aisle is usable.
class NetMonitor extends ChangeNotifier {
  NetMonitor(this.api) {
    api.observer = _observe;
  }

  final Api api;
  NetState state = NetState.good;
  int lastLatencyMs = 0;
  Timer? _probe;

  /// Fired when the network comes back after being offline (used to flush queues).
  final _recovered = StreamController<void>.broadcast();
  Stream<void> get onRecovered => _recovered.stream;

  void _observe(bool ok, int latencyMs, FailKind? kind) {
    final prev = state;
    if (ok) {
      lastLatencyMs = latencyMs;
      state = latencyMs > 2500 ? NetState.slow : NetState.good;
      _stopProbe();
    } else if (kind == FailKind.unknown) {
      // the server is reachable but answers too slowly (or the link dropped mid-request)
      state = NetState.slow;
      _startProbe();
    } else {
      state = NetState.offline;
      _startProbe();
    }
    if (prev != state) {
      if (prev != NetState.good && state == NetState.good) _recovered.add(null);
      notifyListeners();
    }
  }

  void _startProbe() {
    _probe ??= Timer.periodic(const Duration(seconds: 5), (_) => probe());
  }

  void _stopProbe() {
    _probe?.cancel();
    _probe = null;
  }

  /// Cheap unauthenticated request; its outcome feeds [_observe] through the Api observer.
  Future<void> probe() async {
    try {
      await api.query('/v0/version/');
    } catch (_) {}
  }

  @override
  void dispose() {
    _stopProbe();
    _recovered.close();
    super.dispose();
  }
}
