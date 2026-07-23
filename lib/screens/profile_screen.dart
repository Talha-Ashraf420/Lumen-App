import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../downloads.dart';
import '../home_config.dart';
import '../library.dart';
import '../legal.dart';
import '../models.dart';
import '../refresh.dart';
import '../responsive.dart';
import '../store.dart';
import '../theme.dart';
import '../updater.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'customize_home_screen.dart';
import 'downloads_screen.dart';
import 'login_screen.dart';
import 'legal_screen.dart';
import 'update_dialog.dart';
import 'stats_screen.dart';

class ProfileScreen extends StatefulWidget {
  final XtreamClient client;
  final VoidCallback onLogout;
  final void Function(XtreamCredentials) onSwitch;
  const ProfileScreen({
    super.key,
    required this.client,
    required this.onLogout,
    required this.onSwitch,
  });
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _info;
  List<XtreamCredentials> _profiles = [];
  bool _accountInfoLoading = true;

  @override
  void initState() {
    super.initState();
    widget.client
        .authenticate()
        .then((i) {
          if (mounted) {
            setState(() {
              _info = i;
              _accountInfoLoading = false;
            });
          }
        })
        .catchError((_) {
          if (mounted) setState(() => _accountInfoLoading = false);
        });
    Store.savedProfiles().then(
      (p) => mounted ? setState(() => _profiles = p) : null,
    );
  }

  bool _isActive(XtreamCredentials p) =>
      Store.sameProfile(p, widget.client.creds);

