import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'catalog_cache.dart';
import 'epg_cache.dart';
import 'home_config.dart';
import 'models.dart';
import 'playback.dart';
import 'stats.dart';
import 'store.dart';
import 'library.dart';
import 'theme.dart';
import 'widgets.dart';
import 'xtream.dart';
import 'screens/login_screen.dart';
import 'screens/mini_player.dart';
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
          navigatorKey: rootNavKey,
          theme: buildTheme(lightPalette),
          darkTheme: buildTheme(darkPalette),
          themeMode: mode,
          // Flip instantly (no lerp) — our global palette getters switch at once,
          // and a non-const home forces the whole subtree to re-read them.
          themeAnimationDuration: Duration.zero,
          // Float the mini-player above every screen.
          builder: (context, child) => Stack(
            children: [
              child ?? const SizedBox.shrink(),
              const Positioned.fill(child: MiniPlayer()),
            ],
          ),
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
    HomeConfig.instance.load();
    WatchStats.instance.load();
    ThemeController.instance.load();
    Store.active().then((c) => setState(() {
          _creds = c;
          _loading = false;
        }));
  }

  XtreamClient? _client; // cached so theme rebuilds don't recreate it

  /// Make these credentials active: rebuild the client and drop cached catalogs.
  void _activate(XtreamCredentials c) => setState(() {
        _creds = c;
        _client = null;
        PlaybackController.instance.stop();
        CatalogCache.instance.clear();
        EpgCache.instance.clear();
      });

  void _onLogin(XtreamCredentials c) => _activate(c);

  Future<void> _switchTo(XtreamCredentials c) async {
    await Store.setActive(c);
    if (mounted) _activate(c);
  }

  void _onLogout() => setState(() {
        _creds = null;
        _client = null;
        PlaybackController.instance.stop();
        CatalogCache.instance.clear();
        EpgCache.instance.clear();
      });

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
        // Key by the active profile so switching fully remounts all tabs with
        // the new client (fresh catalogs), not stale data from the old account.
        return HomeShell(
          key: ValueKey('${_creds!.baseUrl}|${_creds!.username}'),
          client: _client!,
          onLogout: _onLogout,
          onSwitch: _switchTo,
        );
      },
    );
  }
}
