import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'catalog_cache.dart';
import 'demo_catalog.dart';
import 'downloads.dart';
import 'device_profile.dart';
import 'epg_cache.dart';
import 'home_config.dart';
import 'models.dart';
import 'playback.dart';
import 'session.dart';
import 'split.dart';
import 'stats.dart';
import 'store.dart';
import 'library.dart';
import 'legal.dart';
import 'theme.dart';
import 'xtream.dart';
import 'screens/login_screen.dart';
import 'screens/legal_screen.dart';
import 'screens/player_host.dart';
import 'screens/shell.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DeviceProfile.detect();
  // Catalog artwork is decoded to tile-sized buffers. Keep a generous but
  // bounded cache so large libraries cannot crowd video playback out of RAM.
  final imageCache = PaintingBinding.instance.imageCache;
  if (!kIsWeb && Platform.isAndroid) {
    imageCache.maximumSize = DeviceProfile.isTelevision ? 220 : 400;
    imageCache.maximumSizeBytes =
        (DeviceProfile.isTelevision ? 64 : 128) * 1024 * 1024;
  } else {
    imageCache.maximumSize = 700;
    imageCache.maximumSizeBytes = 224 * 1024 * 1024;
  }
  // Desktop: enable window control (used for real fullscreen in the player).
  if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    await windowManager.ensureInitialized();
  }
  MediaKit.ensureInitialized(); // libmpv — native TS/MKV/HLS playback
  final startup = DemoCatalog.preparePlayback();

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

  runApp(LumenApp(startup: startup));
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => PlaybackController.instance.prewarm(),
  );
}

class LumenApp extends StatelessWidget {
  const LumenApp({
    super.key,
    this.startup,
    this.minimumSplashDuration = const Duration(milliseconds: 1850),
  });

