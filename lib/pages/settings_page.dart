import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/device.dart';
import '../core/i18n.dart';
import '../core/net_monitor.dart';
import '../core/settings.dart';
import '../ui/widgets.dart';
import 'login_page.dart';

const appVersion = '1.0.0';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Object? _scanToken;
  AppState? _app;
  String _testCode = '';
  Map<String, dynamic> _device = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scanToken == null) {
      final app = _app = AppScope.of(context);
      // scanner test area: this page swallows scans while it is visible
      _scanToken = app.scanner.register((code) {
        app.device.ok();
        setState(() => _testCode = code);
      }, isActive: () => mounted && (ModalRoute.of(context)?.isCurrent ?? false));
      app.device.info().then((v) => mounted ? setState(() => _device = v) : null);
    }
  }

  @override
  void dispose() {
    if (_scanToken != null) _app?.scanner.unregister(_scanToken!);
    super.dispose();
  }

  Future<void> _editText(String title, String initial, void Function(String) apply) async {
    final v = await askCode(context, title: title, initial: initial);
    if (v != null) apply(v);
  }

  Future<void> _editServer(AppSettings s) async {
    final v = await askCode(context, title: tr('set.server'), initial: s.server);
    if (v == null || v.isEmpty || v == s.server) return;
    s.server = v;
    if (!mounted) return;
    final app = AppScope.of(context);
    app.session.clearLocal();
    app.ws.close();
    toast(context, tr('set.serverChangedRelogin'));
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
  }

  Future<void> _applyScanner() async => AppScope.of(context).device.configureScanner();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.settings;
    return ListenableBuilder(
      listenable: Listenable.merge([s, app.net]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(tr('mod.settings'))),
        body: ListView(children: [
          // scanner test
          Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1565C0)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('set.test'), style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(_testCode.isEmpty ? '—' : tr('set.testResult', {'code': _testCode}),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ]),
          ),
          _header(tr('set.scanner')),
          ListTile(
            title: Text(tr('set.scannerMode')),
            subtitle: Text(_presetLabel(s.scannerPreset)),
            trailing: const Icon(Icons.arrow_drop_down),
            onTap: () async {
              final v = await showDialog<String>(
                context: context,
                builder: (ctx) => SimpleDialog(children: [
                  for (final e in {
                    'auto': tr('set.scannerAuto'),
                    for (final p in kScannerPresets) p.id: p.label,
                    'custom': tr('set.scannerCustom'),
                    'none': tr('set.scannerNone'),
                  }.entries)
                    SimpleDialogOption(onPressed: () => Navigator.pop(ctx, e.key), child: Text(e.value)),
                ]),
              );
              if (v != null) {
                s.scannerPreset = v;
                await _applyScanner();
              }
            },
          ),
          ListTile(
            title: Text(tr('set.customAction')),
            subtitle: Text(s.customAction.isEmpty ? '—' : s.customAction),
            onTap: () => _editText(tr('set.customAction'), s.customAction, (v) {
              s.customAction = v;
              _applyScanner();
            }),
          ),
          ListTile(
            title: Text(tr('set.customExtra')),
            subtitle: Text(s.customExtra.isEmpty ? '—' : s.customExtra),
            onTap: () => _editText(tr('set.customExtra'), s.customExtra, (v) {
              s.customExtra = v;
              _applyScanner();
            }),
          ),
          SwitchListTile(title: Text(tr('set.wedge')), value: s.wedgeEnabled, onChanged: (v) => s.wedgeEnabled = v),
          _header(tr('set.feedback')),
          SwitchListTile(title: Text(tr('set.sound')), value: s.sound, onChanged: (v) => s.sound = v),
          SwitchListTile(title: Text(tr('set.vibrate')), value: s.vibrate, onChanged: (v) => s.vibrate = v),
          SwitchListTile(
            title: Text(tr('set.keepScreenOn')),
            value: s.keepScreenOn,
            onChanged: (v) {
              s.keepScreenOn = v;
              app.device.keepScreenOn(v);
            },
          ),
          ListTile(
            title: Text(tr('set.testBeep')),
            trailing: Wrap(spacing: 4, children: [
              IconButton(onPressed: () => app.device.feedback(Beep.ok), icon: const Icon(Icons.check_circle, color: Colors.green)),
              IconButton(onPressed: () => app.device.feedback(Beep.warn), icon: const Icon(Icons.warning, color: Colors.orange)),
              IconButton(onPressed: () => app.device.feedback(Beep.error), icon: const Icon(Icons.cancel, color: Colors.red)),
            ]),
          ),
          _header(tr('set.language')),
          for (final e in supportedLanguages.entries)
            RadioListTile<String>(
              dense: true,
              value: e.key,
              groupValue: s.language,
              title: Text(e.value),
              onChanged: (v) => s.language = v ?? 'zh',
            ),
          _header(tr('set.network')),
          ListTile(
            title: Text(tr('set.server')),
            subtitle: Text(s.server),
            onTap: () => _editServer(s),
          ),
          ListTile(
            title: Text(tr('set.origin')),
            subtitle: Text(s.origin),
            onTap: () => _editText(tr('set.origin'), s.origin, (v) => s.origin = v),
          ),
          ListTile(
            title: Text(tr('set.connectTimeout')),
            trailing: _stepper(s.connectTimeout, 3, 30, (v) => s.connectTimeout = v),
          ),
          ListTile(
            title: Text(tr('set.receiveTimeout')),
            trailing: _stepper(s.receiveTimeout, 10, 90, (v) => s.receiveTimeout = v),
          ),
          ListTile(
            title: Text(switch (app.net.state) {
              NetState.good => tr('net.good'),
              NetState.slow => tr('net.slow'),
              NetState.offline => tr('net.offline'),
            }),
            subtitle: Text(tr('set.latency', {'ms': app.net.lastLatencyMs})),
            trailing: OutlinedButton(onPressed: app.net.probe, child: Text(tr('set.checkNow'))),
          ),
          _header(tr('set.about')),
          ListTile(title: Text(tr('set.version')), subtitle: Text(appVersion)),
          ListTile(
            title: Text(tr('set.device')),
            subtitle: Text(_device.isEmpty
                ? '—'
                : '${_device['manufacturer']} ${_device['model']} · Android ${_device['release']} (API ${_device['sdk']})'),
          ),
          const SizedBox(height: 30),
        ]),
      ),
    );
  }

  String _presetLabel(String id) {
    if (id == 'auto') return tr('set.scannerAuto');
    if (id == 'custom') return tr('set.scannerCustom');
    if (id == 'none') return tr('set.scannerNone');
    return kScannerPresets.firstWhere((p) => p.id == id, orElse: () => kScannerPresets.last).label;
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Text(t, style: const TextStyle(color: Color(0xFF1565C0), fontWeight: FontWeight.bold)),
      );

  Widget _stepper(int value, int min, int max, void Function(int) set) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(onPressed: value > min ? () => set(value - 1) : null, icon: const Icon(Icons.remove)),
        Text('$value', style: const TextStyle(fontSize: 16)),
        IconButton(onPressed: value < max ? () => set(value + 1) : null, icon: const Icon(Icons.add)),
      ]);
}
