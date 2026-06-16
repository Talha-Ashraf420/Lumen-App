import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'catalog_cache.dart';
import 'epg_cache.dart';
import 'models.dart';
import 'store.dart';
import 'library.dart';
import 'theme.dart';
import 'widgets.dart';
import 'xtream.dart';
import 'screens/login_screen.dart';
import 'screens/shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized(); // libmpv — native TS/MKV/HLS playback

  // Never show a blank/white error screen — paint errors on the dark canvas.
  ErrorWidget.builder = (details) => Container(
        color: bg,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Text(
          details.exceptionAsString(),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFFF8FA3), fontSize: 13),
        ),
      );

  runApp(const LumenApp());
}

class LumenApp extends StatelessWidget {
  const LumenApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance.mode,
      builder: (context, mode, _) {
        // Resolve & publish the active palette for this build (used by the
        // theme-aware colour getters across the app).
        final platform = MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.dark;
        resolvePalette(mode, platform);
        return MaterialApp(
          title: 'Lumen',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(lightPalette),
          darkTheme: buildTheme(darkPalette),
          themeMode: mode,
          // Flip instantly (no lerp) — our global palette getters switch at once,
          // and a non-const home forces the whole subtree to re-read them.
          themeAnimationDuration: Duration.zero,
          home: _Gate(),
        );
      },
    );
  }
}

/// Decides login vs main shell based on stored credentials.
class _Gate extends StatefulWidget {
  const _Gate();
  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  XtreamCredentials? _creds;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Library.instance.load();
    ThemeController.instance.load();
    Store.active().then((c) => setState(() {
          _creds = c;
          _loading = false;
        }));
  }

  void _onLogin(XtreamCredentials c) => setState(() => _creds = c);
  void _onLogout() => setState(() {
        _creds = null;
        _client = null;
        CatalogCache.instance.clear();
        EpgCache.instance.clear();
      });

  XtreamClient? _client; // cached so theme rebuilds don't recreate it

  @override
  Widget build(BuildContext context) {
    // Set the active palette and build the screens in ONE builder, below the
    // Navigator route — so a theme change rebuilds this subtree and the new
    // palette is published immediately before the screens read it.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance.mode,
      builder: (context, mode, _) {
        resolvePalette(mode, MediaQuery.platformBrightnessOf(context));
        if (_loading) {
          return const Scaffold(body: BrandedLoading(background: true));
        }
        if (_creds == null) return LoginScreen(onLogin: _onLogin);
        _client ??= XtreamClient(_creds!);
        return HomeShell(client: _client!, onLogout: _onLogout);
      },
    );
  }
}
