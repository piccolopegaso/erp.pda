import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/i18n.dart';
import '../core/session.dart';
import 'widgets.dart';

/// Account + password (+ captcha when the device is not yet trusted by the server).
class LoginForm extends StatefulWidget {
  const LoginForm({super.key, required this.onSuccess, this.lockAccount = false});

  final VoidCallback onSuccess;

  /// Re-login dialog: the account cannot change (keeps the operator's open task consistent).
  final bool lockAccount;

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _account = TextEditingController();
  final _password = TextEditingController();
  final _captcha = TextEditingController();
  CaptchaChallenge? _challenge;
  bool _needCaptcha = true;
  bool _loading = false;
  bool _showPwd = false;
  String _error = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_account.text.isEmpty) {
      _account.text = AppScope.of(context).settings.account;
      _prepare();
    }
  }

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    _captcha.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final session = AppScope.of(context).session;
    final acc = _account.text.trim();
    final skip = acc.isNotEmpty && await session.canSkipCaptcha(acc);
    if (!mounted) return;
    setState(() => _needCaptcha = !skip);
    await _refreshCaptcha();
  }

  Future<void> _refreshCaptcha() async {
    try {
      final c = await AppScope.of(context).session.captcha();
      if (!mounted) return;
      setState(() {
        _challenge = c;
        _captcha.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorText(e));
    }
  }

  Future<void> _submit() async {
    if (_loading) return;
    final acc = _account.text.trim();
    final pwd = _password.text;
    if (acc.isEmpty || pwd.isEmpty || (_needCaptcha && _captcha.text.trim().isEmpty)) {
      setState(() => _error = tr('login.required'));
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    final app = AppScope.of(context);
    try {
      if (_challenge == null) await _refreshCaptcha();
      await app.session.login(
        account: acc,
        password: pwd,
        captchaId: _challenge?.id ?? '',
        captchaText: _needCaptcha ? _captcha.text : '',
      );
      if (!mounted) return;
      widget.onSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = tr('login.failed', {'msg': errorText(e)}));
      app.device.error();
      // a captcha is single-use; also re-check whether this device is still trusted
      _needCaptcha = true;
      await _refreshCaptcha();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _account,
          enabled: !widget.lockAccount,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(labelText: tr('login.account'), prefixIcon: const Icon(Icons.person)),
          onEditingComplete: _prepare,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _password,
          obscureText: !_showPwd,
          decoration: InputDecoration(
            labelText: tr('login.password'),
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              icon: Icon(_showPwd ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showPwd = !_showPwd),
            ),
          ),
          onSubmitted: (_) => _needCaptcha ? null : _submit(),
        ),
        if (_needCaptcha) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _captcha,
                autocorrect: false,
                decoration: InputDecoration(labelText: tr('login.captcha'), prefixIcon: const Icon(Icons.verified_user)),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _refreshCaptcha,
              child: Container(
                width: 120,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(border: Border.all(color: Colors.black26)),
                child: _challenge == null || _challenge!.imageBase64.isEmpty
                    ? Text(tr('login.captchaTap'), style: const TextStyle(fontSize: 11))
                    : Image.memory(base64Decode(_challenge!.imageBase64), fit: BoxFit.contain, gaplessPlayback: true),
              ),
            ),
          ]),
        ],
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(_error, style: const TextStyle(color: Color(0xFFC62828))),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _loading ? null : _submit,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: _loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text(tr('login.submit'), style: const TextStyle(fontSize: 17)),
        ),
      ],
    );
  }
}
