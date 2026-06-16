import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';

class ProfileScreen extends StatefulWidget {
  final XtreamClient client;
  final VoidCallback onLogout;
  const ProfileScreen({super.key, required this.client, required this.onLogout});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _info;

  @override
  void initState() {
    super.initState();
    widget.client.authenticate().then((i) {
      if (mounted) setState(() => _info = i);
    }).catchError((_) {});
  }

  String _expiry() {
    final e = _info?['exp_date'];
    if (e == null || '$e' == 'null') return 'Unlimited';
    final secs = int.tryParse('$e');
    if (secs == null) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
    return '${d.day}/${d.month}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client.creds;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(gradient: accentGradient, shape: BoxShape.circle, boxShadow: glow(accent, a: 0.5)),
            child: const Icon(Icons.person_rounded, size: 46, color: Colors.white),
          ),
        ),
        const SizedBox(height: 14),
        Center(child: Text(c.username, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
        Center(
          child: Text(c.baseUrl.replaceFirst(RegExp(r'^https?://'), ''),
              style: const TextStyle(color: subtle)),
        ),
        const SizedBox(height: 24),
        Glass(
          radius: 20,
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [
              _row(Icons.workspace_premium_rounded, 'Status', '${_info?['status'] ?? '—'}'),
              _divider(),
              _row(Icons.event_rounded, 'Expires', _expiry()),
              _divider(),
              _row(Icons.devices_rounded, 'Connections',
                  _info == null ? '—' : '${_info!['active_cons'] ?? 0} / ${_info!['max_connections'] ?? 1}'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: widget.onLogout,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0x1AFF5277),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x33FF5277)),
            ),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.logout_rounded, color: Color(0xFFFF7A9A), size: 20),
              SizedBox(width: 8),
              Text('Sign out', style: TextStyle(color: Color(0xFFFF7A9A), fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _row(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(width: 14),
          Text(label, style: const TextStyle(color: muted)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
  Widget _divider() => Divider(height: 1, color: Colors.white.withValues(alpha: 0.06), indent: 12, endIndent: 12);
}