  final Future<void>? startup;
  final Duration minimumSplashDuration;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      // Rebuild on theme-mode AND accent-colour changes.
      animation: ThemeController.instance.listenable,
      builder: (context, _) {
        final mode = ThemeController.instance.mode.value;
        final accent = ThemeController.instance.accent.value;
        // Resolve & publish the active palette for this build (used by the
        // theme-aware colour getters across the app).
        final platform =
            MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.dark;
        resolvePalette(mode, platform);
        return MaterialApp(
          title: 'Lumen',
          debugShowCheckedModeBanner: false,
          navigatorKey: rootNavKey,
          theme: buildTheme(lightPaletteFor(accent)),
          darkTheme: buildTheme(darkPaletteFor(accent)),
          themeMode: mode,
          // Flip instantly (no lerp) — our global palette getters switch at once,
          // and a non-const home forces the whole subtree to re-read them.
          themeAnimationDuration: Duration.zero,
          // The player floats above every screen (full-screen or docked mini).
          // A bare Overlay (+ Material) gives the controls an Overlay (seek
          // slider) and a text style, while passing clicks through wherever the
          // player isn't painting — so the app stays interactive (e.g. while the
          // mini is docked).
          builder: (context, child) => AnimatedBuilder(
            animation: PlaybackController.instance,
            child: Stack(
              children: [
                child ?? const SizedBox.shrink(),
                Positioned.fill(
                  child: Material(
                    type: MaterialType.transparency,
                    child: Overlay(
                      initialEntries: [
                        OverlayEntry(
                          maintainState: true,
                          opaque: false,
                          builder: (_) => PlayerHost.overlay(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            builder: (context, stack) {
              final playback = PlaybackController.instance;
              final playerOwnsBack = playback.hasMedia && !playback.minimized;
              return PopScope(
                canPop: !playerOwnsBack,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) PlayerHost.handleSystemBack();
                },
                child: stack!,
              );
            },
          ),
          home: LaunchGate(
            startup: startup,
            minimumDuration: minimumSplashDuration,
            child: const SessionGate(),
          ),
        );
      },
    );
  }
}

/// Decides login vs main shell based on stored credentials.
typedef ProfileStateActivator =
    Future<void> Function(XtreamCredentials? credentials);

class SessionGate extends StatefulWidget {
  final ProfileStateActivator? profileActivator;

  const SessionGate({super.key, this.profileActivator});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  XtreamCredentials? _creds;
  bool _legalAccepted = false;
  bool _loading = true;
  String _loadingLabel = 'RESTORING YOUR SESSION';
  int _sessionChange = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final values = await Future.wait<dynamic>([
      Store.active(),
      LegalAcceptance.isAccepted(),
      ThemeController.instance.load(),
    ]);
    final credentials = values[0] as XtreamCredentials?;
    final profileState = _activateProfileState(credentials);
    if (!mounted) return;
    setState(() {
      _creds = credentials;
      _legalAccepted = values[1] as bool;
      _loading = false;
    });
    unawaited(_guardProfileState(profileState));
  }

  Future<void> _acceptLegal() async {
    await LegalAcceptance.accept();
    if (mounted) setState(() => _legalAccepted = true);
  }

  XtreamClient? _client; // cached so theme rebuilds don't recreate it

  Future<void> _activateProfileState(XtreamCredentials? credentials) {
    final override = widget.profileActivator;
    if (override != null) return override(credentials);
    return Future.wait([
      Library.instance.activate(credentials),
      HomeConfig.instance.activate(credentials),
      WatchStats.instance.activate(credentials),
      Downloads.instance.activate(credentials),
    ]);
  }

  Future<void> _guardProfileState(Future<void> activation) async {
    try {
      await activation;
    } catch (error, stack) {
      debugPrint('Profile state hydration failed: $error\n$stack');
    }
  }

  /// Make these credentials active: stop account-bound work, atomically switch
  /// persisted state, then rebuild with a fresh client and catalog namespace.
  void _activate(XtreamCredentials? credentials) {
    ++_sessionChange;
    final previousClient = _client;

    // Commit the authenticated session first. Cleanup and profile hydration
    // must never be able to strand a successfully saved account on Login.
    if (!mounted) return;
    setState(() {
      _creds = credentials;
      _client = null;
      _loading = false;
    });

    _guardSessionStep('previous client', () => previousClient?.close());
    activeClient = null;
    _guardSessionStep('playback', PlaybackController.instance.stop);
    unawaited(_guardProfileState(SplitController.instance.close()));
    _guardSessionStep('catalog cache', CatalogCache.instance.clear);
    _guardSessionStep('EPG cache', EpgCache.instance.clear);

    // Each controller clears its previous profile synchronously before its
    // first await. Let slower secure-storage and download-folder hydration
    // finish behind Home instead of trapping the user on a loading screen.
    unawaited(
      _guardProfileState(
        Future<void>.sync(() => _activateProfileState(credentials)),
      ),
    );
  }

  void _guardSessionStep(String label, void Function() action) {
    try {
      action();
    } catch (error, stack) {
      debugPrint('Session $label cleanup failed: $error\n$stack');
    }
  }

  void _onLogin(XtreamCredentials c) {
    _activate(c);
  }

  Future<void> _switchTo(XtreamCredentials c) async {
    await Store.setActive(c);
    if (mounted) _activate(c);
  }

  Future<void> _onLogout() async {
    final change = ++_sessionChange;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadingLabel = 'SIGNING OUT SECURELY';
      });
    }
    try {
      await Store.logout().timeout(const Duration(seconds: 6));
    } catch (_) {
      if (mounted && change == _sessionChange) {
        setState(() => _loading = false);
      }
      rethrow;
    }

    _client?.close();
    activeClient = null;
    PlaybackController.instance.stop();
    SplitController.instance.close();
    CatalogCache.instance.clear();
    EpgCache.instance.clear();
    if (!mounted || change != _sessionChange) return;

    // Every account-bound controller clears its in-memory view synchronously,
    // then completes any slower download persistence in the background. Move
    // to Login immediately so sign-out never appears stuck behind that work.
    final clearProfileState = _activateProfileState(null);
    setState(() {
      _creds = null;
      _client = null;
      _loading = false;
    });
    unawaited(clearProfileState);
  }

  @override
  void dispose() {
    _client?.close();
    if (identical(activeClient, _client)) activeClient = null;
    super.dispose();
  }

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
          return SessionLoading(message: _loadingLabel);
        }
        if (!_legalAccepted) {
          return LegalWelcomeScreen(onAccepted: _acceptLegal);
        }
        if (_creds == null) return LoginScreen(onLogin: _onLogin);
        _client ??= XtreamClient(_creds!);
        activeClient = _client; // expose to the app-level player (split picker)
        // Key by the active profile so switching fully remounts all tabs with
        // the new client (fresh catalogs), not stale data from the old account.
        return HomeShell(
          key: ValueKey(Store.profileScope(_creds!)),
          client: _client!,
          onLogout: _onLogout,
          onSwitch: _switchTo,
        );
      },
    );
  }
}
