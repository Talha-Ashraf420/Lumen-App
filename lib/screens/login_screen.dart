import 'package:flutter/material.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../xtream.dart';

class LoginScreen extends StatefulWidget {
  final void Function(XtreamCredentials) onLogin;
  const LoginScreen({super.key, required this.onLogin});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;
  List<XtreamCredentials> _profiles = [];

  @override
  void initState() {
    super.initState();
    Store.savedProfiles().then((p) => setState(() => _profiles = p));
  }

  Future<void> _connect(XtreamCredentials c) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await XtreamClient(c).authenticate();
      await Store.setActive(c);
      if (mounted) widget.onLogin(c);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ambient glow
          Positioned(
            top: -120,
            left: -80,
            child: _blob(accent.withValues(alpha: 0.18), 320),
          ),
          Positioned(bottom: -100, right: -60, child: _blob(accent2.withValues(alpha: 0.12), 280)),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [accent, accent2]),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.4), blurRadius: 30)],
                      ),
                      child: Icon(Icons.play_arrow_rounded, color: bg, size: 38),
                    ),
                    const SizedBox(height: 16),
                    const Text('Lumen', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Sign in with your Xtream / X3U codes.',
                        style: TextStyle(color: muted)),
                    const SizedBox(height: 24),
                    if (_profiles.isNotEmpty) ...[
                      ..._profiles.map((p) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ProfileTile(profile: p, busy: _busy, onTap: () => _connect(p)),
                          )),
                      Divider(height: 28, color: line),
                    ],
                    _field(_url, 'Server URL', hint: 'http://host:8080'),
                    const SizedBox(height: 12),
                    _field(_user, 'Username'),
                    const SizedBox(height: 12),
                    _field(_pass, 'Password', obscure: true),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12)),
                        child: Text(_error!, style: const TextStyle(color: Color(0xFFFFB4B4))),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: bg,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _busy
                            ? null
                            : () => _connect(XtreamCredentials(
                                  baseUrl: normalizeBaseUrl(_url.text),
                                  username: _user.text.trim(),
                                  password: _pass.text.trim(),
                                )),
                        child: _busy
                            ? SizedBox(
                                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: bg))
                            : const Text('Connect', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('Credentials are stored only on this device.',
                        style: TextStyle(color: subtle, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {String? hint, bool obscure = false}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(labelText: label, hintText: hint),
    );
  }

  Widget _blob(Color color, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      );
}

class _ProfileTile extends StatelessWidget {
  final XtreamCredentials profile;
  final bool busy;
  final VoidCallback onTap;
  const _ProfileTile({required this.profile, required this.busy, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        onTap: busy ? null : onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Icon(Icons.tv_rounded, color: accent),
        title: Text(profile.username, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(profile.baseUrl.replaceFirst(RegExp(r'^https?://'), ''),
            style: TextStyle(color: subtle)),
        trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: subtle),
      ),
    );
  }
}
