import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/device.dart';
import '../core/i18n.dart';
import '../core/net_monitor.dart';
import '../core/settings.dart';
import '../ui/el.dart';
import '../ui/widgets.dart';
import 'login_page.dart';

const appVersion = '0.0.2';

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
  String _printTest = '';
  bool _printBusy = false;

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
    final v = await askCode(context, title: tr('pda.set.server'), initial: s.server);
    if (v == null || v.isEmpty || v == s.server) return;
    s.server = v;
    if (!mounted) return;
    final app = AppScope.of(context);
    app.session.clearLocal();
    app.ws.close();
    toast(context, tr('pda.set.serverChanged'));
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
  }

  Future<void> _choosePrinter() async {
    final app = AppScope.of(context);
    setState(() {
      _printBusy = true;
      _printTest = '';
    });
    try {
      final list = await app.printer.printers();
      if (!mounted) return;
      final v = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(tr('pda.set.printer')),
          children: [for (final p in list) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, p), child: Text(p))],
        ),
      );
      if (v != null) app.settings.printer = v;
      setState(() => _printTest = tr('pda.set.printerOk', {'n': list.length}));
    } catch (e) {
      setState(() => _printTest = tr('pda.print.failed', {'msg': '$e'}));
    } finally {
      if (mounted) setState(() => _printBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.settings;
    return ListenableBuilder(
      listenable: Listenable.merge([s, app.net]),
      builder: (context, _) => Scaffold(
        appBar: elAppBar(tr('common.settings')),
        body: ListView(children: [
          Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFECF5FF),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFB3D8FF)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('pda.set.test'), style: const TextStyle(fontWeight: FontWeight.w600, color: El.primary)),
              const SizedBox(height: 4),
              Text(_testCode.isEmpty ? '—' : _testCode, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ]),
          ),
          _header(tr('pda.set.printStation')),
          ListTile(
            dense: true,
            title: Text(tr('pda.set.printHost')),
            subtitle: Text(s.printHost.isEmpty ? tr('pda.print.notConfigured') : s.printBridgeUrl),
            onTap: () => _editText(tr('pda.set.printHost'), s.printHost, (v) => s.printHost = v),
          ),
          ListTile(
            dense: true,
            title: Text(tr('pda.set.printer')),
            subtitle: Text(s.printer.isEmpty ? '—' : s.printer),
            trailing: _printBusy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.arrow_drop_down),
            onTap: s.printHost.isEmpty || _printBusy ? null : _choosePrinter,
          ),
          if (_printTest.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_printTest, style: const TextStyle(fontSize: 12.5, color: El.textRegular)),
            ),
          _header(tr('pda.set.scanner')),
          ListTile(
            dense: true,
            title: Text(tr('pda.set.scannerMode')),
            subtitle: Text(_presetLabel(s.scannerPreset)),
            trailing: const Icon(Icons.arrow_drop_down),
            onTap: () async {
              final v = await showDialog<String>(
                context: context,
                builder: (ctx) => SimpleDialog(children: [
                  for (final e in {
                    'auto': tr('pda.set.scannerAuto'),
                    for (final p in kScannerPresets) p.id: p.label,
                    'custom': tr('pda.set.scannerCustom'),
                    'none': tr('pda.set.scannerNone'),
                  }.entries)
                    SimpleDialogOption(onPressed: () => Navigator.pop(ctx, e.key), child: Text(e.value)),
                ]),
              );
              if (v != null) {
                s.scannerPreset = v;
                await app.device.configureScanner();
              }
            },
          ),
          ListTile(
            dense: true,
            title: Text(tr('pda.set.customAction')),
            subtitle: Text(s.customAction.isEmpty ? '—' : s.customAction),
            onTap: () => _editText(tr('pda.set.customAction'), s.customAction, (v) {
              s.customAction = v;
              app.device.configureScanner();
            }),
          ),
          ListTile(
            dense: true,
            title: Text(tr('pda.set.customExtra')),
            subtitle: Text(s.customExtra.isEmpty ? '—' : s.customExtra),
            onTap: () => _editText(tr('pda.set.customExtra'), s.customExtra, (v) {
              s.customExtra = v;
              app.device.configureScanner();
            }),
          ),
          SwitchListTile(dense: true, title: Text(tr('pda.set.wedge')), value: s.wedgeEnabled, onChanged: (v) => s.wedgeEnabled = v),
          _header(tr('pda.set.feedback')),
          SwitchListTile(dense: true, title: Text(tr('pda.set.sound')), value: s.sound, onChanged: (v) => s.sound = v),
          SwitchListTile(dense: true, title: Text(tr('pda.set.vibrate')), value: s.vibrate, onChanged: (v) => s.vibrate = v),
          SwitchListTile(
            dense: true,
            title: Text(tr('pda.set.keepScreenOn')),
            value: s.keepScreenOn,
            onChanged: (v) {
              s.keepScreenOn = v;
              app.device.keepScreenOn(v);
            },
          ),
          ListTile(
            dense: true,
            title: Text(tr('pda.set.testBeep')),
            trailing: Wrap(children: [
              IconButton(onPressed: () => app.device.feedback(Beep.ok), icon: const Icon(Icons.check_circle, color: El.success)),
              IconButton(onPressed: () => app.device.feedback(Beep.warn), icon: const Icon(Icons.warning, color: El.warning)),
              IconButton(onPressed: () => app.device.feedback(Beep.error), icon: const Icon(Icons.cancel, color: El.danger)),
            ]),
          ),
          _header(tr('pda.set.language')),
          for (final e in supportedLanguages.entries)
            RadioListTile<String>(
              dense: true,
              value: e.key,
              groupValue: s.language,
              title: Text(e.value),
              onChanged: (v) => s.language = v ?? 'en',
            ),
          _header(tr('pda.set.network')),
          ListTile(dense: true, title: Text(tr('pda.set.server')), subtitle: Text(s.server), onTap: () => _editServer(s)),
          ListTile(
            dense: true,
            title: const Text('CarrierGate'),
            subtitle: Text(s.cgServer),
            onTap: () => _editText('CarrierGate', s.cgServer, (v) => s.cgServer = v),
          ),
          ListTile(
            dense: true,
            title: Text(tr('pda.set.origin')),
            subtitle: Text(s.origin),
            onTap: () => _editText(tr('pda.set.origin'), s.origin, (v) => s.origin = v),
          ),
          ListTile(dense: true, title: Text(tr('pda.set.connectTimeout')), trailing: _stepper(s.connectTimeout, 3, 30, (v) => s.connectTimeout = v)),
          ListTile(dense: true, title: Text(tr('pda.set.receiveTimeout')), trailing: _stepper(s.receiveTimeout, 10, 90, (v) => s.receiveTimeout = v)),
          ListTile(
            dense: true,
            title: Text(switch (app.net.state) {
              NetState.good => tr('pda.net.good'),
              NetState.slow => tr('pda.net.slowShort'),
              NetState.offline => tr('pda.net.offlineShort'),
            }),
            subtitle: Text('${app.net.lastLatencyMs} ms'),
            trailing: OutlinedButton(onPressed: app.net.probe, child: Text(tr('pda.set.checkNow'))),
          ),
          _header(tr('pda.set.about')),
          const ListTile(dense: true, title: Text('Version'), subtitle: Text(appVersion)),
          ListTile(
            dense: true,
            title: Text(tr('pda.set.device')),
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
    if (id == 'auto') return tr('pda.set.scannerAuto');
    if (id == 'custom') return tr('pda.set.scannerCustom');
    if (id == 'none') return tr('pda.set.scannerNone');
    return kScannerPresets.firstWhere((p) => p.id == id, orElse: () => kScannerPresets.last).label;
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 2),
        child: Text(t, style: const TextStyle(color: El.primary, fontWeight: FontWeight.bold, fontSize: 13.5)),
      );

  Widget _stepper(int value, int min, int max, void Function(int) set) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(onPressed: value > min ? () => set(value - 1) : null, icon: const Icon(Icons.remove)),
        Text('$value', style: const TextStyle(fontSize: 15)),
        IconButton(onPressed: value < max ? () => set(value + 1) : null, icon: const Icon(Icons.add)),
      ]);
}
