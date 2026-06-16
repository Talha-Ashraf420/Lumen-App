import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'models.dart';
import 'store.dart';
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
    return MaterialApp(
      title: 'Lumen',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const _Gate(),
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
    Store.active().then((c) => setState(() {
          _creds = c;
          _loading = false;
        }));
  }

  void _onLogin(XtreamCredentials c) => setState(() => _creds = c);
  void _onLogout() => setState(() => _creds = null);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: BrandedLoading(background: true));
    }
    if (_creds == null) return LoginScreen(onLogin: _onLogin);
    return HomeShell(client: XtreamClient(_creds!), onLogout: _onLogout);
  }
}
