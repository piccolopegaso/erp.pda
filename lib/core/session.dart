import 'package:flutter/foundation.dart';

import 'api.dart';
import 'settings.dart';

class UserInfo {
  UserInfo(this.raw);

  final Map<String, dynamic> raw;

  String get account => '${raw['account'] ?? ''}';
  String get name => '${raw['name'] ?? ''}';
  String get agentName => '${raw['agentName'] ?? ''}';
  List<String> get roles => (raw['roles'] as List? ?? const []).map((e) => '$e').toList();
}

class CaptchaChallenge {
  CaptchaChallenge(this.id, this.imageBase64);

  final String id;

  /// PNG bytes encoded as base64 (without the data: prefix).
  final String imageBase64;
}

class Session extends ChangeNotifier {
  Session(this.settings, this.api);

  final AppSettings settings;
  final Api api;

  UserInfo? user;

  /// While the remembered token is checked at start-up, a 403 just means "go to login".
  bool validating = false;

  /// customer GUID -> display name, cached for offline use
  Map<String, String> customers = {};

  bool get loggedIn => settings.token.isNotEmpty;

  /// True if the server accepts the remembered login-environment id (no captcha needed).
  Future<bool> canSkipCaptcha(String account) async {
    final eid = settings.loginEnvId(account.trim());
    if (eid.isEmpty) return false;
    try {
      await api.command('POST', '/v0/auth/_ci', data: {'login': account.trim(), 'envId': eid});
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<CaptchaChallenge> captcha() async {
    final data = await api.query('/v0/captcha/');
    final image = '${data['image'] ?? ''}';
    final comma = image.indexOf(',');
    return CaptchaChallenge('${data['id'] ?? ''}', comma >= 0 ? image.substring(comma + 1) : image);
  }

  /// [captchaId] is always required by the backend ("xxs"); [captchaText] may be empty when
  /// the remembered eid is valid.
  Future<void> login({
    required String account,
    required String password,
    required String captchaId,
    String captchaText = '',
  }) async {
    final acc = account.trim().toLowerCase();
    final eid = settings.loginEnvId(acc);
    final body = <String, dynamic>{
      'account': acc,
      'passwd': password,
      'xxs': captchaId,
      'captcha': captchaText.trim(),
    };
    if (captchaText.trim().isEmpty && eid.isNotEmpty) body['eid'] = eid;
    final data = await api.command('POST', '/v0/auth/login', data: body);
    if (data is! Map || '${data['token'] ?? ''}'.isEmpty) {
      throw ApiException(FailKind.business, 'Login failed', code: 'LoginError');
    }
    settings.token = '${data['token']}';
    settings.account = acc;
    final newEid = '${data['loginEnvId'] ?? ''}';
    if (newEid.isNotEmpty) await settings.setLoginEnvId(acc, newEid);
    await loadUser();
  }

  Future<void> loadUser() async {
    final data = await api.query('/v0/auth/stat');
    if (data is Map) {
      user = UserInfo(Map<String, dynamic>.from(data));
      notifyListeners();
    }
    // reference data, best effort
    loadCustomers();
  }

  Future<void> loadCustomers() async {
    final cached = settings.readJson<Map>('customers');
    if (cached != null) {
      customers = cached.map((k, v) => MapEntry('$k', '$v'));
    }
    try {
      final data = await api.query('/v0/customer/opts');
      if (data is List) {
        final m = <String, String>{};
        for (final o in data) {
          if (o is Map && o['guid'] != null) {
            m['${o['guid']}'] = '${o['fullName'] ?? o['name'] ?? ''}';
          }
        }
        customers = m;
        await settings.writeJson('customers', m);
        notifyListeners();
      }
    } catch (_) {}
  }

  String customerName(String? guid) {
    if (guid == null || guid.isEmpty) return '';
    return customers[guid] ?? guid;
  }

  Future<void> logout() async {
    try {
      await api.query('/v0/auth/logout');
    } catch (_) {}
    clearLocal();
  }

  void clearLocal() {
    settings.token = '';
    user = null;
    notifyListeners();
  }
}
