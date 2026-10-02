import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../core/app_state.dart';
import '../core/i18n.dart';
import '../ui/el.dart';
import '../ui/widgets.dart';
import 'history_page.dart';
import 'logging_scan_page.dart';
import 'login_page.dart';
import 'pallet_page.dart';
import 'picklist/picklist_page.dart';
import 'rma/rma_page.dart';
import 'settings_page.dart';
import 'shipping_scan_page.dart';
import 'sn_swap_page.dart';
import 'stock_page.dart';

class _Menu {
  const _Menu(this.title, this.icon, this.builder);

  final String Function() title;
  final IconData icon;
  final WidgetBuilder builder;
}

/// Same menu names and icons as the web sidebar (router/modules/warehouseEp.js, wms.js).
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static final _groups = <String Function(), List<_Menu>>{
    () => 'Warehouse EP': [
      _Menu(() => tr('wms.picklist'), FontAwesomeIcons.dolly, (_) => const PicklistPage()),
      _Menu(() => tr('wms.shippingScan'), FontAwesomeIcons.truckRampBox, (_) => const ShippingScanPage()),
      _Menu(() => tr('wms.palletHandover'), FontAwesomeIcons.pallet, (_) => const PalletPage()),
      _Menu(() => tr('wms.loggingScan'), FontAwesomeIcons.personDotsFromLine, (_) => const LoggingScanPage()),
      _Menu(() => tr('wms.snScan'), FontAwesomeIcons.barcode, (_) => const SnSwapPage()),
      _Menu(() => tr('common.rma'), FontAwesomeIcons.parachuteBox, (_) => const RmaPage()),
    ],
    () => tr('wms.wms'): [
      _Menu(() => tr('wms.inventory'), FontAwesomeIcons.boxesStacked, (_) => const StockPage()),
    ],
    () => 'PDA': [
      _Menu(() => tr('pda.history'), FontAwesomeIcons.clockRotateLeft, (_) => const HistoryPage()),
      _Menu(() => tr('common.settings'), FontAwesomeIcons.gear, (_) => const SettingsPage()),
    ],
  };

  Future<void> _logout(BuildContext context) async {
    if (!await confirm(context, tr('pda.logoutConfirm'), okText: tr('common.logout'))) return;
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
          backgroundColor: El.sidebar,
          appBar: AppBar(
            backgroundColor: El.sidebar,
            foregroundColor: Colors.white,
            title: const Text('MICLinker PDA', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            actions: [
              const NetBadge(),
              IconButton(icon: const Icon(Icons.logout), tooltip: tr('common.logout'), onPressed: () => _logout(context)),
            ],
          ),
          body: Column(children: [
            const OfflineBanner(),
            Container(
              width: double.infinity,
              color: El.sidebarSub,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(children: [
                const Icon(Icons.account_circle, color: Color(0xFFBFCBD9), size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(name, style: const TextStyle(color: Color(0xFFBFCBD9)), overflow: TextOverflow.ellipsis)),
              ]),
            ),
            Expanded(
              child: ListView(children: [
                for (final g in _groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(g.key(), style: const TextStyle(color: Color(0xFF8391A5), fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                  for (final m in g.value)
                    Material(
                      color: El.sidebar,
                      child: InkWell(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: m.builder)),
                        child: Container(
                          height: 50,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(children: [
                            SizedBox(width: 24, child: FaIcon(m.icon, size: 17, color: const Color(0xFFBFCBD9))),
                            const SizedBox(width: 14),
                            Expanded(child: Text(m.title(), style: const TextStyle(color: Color(0xFFBFCBD9), fontSize: 15.5))),
                            const Icon(Icons.chevron_right, color: Color(0xFF5A6B80), size: 20),
                          ]),
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 20),
              ]),
            ),
          ]),
        );
      },
    );
  }
}
