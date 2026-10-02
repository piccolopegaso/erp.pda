import 'package:flutter/widgets.dart';

import 'api.dart';
import 'device.dart';
import 'history.dart';
import 'net_monitor.dart';
import 'scanner.dart';
import 'session.dart';
import 'settings.dart';
import 'ws_print.dart';

/// All long-lived services, created once at start-up.
class AppState {
  AppState._(this.settings)
      : api = Api(settings),
        device = Device(settings),
        scanner = ScannerService(settings),
        history = ScanHistory(settings),
        ws = WsPrint(settings) {
    session = Session(settings, api);
    net = NetMonitor(api);
  }

  static Future<AppState> create() async {
    final s = await AppSettings.load();
    return AppState._(s);
  }

  final AppSettings settings;
  final Api api;
  final Device device;
  final ScannerService scanner;
  final ScanHistory history;
  final WsPrint ws;
  late final Session session;
  late final NetMonitor net;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.state, required super.child});

  final AppState state;

  static AppState of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing');
    return scope!.state;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => oldWidget.state != state;
}
