import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A known PDA scanner broadcast configuration.
class ScannerPreset {
  final String id;
  final String label;
  final List<String> actions;
  final List<String> extras;

  const ScannerPreset(this.id, this.label, this.actions, this.extras);
}

/// Broadcast actions / extra keys used by common PDA brands.
/// "auto" listens to all of them at once, which works out of the box on most devices.
const List<ScannerPreset> kScannerPresets = [
  ScannerPreset('urovo', 'Urovo / 优博讯', ['android.intent.ACTION_DECODE_DATA', 'urovo.rcv.message'], ['barcode_string', 'barocode']),
  ScannerPreset('honeywell', 'Honeywell', ['com.honeywell.decode.intent.action.EDIT_DATA', 'com.honeywell.scan.broadcast'], ['data', 'barcodeData']),
  ScannerPreset('zebra', 'Zebra DataWedge', ['com.miclinker.pda.SCAN', 'com.symbol.datawedge.api.RESULT_ACTION'], ['com.symbol.datawedge.data_string']),
  ScannerPreset('idata', 'iData / 盈达', ['android.intent.action.SCANRESULT'], ['value']),
  ScannerPreset('seuic', 'Seuic / 东集', ['com.android.server.scannerservice.broadcast'], ['scannerdata']),
  ScannerPreset('newland', 'Newland / 新大陆', ['nlscan.action.SCANNER_RESULT'], ['SCAN_BARCODE1']),
  ScannerPreset('chainway', 'Chainway / 成为', ['com.scanner.broadcast', 'com.rscja.scanner.action.scanner.RFID'], ['data']),
  ScannerPreset('sunmi', 'Sunmi / 商米', ['com.sunmi.scanner.ACTION_DATA_CODE_RECEIVED'], ['data']),
  ScannerPreset('generic', 'Generic / 通用', ['scan.rcv.message', 'com.android.scanner.broadcast', 'android.intent.action.SCANNER_RESULT'], ['barocode', 'scannerdata', 'data', 'barcode']),
];

const String kDefaultServer = 'https://api.courrierhub.com';

/// The Go backend rejects requests whose Origin header is not in its allow-list (HTTP 400).
/// A native app has no origin, so we present the web front-end's origin.
const String kDefaultOrigin = 'https://miclinker.com';

