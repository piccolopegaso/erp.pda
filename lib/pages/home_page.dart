import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/i18n.dart';
import '../ui/widgets.dart';
import 'history_page.dart';
import 'logging_scan_page.dart';
import 'login_page.dart';
import 'pallet_page.dart';
import 'pick_guide_page.dart';
import 'receiving_scan_page.dart';
import 'settings_page.dart';
import 'shipping_scan_page.dart';
import 'sn_swap_page.dart';
import 'stock_page.dart';

class _Module {
  const _Module(this.key, this.icon, this.color, this.builder);

  final String key;
  final IconData icon;
  final Color color;
  final WidgetBuilder builder;
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static final _sections = <String, List<_Module>>{
    'home.sectionOutbound': [
      _Module('mod.shipping', Icons.local_shipping, const Color(0xFF1565C0), (_) => const ShippingScanPage()),
      _Module('mod.pallet', Icons.view_in_ar, const Color(0xFF00838F), (_) => const PalletPage()),
      _Module('mod.pick', Icons.shopping_cart_checkout, const Color(0xFF2E7D32), (_) => const PickGuidePage()),
      _Module('mod.logging', Icons.fact_check, const Color(0xFF5D4037), (_) => const LoggingScanPage()),
    ],
    'home.sectionInbound': [
      _Module('mod.receiving', Icons.assignment_return, const Color(0xFFEF6C00), (_) => const ReceivingScanPage()),
      _Module('mod.snswap', Icons.qr_code_2, const Color(0xFF6A1B9A), (_) => const SnSwapPage()),
    ],
    'home.sectionStock': [
      _Module('mod.stock', Icons.inventory_2, const Color(0xFF283593), (_) => const StockPage()),
    ],
    'home.sectionOther': [
      _Module('mod.history', Icons.history, const Color(0xFF455A64), (_) => const HistoryPage()),
      _Module('mod.settings', Icons.settings, const Color(0xFF455A64), (_) => const SettingsPage()),
    ],
  };

  Future<void> _logout(BuildContext context) async {
    if (!await confirm(context, tr('home.logoutConfirm'), okText: tr('home.logout'))) return;
    if (!context.mounted) return;
    final app = AppScope.of(context);
    await app.session.logout();
    app.ws.close();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([app.settings, app.session]),
      builder: (context, _) {
        final user = app.session.user;
        final name = user == null ? app.settings.account : (user.name.isNotEmpty ? user.name : user.account);
        return Scaffold(
          appBar: AppBar(
            title: Text(tr('app.title')),
            actions: [
              const NetBadge(),
              IconButton(icon: const Icon(Icons.logout), tooltip: tr('home.logout'), onPressed: () => _logout(context)),
            ],
          ),
          body: Column(children: [
            const OfflineBanner(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 20),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                    child: Text(tr('home.hello', {'name': name}),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  ),
                  for (final sec in _sections.entries) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                      child: Text(tr(sec.key), style: const TextStyle(color: Color(0xFF666666), fontWeight: FontWeight.w600)),
                    ),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.55,
                      children: [for (final m in sec.value) _tile(context, m)],
                    ),
                  ],
                ],
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _tile(BuildContext context, _Module m) {
    return Material(
      color: m.color,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: m.builder)),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(m.icon, color: Colors.white, size: 30),
            const Spacer(),
            Text(tr(m.key), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            Text(tr('${m.key}.desc'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
          ]),
        ),
      ),
    );
  }
}
