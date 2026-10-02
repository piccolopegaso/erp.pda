import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/api.dart';
import 'core/app_state.dart';
import 'core/i18n.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'ui/el.dart';
import 'ui/relogin_dialog.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final app = await AppState.create();
  setLanguage(app.settings.language);
  app.scanner.start();
  await app.device.configureScanner();
  await app.device.keepScreenOn(app.settings.keepScreenOn);
  runApp(PdaApp(app: app));
}

class PdaApp extends StatefulWidget {
  const PdaApp({super.key, required this.app});

  final AppState app;

  @override
  State<PdaApp> createState() => _PdaAppState();
}

class _PdaAppState extends State<PdaApp> {
  bool _reloginOpen = false;

  @override
  void initState() {
    super.initState();
    widget.app.settings.addListener(_onSettings);
    widget.app.api.onAuthExpired = _onAuthExpired;
  }

  @override
  void dispose() {
    widget.app.settings.removeListener(_onSettings);
    super.dispose();
  }

  void _onSettings() {
    if (currentLanguage != widget.app.settings.language) {
      setLanguage(widget.app.settings.language);
      setState(() {});
    }
  }

  /// HTTP 403 anywhere: ask for the password in a dialog instead of throwing the
  /// operator out of the half-finished task.
  void _onAuthExpired() {
    if (_reloginOpen) return;
    final nav = navigatorKey.currentState;
    final ctx = navigatorKey.currentContext;
    if (nav == null || ctx == null) return;
    // already on the login page -> nothing to do
    if (!widget.app.session.loggedIn || widget.app.session.validating) return;
    _reloginOpen = true;
    scheduleMicrotask(() async {
      final ok = await showReloginDialog(ctx, widget.app);
      _reloginOpen = false;
      if (ok) {
        messengerKey.currentState?.showSnackBar(SnackBar(
          content: Text(tr('pda.login.renewed'), style: const TextStyle(fontSize: 15)),
          backgroundColor: El.warning,
          duration: const Duration(seconds: 5),
        ));
      } else {
        widget.app.session.clearLocal();
        nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: widget.app,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: messengerKey,
        title: 'MICLinker PDA',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: El.primary, primary: El.primary),
          scaffoldBackgroundColor: El.bg,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: El.textPrimary,
            surfaceTintColor: Colors.white,
            elevation: 0.5,
            shadowColor: Color(0x22000000),
            toolbarHeight: 48,
          ),
          textTheme: const TextTheme(bodyMedium: TextStyle(color: El.textRegular)),
          visualDensity: VisualDensity.compact,
          // old PDA GPUs: no fancy page transitions
          pageTransitionsTheme: const PageTransitionsTheme(builders: {
            TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          }),
        ),
        home: widget.app.session.loggedIn ? const _Startup() : const LoginPage(),
      ),
    );
  }
}

/// Validates a remembered token. Works offline: if the server is unreachable we still
/// go to the home screen (cached customer names etc.) and the first request will tell.
class _Startup extends StatefulWidget {
  const _Startup();

  @override
  State<_Startup> createState() => _StartupState();
}

class _StartupState extends State<_Startup> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final app = AppScope.of(context);
    var toLogin = false;
    app.session.validating = true;
    try {
      await app.session.loadUser();
    } on ApiException catch (e) {
      toLogin = e.kind == FailKind.auth;
    } catch (_) {
    } finally {
      app.session.validating = false;
    }
    if (!mounted) return;
    if (toLogin) app.session.clearLocal();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => toLogin ? const LoginPage() : const HomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
