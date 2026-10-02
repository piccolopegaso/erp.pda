import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/i18n.dart';
import 'login_form.dart';

/// Returns true when the operator signed in again (the page underneath keeps its state).
Future<bool> showReloginDialog(BuildContext context, AppState app) async {
  final r = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(tr('login.relogin')),
      scrollable: true,
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('login.reloginHint')),
          const SizedBox(height: 12),
          LoginForm(lockAccount: true, onSuccess: () => Navigator.of(ctx).pop(true)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('login.toLoginPage'))),
      ],
    ),
  );
  return r ?? false;
}
