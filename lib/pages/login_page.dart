import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/i18n.dart';
import '../ui/login_form.dart';
import '../ui/widgets.dart';
import 'home_page.dart';
import '../ui/el.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  int _formKey = 0;

  Future<void> _editServer() async {
    final s = AppScope.of(context).settings;
    final v = await askCode(context, title: tr('pda.set.server'), initial: s.server);
    if (v != null && v.isNotEmpty && v != s.server) {
      s.server = v;
      setState(() => _formKey++); // new captcha from the new server
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).settings;
    return ListenableBuilder(listenable: s, builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Text('MICLinker PDA'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.language),
            onSelected: (v) => s.language = v,
            itemBuilder: (_) => [
              for (final e in supportedLanguages.entries) PopupMenuItem(value: e.key, child: Text(e.value)),
            ],
          ),
          const NetBadge(),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 8),
            const Icon(Icons.warehouse_rounded, size: 64, color: El.primary),
            const SizedBox(height: 8),
            Center(child: Text(tr('common.login'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
            const SizedBox(height: 20),
            LoginForm(
              key: ValueKey(_formKey),
              onSuccess: () {
                Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
              },
            ),
            const SizedBox(height: 24),
            ListTile(
              dense: true,
              leading: const Icon(Icons.dns),
              title: Text(tr('pda.set.server')),
              subtitle: Text(s.server),
              onTap: _editServer,
            ),
          ],
        ),
      ),
    ));
  }
}