class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings._(prefs);
  }

  SharedPreferences get prefs => _prefs;

  String _str(String k, String d) => _prefs.getString(k) ?? d;
  bool _bool(String k, bool d) => _prefs.getBool(k) ?? d;
  int _int(String k, int d) => _prefs.getInt(k) ?? d;

  Future<void> _set(String k, Object v) async {
    if (v is String) {
      await _prefs.setString(k, v);
    } else if (v is bool) {
      await _prefs.setBool(k, v);
    } else if (v is int) {
      await _prefs.setInt(k, v);
    }
    notifyListeners();
  }

  // ---- server ----
  String get server => _str('server', kDefaultServer);
  set server(String v) => _set('server', _normalizeServer(v));

  /// CarrierGate (label service), same pairs as erp.webapp/.env.* (VUE_APP_BASE_API -> VUE_APP_CG_API).
  /// An explicit value in settings wins.
  String get cgServer {
    final custom = _str('cgServer', '');
    if (custom.isNotEmpty) return custom;
    const pairs = {
      'https://api.courrierhub.com': 'https://courrierhub.com',
      'https://di.courrierhub.com': 'https://a.courrierhub.com',
      'https://mic.courrierhub.com': 'https://a.courrierhub.com',
      'https://miccn.courrierhub.com': 'https://cn.courrierhub.com',
      'https://t.courrierhub.com': 'https://tcg.courrierhub.com',
    };
    return pairs[server] ?? server;
  }

  set cgServer(String v) => _set('cgServer', v.trim().isEmpty ? '' : _normalizeServer(v));

  String get origin => _str('origin', kDefaultOrigin);
  set origin(String v) => _set('origin', _normalizeServer(v));

  /// socket.io endpoint, derived from the API server (http->ws, https->wss).
  String get wsUrl {
    final s = server;
    if (s.startsWith('https://')) return 'wss://${s.substring(8)}/ws/';
    if (s.startsWith('http://')) return 'ws://${s.substring(7)}/ws/';
    return '$s/ws/';
  }

  static String _normalizeServer(String v) {
    var s = v.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.isNotEmpty && !s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    return s;
  }

  // ---- ui ----
  String get language => _str('language', 'en');
  set language(String v) => _set('language', v);

  bool get sound => _bool('sound', true);
  set sound(bool v) => _set('sound', v);

  bool get vibrate => _bool('vibrate', true);
  set vibrate(bool v) => _set('vibrate', v);

  bool get keepScreenOn => _bool('keepScreenOn', true);
  set keepScreenOn(bool v) => _set('keepScreenOn', v);

  // ---- print station (PrintBridge on the packing PC, port 9100) ----
  /// e.g. "192.168.1.20" or "192.168.1.20:9100"; empty = not configured
  String get printHost => _str('printHost', '');
  set printHost(String v) => _set('printHost', v.trim());

  String get printBridgeUrl {
    var h = printHost.trim();
    if (h.isEmpty) return '';
    if (!h.startsWith('http://') && !h.startsWith('https://')) h = 'http://$h';
    final u = Uri.tryParse(h);
    if (u == null) return '';
    return u.hasPort ? '${u.scheme}://${u.host}:${u.port}' : '${u.scheme}://${u.host}:9100';
  }

  /// Printer name as listed by PrintBridge (GET /printers)
  String get printer => _str('printer', '');
  set printer(String v) => _set('printer', v);

  /// web: Pack Scan Order "Auto Print"
  bool get autoPackScanPrint => _bool('autoPackScanPrint', false);
  set autoPackScanPrint(bool v) => _set('autoPackScanPrint', v);

  // ---- network ----
  /// Seconds to wait for a TCP connection (weak Wi-Fi: keep short, retry is safe here).
  int get connectTimeout => _int('connectTimeout', 8);
  set connectTimeout(int v) => _set('connectTimeout', v);

  /// Seconds to wait for a response once the request was sent.
  int get receiveTimeout => _int('receiveTimeout', 25);
  set receiveTimeout(int v) => _set('receiveTimeout', v);

  // ---- scanner ----
  /// 'auto' = all presets, otherwise preset id, or 'custom'.
  String get scannerPreset => _str('scannerPreset', 'auto');
  set scannerPreset(String v) => _set('scannerPreset', v);

  String get customAction => _str('customAction', '');
  set customAction(String v) => _set('customAction', v.trim());

  String get customExtra => _str('customExtra', '');
  set customExtra(String v) => _set('customExtra', v.trim());

  /// Keyboard-wedge (scanner types like a keyboard and ends with Enter).
  bool get wedgeEnabled => _bool('wedgeEnabled', true);
  set wedgeEnabled(bool v) => _set('wedgeEnabled', v);

  /// Identical code within this window is treated as a bounce and ignored.
  int get dedupMs => _int('dedupMs', 300);
  set dedupMs(int v) => _set('dedupMs', v);

  List<String> get scannerActions {
    final p = scannerPreset;
    final out = <String>{};
    if (p == 'auto') {
      for (final s in kScannerPresets) {
        out.addAll(s.actions);
      }
    } else if (p != 'custom' && p != 'none') {
      out.addAll(kScannerPresets.firstWhere((s) => s.id == p, orElse: () => kScannerPresets.last).actions);
    }
    if (customAction.isNotEmpty) out.add(customAction);
    return out.toList();
  }

  List<String> get scannerExtras {
    final p = scannerPreset;
    final out = <String>[];
    if (customExtra.isNotEmpty) out.add(customExtra);
    if (p == 'auto' || p == 'custom') {
      for (final s in kScannerPresets) {
        out.addAll(s.extras);
      }
    } else if (p != 'none') {
      out.addAll(kScannerPresets.firstWhere((s) => s.id == p, orElse: () => kScannerPresets.last).extras);
    }
    return out.toSet().toList();
  }

  // ---- session persistence ----
  String get account => _str('account', '');
  set account(String v) => _set('account', v);

  String get token => _str('token', '');
  set token(String v) => _set('token', v);

  /// Login environment id returned by the server; lets this device skip the captcha next time.
  String loginEnvId(String account) => _str('eid:${account.toLowerCase()}', '');
  Future<void> setLoginEnvId(String account, String eid) => _set('eid:${account.toLowerCase()}', eid);

  // ---- generic JSON blobs (caches, queues) ----
  T? readJson<T>(String key) {
    final s = _prefs.getString('json:$key');
    if (s == null) return null;
    try {
      return jsonDecode(s) as T;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeJson(String key, Object? value) async {
    if (value == null) {
      await _prefs.remove('json:$key');
    } else {
      await _prefs.setString('json:$key', jsonEncode(value));
    }
  }
}