  Future<void> _addProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          onLogin: (c) {
            Navigator.of(context).pop();
            widget.onSwitch(c); // login already set it active; rebuild with it
          },
        ),
      ),
    );
    final p = await Store.savedProfiles();
    if (mounted) setState(() => _profiles = p);
  }

  void _switch(XtreamCredentials p) {
    if (_isActive(p)) return;
    HapticFeedback.selectionClick();
    widget.onSwitch(p);
  }

  Future<void> _delete(XtreamCredentials p) async {
    final wasActive = _isActive(p);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        title: const Text('Remove account?'),
        content: Text(
          '“${p.username}” will be removed from this device.'
          '${wasActive ? '\n\nYou’re currently signed in to it — you’ll be switched out.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: muted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF5277),
              foregroundColor: foregroundFor(const Color(0xFFFF5277)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final left = await Store.removeProfile(p);
    if (!mounted) return;
    if (wasActive) {
      // Active account removed: hop to another saved one, or drop to login.
      if (left.isNotEmpty) {
        widget.onSwitch(left.first);
      } else {
        widget.onLogout();
      }
      return;
    }
    setState(() => _profiles = left);
  }

  Future<void> _clearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        title: const Text('Clear watch history?'),
        content: const Text(
          'This removes Continue watching and Recently watched. Your favourites and downloads are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: muted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: onAccent,
            ),
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
        ..showSnackBar(
          const SnackBar(
            content: Text('Watch history cleared'),
            duration: Duration(seconds: 2),
          ),
        );
    }
  }

  bool _checkingUpdate = false;
  Future<void> _checkForUpdates() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    final result = await Updater.instance.check();
    if (!mounted) return;
    setState(() => _checkingUpdate = false);
    switch (result.status) {
      case UpdateCheckStatus.available:
        showUpdateFlow(context, result.info!);
      case UpdateCheckStatus.upToDate:
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'You’re on the latest (${Updater.instance.currentLabel}).',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
      case UpdateCheckStatus.failed:
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(result.error ?? 'Could not check for updates.'),
              duration: const Duration(seconds: 3),
            ),
          );
    }
  }

  String _expiry() {
    if (_info == null) return _accountInfoLoading ? 'Checking' : '—';
    final e = _info?['exp_date'];
    if (e == null || '$e' == 'null') return 'Unlimited';
    final secs = int.tryParse('$e');
    if (secs == null) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
    return '${d.day}/${d.month}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final shellIsWide = isWide(context);
        final twoColumn = constraints.maxWidth >= 820;
        final accountColumn = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _accountCard(),
            const SizedBox(height: 16),
            _profilesCard(),
          ],
        );
        final settingsColumn = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _personalizationCard(),
            const SizedBox(height: 16),
            _libraryCard(),
            const SizedBox(height: 16),
            _privacyCard(),
            const SizedBox(height: 16),
            _signOutButton(),
          ],
        );

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            shellIsWide ? 28 : 18,
            shellIsWide ? 18 : 12,
            shellIsWide ? 28 : 18,
            120,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1160),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!shellIsWide) ...[
                    Text('Profile', style: kTitle()),
                    const SizedBox(height: 4),
                    Text(
                      'Your account, your Lumen.',
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (twoColumn)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 350, child: accountColumn),
                        const SizedBox(width: 18),
                        Expanded(child: settingsColumn),
                      ],
                    )
                  else ...[
                    accountColumn,
                    const SizedBox(height: 16),
                    settingsColumn,
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _accountCard() {
    final c = widget.client.creds;
    final status = _accountInfoLoading
        ? 'Checking'
        : _info == null
        ? 'Unavailable'
        : '${_info?['status'] ?? 'Unknown'}';
    final isActive = status.toLowerCase() == 'active';
    return Glass(
      radius: 24,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CURRENT ACCOUNT', style: kSection()),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: glow(accent, blur: 18, y: 7),
                ),
                child: Text(
                  c.username.isEmpty ? '?' : c.username[0].toUpperCase(),
                  style: TextStyle(
                    color: onAccent,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.baseUrl.replaceFirst(RegExp(r'^https?://'), ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: subtle, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(height: 1, color: line),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _accountMetric(
                  'STATUS',
                  status,
                  isActive ? accentInk : textHi,
                ),
              ),
              _metricDivider(),
              Expanded(child: _accountMetric('EXPIRES', _expiry(), textHi)),
              _metricDivider(),
              Expanded(
                child: _accountMetric(
                  'DEVICES',
                  _info == null
                      ? '—'
                      : '${_info!['active_cons'] ?? 0} / ${_info!['max_connections'] ?? 1}',
                  textHi,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _accountMetric(String label, String value, Color valueColor) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          color: subtle,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: valueColor,
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );

  Widget _metricDivider() => Container(
    width: 1,
    height: 34,
    margin: const EdgeInsets.symmetric(horizontal: 10),
    color: line,
  );

  Widget _profilesCard() {
    final profiles = _profiles.where((profile) => !_isActive(profile)).toList();
    return Glass(
      radius: 24,
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Other accounts',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
                RemoteTap(
                  onTap: _addProfile,
                  semanticLabel: 'Add account',
                  focusRadius: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: accentInk.withValues(alpha: isDark ? 0.12 : 0.10),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, size: 17, color: accentInk),
                        const SizedBox(width: 4),
                        Text(
                          'Add',
                          style: TextStyle(
                            color: accentInk,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          _divider(),
          if (profiles.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 18),
              child: Row(
                children: [
                  Icon(Icons.people_outline_rounded, color: subtle, size: 20),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      'Add another account to switch without signing out.',
                      style: TextStyle(
                        color: subtle,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            for (var i = 0; i < profiles.length; i++) ...[
              if (i > 0) _divider(),
              _profileRow(profiles[i]),
            ],
        ],
      ),
    );
  }

  Widget _personalizationCard() => _sectionCard(
    icon: Icons.tune_rounded,
    title: 'Make Lumen yours',
    subtitle: 'Choose how the app looks and what appears on Home.',
    body: [
      Text('APPEARANCE', style: kSection()),
      const SizedBox(height: 10),
      const _ThemeSelector(),
      const SizedBox(height: 20),
      Text('ACCENT', style: kSection()),
      const SizedBox(height: 12),
      const _AccentPicker(),
      const SizedBox(height: 18),
      Divider(height: 1, color: line),
      const SizedBox(height: 6),
      AnimatedBuilder(
        animation: HomeConfig.instance,
        builder: (_, child) => _actionRow(
          icon: Icons.dashboard_customize_rounded,
          title: 'Customize Home',
          subtitle: HomeConfig.instance.isCustom
              ? '${HomeConfig.instance.shelves.length} shelves selected'
              : 'Choose shelves and their order',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CustomizeHomeScreen(client: widget.client),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _libraryCard() => _sectionCard(
    icon: Icons.video_library_outlined,
    title: 'Library & playback',
    subtitle: 'Manage viewing activity, offline items and catalog data.',
    body: [
      _actionRow(
        icon: Icons.insights_rounded,
        title: 'Watch insights',
        subtitle: 'See your viewing activity',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => StatsScreen(client: widget.client)),
        ),
      ),
      _divider(),
      AnimatedBuilder(
        animation: Downloads.instance,
        builder: (_, child) {
          final n = Downloads.instance.completedCount;
          return _actionRow(
            icon: Icons.download_rounded,
            title: 'Downloads',
            subtitle: n == 0 ? 'No offline items' : '$n available offline',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DownloadsScreen(client: widget.client),
              ),
            ),
          );
        },
      ),
      _divider(),
      _actionRow(
        icon: Icons.refresh_rounded,
        title: 'Refresh library',
        subtitle: 'Reload channels, films and series',
        onTap: () {
          refreshContent();
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text('Refreshing library…'),
                duration: Duration(seconds: 2),
              ),
            );
        },
      ),
      _divider(),
      _actionRow(
        icon: Icons.history_rounded,
        title: 'Clear watch history',
        subtitle: 'Remove Continue watching and Recent',
        onTap: _clearHistory,
        danger: true,
        showChevron: false,
      ),
    ],
  );

  Widget _privacyCard() => _sectionCard(
    icon: Icons.shield_outlined,
    title: 'Privacy & app',
    subtitle: 'Review policies and keep this installation current.',
    body: [
      _actionRow(
        icon: Icons.privacy_tip_outlined,
        title: 'Legal & privacy',
        subtitle: privacyPolicyUrl.contains('github.io')
            ? 'Privacy policy and terms'
            : 'App policies and details',
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const LegalScreen())),
      ),
      if (Updater.instance.isEnabled) ...[
        _divider(),
        _actionRow(
          icon: Icons.system_update_rounded,
          title: 'Check for updates',
          subtitle: _checkingUpdate
              ? 'Checking…'
              : 'Installed ${Updater.instance.currentLabel}',
          onTap: _checkingUpdate ? null : _checkForUpdates,
          trailing: _checkingUpdate
              ? SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accentInk,
                  ),
                )
              : null,
        ),
      ],
    ],
  );

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> body,
  }) => Glass(
    radius: 24,
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accentInk.withValues(alpha: isDark ? 0.12 : 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accentInk, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: subtle,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        ...body,
      ],
    ),
  );

  Widget _actionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool danger = false,
    bool showChevron = true,
    Widget? trailing,
  }) {
    const dangerColor = Color(0xFFFF6B88);
    final iconColor = danger ? dangerColor : accentInk;
    return RemoteTap(
      onTap: onTap,
      semanticLabel: title,
      focusRadius: 14,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: danger ? dangerColor : textHi,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: subtle,
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              trailing,
            ] else if (showChevron)
              Icon(Icons.chevron_right_rounded, color: subtle, size: 21),
          ],
        ),
      ),
    );
  }

  Widget _signOutButton() => RemoteTap(
    onTap: widget.onLogout,
    semanticLabel: 'Sign out of Lumen',
    focusRadius: 18,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0x12FF5277),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x30FF5277)),
      ),
      child: const Row(
        children: [
          Icon(Icons.logout_rounded, color: Color(0xFFFF7A9A), size: 20),
          SizedBox(width: 11),
          Expanded(
            child: Text(
              'Sign out of Lumen',
              style: TextStyle(
                color: Color(0xFFFF7A9A),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: Color(0x99FF7A9A), size: 21),
        ],
      ),
    ),
  );

  Widget _divider() =>
      Divider(height: 1, color: line, indent: 12, endIndent: 12);

  Widget _profileRow(XtreamCredentials p) {
    final active = _isActive(p);
    final host = p.baseUrl.replaceFirst(RegExp(r'^https?://'), '');
    return RemoteTap(
      behavior: HitTestBehavior.opaque,
      onTap: active ? null : () => _switch(p),
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
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: active ? onAccent : muted,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: subtle, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (active)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: accentInk.withValues(alpha: isDark ? 0.18 : 0.11),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Active',
                  style: TextStyle(
                    color: accentInk,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else ...[
              Icon(Icons.swap_horiz_rounded, color: muted, size: 20),
              const SizedBox(width: 4),
              IconButton(
                onPressed: () => _delete(p),
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: subtle,
                  size: 20,
                ),
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
    (
      mode: ThemeMode.system,
      icon: Icons.brightness_auto_rounded,
      label: 'System',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance.mode,
      builder: (context, current, _) {
        return Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: surfaceHi.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              for (final o in _opts)
                Expanded(
                  child: RemoteTap(
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
                          Icon(
                            o.icon,
                            size: 20,
                            color: current == o.mode ? onAccent : muted,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            o.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: current == o.mode ? onAccent : muted,
                            ),
                          ),
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

/// Accent picker: five named Lumen directions plus a custom colour wheel.
class _AccentPicker extends StatelessWidget {
  const _AccentPicker();

  Future<void> _pickCustom(BuildContext context, Color initial) async {
    var picked = initial;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        title: const Text('Custom accent'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: initial,
            onColorChanged: (c) => picked = c,
            enableAlpha: false,
            displayThumbColor: true,
            labelTypes: const [],
            pickerAreaHeightPercent: 0.7,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: muted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: picked,
              foregroundColor: foregroundFor(picked),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (ok == true) ThemeController.instance.setAccent(picked);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: ThemeController.instance.accent,
      builder: (context, current, _) {
        final cur = current.toARGB32();
        final isCustom = !accentSchemes.any(
          (scheme) => scheme.color.toARGB32() == cur,
        );
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final scheme in accentSchemes)
              _schemeChoice(
                label: scheme.name,
                color: scheme.color,
                selected: scheme.color.toARGB32() == cur,
                onTap: () => ThemeController.instance.setAccent(scheme.color),
              ),
            // Custom colour is available without competing visually with the
            // curated directions above.
            RemoteTap(
              onTap: () => _pickCustom(context, current),
              child: Container(
                width: 112,
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 11),
                decoration: BoxDecoration(
                  color: isCustom
                      ? accentInk.withValues(alpha: isDark ? 0.16 : 0.10)
                      : surfaceHi,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isCustom ? accentInk : line,
                    width: isCustom ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const SweepGradient(
                          colors: [
                            Color(0xFFFF0000),
                            Color(0xFFFFFF00),
                            Color(0xFF00FF00),
                            Color(0xFF00FFFF),
                            Color(0xFF0000FF),
                            Color(0xFFFF00FF),
                            Color(0xFFFF0000),
                          ],
                        ),
                      ),
                      child: isCustom
                          ? const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 15,
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Custom',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isCustom ? textHi : muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _schemeChoice({
    required String label,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return RemoteTap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 112,
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: selected
              ? accentInk.withValues(alpha: isDark ? 0.16 : 0.10)
              : surfaceHi,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accentInk : line,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.55),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: selected
                  ? Icon(
                      Icons.check_rounded,
                      color: foregroundFor(color),
                      size: 15,
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: selected ? textHi : muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
