import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../downloads.dart';
import '../home_config.dart';
import '../library.dart';
import '../models.dart';
import '../refresh.dart';
import '../store.dart';
import '../theme.dart';
import '../updater.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'customize_home_screen.dart';
import 'downloads_screen.dart';
import 'login_screen.dart';
import 'update_dialog.dart';
import 'stats_screen.dart';

class ProfileScreen extends StatefulWidget {
  final XtreamClient client;
  final VoidCallback onLogout;
  final void Function(XtreamCredentials) onSwitch;
  const ProfileScreen({super.key, required this.client, required this.onLogout, required this.onSwitch});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _info;
  List<XtreamCredentials> _profiles = [];

  @override
  void initState() {
    super.initState();
    widget.client.authenticate().then((i) {
      if (mounted) setState(() => _info = i);
    }).catchError((_) {});
    Store.savedProfiles().then((p) => mounted ? setState(() => _profiles = p) : null);
  }

  bool _isActive(XtreamCredentials p) =>
      p.baseUrl == widget.client.creds.baseUrl && p.username == widget.client.creds.username;

  Future<void> _addProfile() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LoginScreen(onLogin: (c) {
        Navigator.of(context).pop();
        widget.onSwitch(c); // login already set it active; rebuild with it
      }),
    ));
    final p = await Store.savedProfiles();
    if (mounted) setState(() => _profiles = p);
  }

  void _switch(XtreamCredentials p) {
    if (_isActive(p)) return;
    HapticFeedback.selectionClick();
    widget.onSwitch(p);
  }

  Future<void> _delete(XtreamCredentials p) async {
    final left = await Store.removeProfile(p);
    if (mounted) setState(() => _profiles = left);
  }

  Future<void> _clearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        title: const Text('Clear watch history?'),
        content: const Text('This removes Continue watching and Recently watched. Your favourites and downloads are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: muted))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: bg),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      Library.instance.clearHistory();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Watch history cleared'), duration: Duration(seconds: 2)));
    }
  }

  bool _checkingUpdate = false;
  Future<void> _checkForUpdates() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    final info = await Updater.instance.check();
    if (!mounted) return;
    setState(() => _checkingUpdate = false);
    if (info != null) {
      showUpdateFlow(context, info);
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('You’re on the latest (${Updater.instance.currentLabel}).'), duration: const Duration(seconds: 2)));
    }
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
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle, boxShadow: glow(accent)),
            child: const Icon(Icons.person_rounded, size: 46, color: Colors.white),
          ),
        ),
        const SizedBox(height: 14),
        Center(child: Text(c.username, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
        Center(
          child: Text(c.baseUrl.replaceFirst(RegExp(r'^https?://'), ''),
              style: TextStyle(color: subtle)),
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
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Row(
            children: [
              const Text('Profiles', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const Spacer(),
              GestureDetector(
                onTap: _addProfile,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_rounded, size: 18, color: accent),
                  const SizedBox(width: 4),
                  Text('Add', style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
              ),
            ],
          ),
        ),
        Glass(
          radius: 20,
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [
              for (var i = 0; i < _profiles.length; i++) ...[
                if (i > 0) _divider(),
                _profileRow(_profiles[i]),
              ],
              if (_profiles.isEmpty) _profileRow(widget.client.creds),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text('Home', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
        GestureDetector(
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => CustomizeHomeScreen(client: widget.client))),
          child: Glass(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            child: Row(children: [
              Icon(Icons.dashboard_customize_rounded, color: accent, size: 20),
              const SizedBox(width: 14),
              const Expanded(child: Text('Customize Home', style: TextStyle(fontWeight: FontWeight.w700))),
              AnimatedBuilder(
                animation: HomeConfig.instance,
                builder: (_, __) => Text(
                  HomeConfig.instance.isCustom ? '${HomeConfig.instance.shelves.length} shelves' : 'Default',
                  style: TextStyle(color: subtle, fontSize: 13),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: subtle),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () =>
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => StatsScreen(client: widget.client))),
          child: Glass(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            child: Row(children: [
              Icon(Icons.insights_rounded, color: accent, size: 20),
              const SizedBox(width: 14),
              const Expanded(child: Text('Your Lumen', style: TextStyle(fontWeight: FontWeight.w700))),
              Icon(Icons.chevron_right_rounded, color: subtle),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () =>
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => DownloadsScreen(client: widget.client))),
          child: Glass(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            child: Row(children: [
              Icon(Icons.download_rounded, color: accent, size: 20),
              const SizedBox(width: 14),
              const Expanded(child: Text('Downloads', style: TextStyle(fontWeight: FontWeight.w700))),
              AnimatedBuilder(
                animation: Downloads.instance,
                builder: (_, __) {
                  final n = Downloads.instance.completedCount;
                  return Text(n == 0 ? 'Offline' : '$n offline', style: TextStyle(color: subtle, fontSize: 13));
                },
              ),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () {
            refreshContent();
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('Refreshing content…'), duration: Duration(seconds: 2)));
          },
          child: Glass(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            child: Row(children: [
              Icon(Icons.refresh_rounded, color: accent, size: 20),
              const SizedBox(width: 14),
              const Expanded(child: Text('Refresh content', style: TextStyle(fontWeight: FontWeight.w700))),
              Text('Reload catalog', style: TextStyle(color: subtle, fontSize: 13)),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _checkForUpdates,
          child: Glass(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            child: Row(children: [
              Icon(Icons.system_update_rounded, color: accent, size: 20),
              const SizedBox(width: 14),
              const Expanded(child: Text('Check for updates', style: TextStyle(fontWeight: FontWeight.w700))),
              if (_checkingUpdate)
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: accent))
              else
                Text(Updater.instance.currentLabel, style: TextStyle(color: subtle, fontSize: 13)),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _clearHistory,
          child: Glass(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            child: Row(children: [
              Icon(Icons.history_rounded, color: accent, size: 20),
              const SizedBox(width: 14),
              const Expanded(child: Text('Clear watch history', style: TextStyle(fontWeight: FontWeight.w700))),
              Text('Continue & Recent', style: TextStyle(color: subtle, fontSize: 13)),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text('Appearance', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
        const _ThemeSelector(),
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
          Text(label, style: TextStyle(color: muted)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
  Widget _divider() => Divider(height: 1, color: line, indent: 12, endIndent: 12);

  Widget _profileRow(XtreamCredentials p) {
    final active = _isActive(p);
    final host = p.baseUrl.replaceFirst(RegExp(r'^https?://'), '');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _switch(p),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? accent : surfaceHi,
                shape: BoxShape.circle,
              ),
              child: Text(
                p.username.isNotEmpty ? p.username[0].toUpperCase() : '?',
                style: TextStyle(fontWeight: FontWeight.w800, color: active ? Colors.white : muted),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.username, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(host, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: subtle, fontSize: 12)),
                ],
              ),
            ),
            if (active)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
                child: Text('Active', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w700)),
              )
            else ...[
              Icon(Icons.swap_horiz_rounded, color: muted, size: 20),
              const SizedBox(width: 4),
              IconButton(
                onPressed: () => _delete(p),
                icon: Icon(Icons.delete_outline_rounded, color: subtle, size: 20),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Dark / Light / System segmented selector wired to ThemeController.
class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector();

  static const _opts = [
    (mode: ThemeMode.dark, icon: Icons.dark_mode_rounded, label: 'Dark'),
    (mode: ThemeMode.light, icon: Icons.light_mode_rounded, label: 'Light'),
    (mode: ThemeMode.system, icon: Icons.brightness_auto_rounded, label: 'System'),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance.mode,
      builder: (context, current, _) {
        return Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: surfaceHi.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(18)),
          child: Row(
            children: [
              for (final o in _opts)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => ThemeController.instance.set(o.mode),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: current == o.mode ? accent : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Icon(o.icon, size: 20, color: current == o.mode ? Colors.white : muted),
                          const SizedBox(height: 5),
                          Text(o.label,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: current == o.mode ? Colors.white : muted)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
