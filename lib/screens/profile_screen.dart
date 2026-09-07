import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../device_profile.dart';
import '../downloads.dart';
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
import 'downloads_screen.dart';
import 'diagnostics_screen.dart';
import 'login_screen.dart';
import 'legal_screen.dart';
import 'update_dialog.dart';
import 'stats_screen.dart';

class ProfileScreen extends StatefulWidget {
  final XtreamClient client;
  final Future<void> Function() onLogout;
  final void Function(XtreamCredentials) onSwitch;
  final FocusNode? shellRailFocusNode;
  final FocusNode? shellTopFocusNode;
  final FocusNode? entryFocusNode;
  const ProfileScreen({
    super.key,
    required this.client,
    required this.onLogout,
    required this.onSwitch,
    this.shellRailFocusNode,
    this.shellTopFocusNode,
    this.entryFocusNode,
  });
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _entryFocus = FocusNode(debugLabel: 'Profile add account');
  final _themeEntryFocus = FocusNode(debugLabel: 'Dark appearance');
  final _accentEntryFocus = FocusNode(debugLabel: 'Signal lime accent');
  final _insightsFocus = FocusNode(debugLabel: 'Watch insights');
  final _downloadsFocus = FocusNode(debugLabel: 'Downloads');
  final _refreshFocus = FocusNode(debugLabel: 'Refresh library');
  final _historyFocus = FocusNode(debugLabel: 'Clear watch history');
  final _diagnosticsFocus = FocusNode(debugLabel: 'Diagnostics & feedback');
  final _legalFocus = FocusNode(debugLabel: 'Legal & privacy');
  final _updateFocus = FocusNode(debugLabel: 'Check for updates');
  final _signOutFocus = FocusNode(debugLabel: 'Sign out of Lumen');
  Map<String, dynamic>? _info;
  List<XtreamCredentials> _profiles = [];
  bool _accountInfoLoading = true;
  bool _signingOut = false;

  KeyEventResult _handlePageKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
        _entryFocusNode.hasFocus) {
      final top = widget.shellTopFocusNode;
      if (top != null && top.canRequestFocus) {
        top.requestFocus();
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey != LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.ignored;
    }
    final rail = widget.shellRailFocusNode;
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    final pageBox = context.findRenderObject();
    final focusedBox = focusedContext?.findRenderObject();
    if (rail == null ||
        !rail.canRequestFocus ||
        pageBox is! RenderBox ||
        focusedBox is! RenderBox) {
      return KeyEventResult.ignored;
    }
    final pageLeft = pageBox.localToGlobal(Offset.zero).dx;
    final focusedCenter = focusedBox
        .localToGlobal(focusedBox.size.center(Offset.zero))
        .dx;
    // The left profile column (or the single column on smaller TVs) exits to
    // the stable shell rail. Controls in the right column retain normal Left
    // navigation between theme/accent choices and the account column.
    if (focusedCenter <= pageLeft + pageBox.size.width * .42) {
      rail.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  FocusNode get _entryFocusNode => widget.entryFocusNode ?? _entryFocus;

  KeyEventResult _moveVertically(
    KeyEvent event, {
    FocusNode? up,
    FocusNode? down,
  }) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final target = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => up,
      LogicalKeyboardKey.arrowDown => down,
      _ => null,
    };
    if (target == null || !target.canRequestFocus) {
      return KeyEventResult.ignored;
    }
    target.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = target.context;
      if (!mounted || !target.hasFocus || targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        duration: DeviceProfile.isTelevision
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignmentPolicy: event.logicalKey == LogicalKeyboardKey.arrowUp
            ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
            : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
    return KeyEventResult.handled;
  }

  @override
  void initState() {
    super.initState();
    _entryFocusNode.onKeyEvent = (_, event) =>
        _moveVertically(event, down: _themeEntryFocus);
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
            autofocus: true,
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
            autofocus: true,
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

  Future<void> _requestLogout() async {
    if (_signingOut) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        title: const Text('Sign out of Lumen?'),
        content: const Text(
          'This account stays saved on this device, but playback and its '
          'library will close now.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Stay signed in', style: TextStyle(color: muted)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF5277),
              foregroundColor: foregroundFor(const Color(0xFFFF5277)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _signingOut = true);
    try {
      await widget.onLogout();
    } catch (_) {
      if (!mounted) return;
      setState(() => _signingOut = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Lumen could not finish signing out. Please try again.',
            ),
            duration: Duration(seconds: 3),
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
    if (widget.client.creds.isDemo) return 'Not applicable';
    if (_info == null) return _accountInfoLoading ? 'Checking' : '—';
    final e = _info?['exp_date'];
    if (e == null || '$e' == 'null') return 'Unlimited';
    final secs = int.tryParse('$e');
    if (secs == null) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
    return '${d.day}/${d.month}/${d.year}';
  }

  @override
  void dispose() {
    _entryFocusNode.onKeyEvent = null;
    _entryFocus.dispose();
    _themeEntryFocus.dispose();
    _accentEntryFocus.dispose();
    _insightsFocus.dispose();
    _downloadsFocus.dispose();
    _refreshFocus.dispose();
    _historyFocus.dispose();
    _diagnosticsFocus.dispose();
    _legalFocus.dispose();
    _updateFocus.dispose();
    _signOutFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(
      context,
    ); // Refresh every cached profile card with the new palette.
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

        return Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _handlePageKey,
          child: SingleChildScrollView(
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
          ),
        );
      },
    );
  }

  Widget _accountCard() {
    final c = widget.client.creds;
    final status = c.isDemo
        ? 'Ready'
        : _accountInfoLoading
        ? 'Checking'
        : _info == null
        ? 'Unavailable'
        : '${_info?['status'] ?? 'Unknown'}';
    final isActive =
        status.toLowerCase() == 'active' || status.toLowerCase() == 'ready';
    final accountName = c.isDemo ? 'Demo Mode' : c.username;
    final accountSubtitle = c.isDemo
        ? 'Offline sample library'
        : c.baseUrl.replaceFirst(RegExp(r'^https?://'), '');
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
                child: c.isDemo
                    ? Icon(
                        Icons.auto_awesome_rounded,
                        color: onAccent,
                        size: 25,
                      )
                    : Text(
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
                      accountName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      accountSubtitle,
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
              Expanded(
                child: _accountMetric(
                  c.isDemo ? 'CONTENT' : 'EXPIRES',
                  c.isDemo ? 'Fictional' : _expiry(),
                  textHi,
                ),
              ),
              _metricDivider(),
              Expanded(
                child: _accountMetric(
                  c.isDemo ? 'NETWORK' : 'DEVICES',
                  c.isDemo
                      ? 'Offline'
                      : _info == null
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
                  focusNode: _entryFocusNode,
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
    subtitle: 'Choose how the app looks on every screen.',
    body: [
      Text('APPEARANCE', style: kSection()),
      const SizedBox(height: 10),
      _ThemeSelector(
        entryFocusNode: _themeEntryFocus,
        upFocusNode: _entryFocusNode,
        downFocusNode: _accentEntryFocus,
        leftExitFocusNode: widget.shellRailFocusNode,
      ),
      const SizedBox(height: 20),
      Text('ACCENT', style: kSection()),
      const SizedBox(height: 12),
      _AccentPicker(
        entryFocusNode: _accentEntryFocus,
        upFocusNode: _themeEntryFocus,
        downFocusNode: _insightsFocus,
        leftExitFocusNode: widget.shellRailFocusNode,
      ),
      const SizedBox(height: 6),
    ],
  );

  Widget _libraryCard() => _sectionCard(
    icon: Icons.video_library_outlined,
    title: 'Library & playback',
    subtitle: 'Manage viewing activity, offline items and catalog data.',
    body: [
      _actionRow(
        focusNode: _insightsFocus,
        onKeyEvent: (_, event) => _moveVertically(
          event,
          up: _accentEntryFocus,
          down: _downloadsFocus,
        ),
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
            focusNode: _downloadsFocus,
            onKeyEvent: (_, event) =>
                _moveVertically(event, up: _insightsFocus, down: _refreshFocus),
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
        focusNode: _refreshFocus,
        onKeyEvent: (_, event) =>
            _moveVertically(event, up: _downloadsFocus, down: _historyFocus),
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
        focusNode: _historyFocus,
        onKeyEvent: (_, event) =>
            _moveVertically(event, up: _refreshFocus, down: _diagnosticsFocus),
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
        focusNode: _diagnosticsFocus,
        onKeyEvent: (_, event) =>
            _moveVertically(event, up: _historyFocus, down: _legalFocus),
        icon: Icons.bug_report_outlined,
        title: 'Diagnostics & feedback',
        subtitle: 'Review a private, redacted support report',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DiagnosticsScreen(credentials: widget.client.creds),
          ),
        ),
      ),
      _divider(),
      _actionRow(
        focusNode: _legalFocus,
        onKeyEvent: (_, event) => _moveVertically(
          event,
          up: _diagnosticsFocus,
          down: Updater.instance.isEnabled ? _updateFocus : _signOutFocus,
        ),
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
          focusNode: _updateFocus,
          onKeyEvent: (_, event) =>
              _moveVertically(event, up: _legalFocus, down: _signOutFocus),
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
    FocusNode? focusNode,
    FocusOnKeyEventCallback? onKeyEvent,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool danger = false,
    bool showChevron = true,
    Widget? trailing,
  }) {
    final dangerColor = dangerInk;
    final iconColor = danger ? dangerColor : accentInk;
    return RemoteTap(
      focusNode: focusNode,
      onKeyEvent: onKeyEvent,
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
    focusNode: _signOutFocus,
    onKeyEvent: (_, event) => _moveVertically(
      event,
      up: Updater.instance.isEnabled ? _updateFocus : _legalFocus,
    ),
    onTap: _signingOut ? null : _requestLogout,
    semanticLabel: 'Sign out of Lumen',
    focusRadius: 18,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: dangerInk.withValues(alpha: isDark ? 0.07 : 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: dangerInk.withValues(alpha: isDark ? 0.19 : 0.25),
        ),
      ),
      child: Row(
        children: [
          if (_signingOut)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: dangerInk,
              ),
            )
          else
            Icon(Icons.logout_rounded, color: dangerInk, size: 20),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              _signingOut ? 'Signing out…' : 'Sign out of Lumen',
              style: TextStyle(color: dangerInk, fontWeight: FontWeight.w800),
            ),
          ),
          if (!_signingOut)
            Icon(
              Icons.chevron_right_rounded,
              color: dangerInk.withValues(alpha: 0.60),
              size: 21,
            ),
        ],
      ),
    ),
  );

  Widget _divider() =>
      Divider(height: 1, color: line, indent: 12, endIndent: 12);

  Widget _profileRow(XtreamCredentials p) {
    final active = _isActive(p);
    final host = p.isDemo
        ? 'Offline sample library'
        : p.baseUrl.replaceFirst(RegExp(r'^https?://'), '');
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
              child: p.isDemo
                  ? Icon(
                      Icons.auto_awesome_rounded,
                      color: active ? onAccent : muted,
                      size: 19,
                    )
                  : Text(
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
                    p.isDemo ? 'Demo Mode' : p.username,
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
class _ThemeSelector extends StatefulWidget {
  const _ThemeSelector({
    required this.entryFocusNode,
    required this.upFocusNode,
    required this.downFocusNode,
    this.leftExitFocusNode,
  });

  final FocusNode entryFocusNode;
  final FocusNode upFocusNode;
  final FocusNode downFocusNode;
  final FocusNode? leftExitFocusNode;

  @override
  State<_ThemeSelector> createState() => _ThemeSelectorState();
}

class _ThemeSelectorState extends State<_ThemeSelector> {
  static const _opts = [
    (mode: ThemeMode.dark, icon: Icons.dark_mode_rounded, label: 'Dark'),
    (mode: ThemeMode.light, icon: Icons.light_mode_rounded, label: 'Light'),
    (
      mode: ThemeMode.system,
      icon: Icons.brightness_auto_rounded,
      label: 'System',
    ),
  ];

  late final List<FocusNode> _focusNodes = [
    widget.entryFocusNode,
    for (var index = 1; index < _opts.length; index++)
      FocusNode(debugLabel: '${_opts[index].label} appearance'),
  ];

  @override
  void dispose() {
    // The first node belongs to ProfileScreen so it can be part of the
    // page-wide route. This selector owns only the remaining nodes.
    for (final node in _focusNodes.skip(1)) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult _route(int index, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.upFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      widget.downFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    final delta = event.logicalKey == LogicalKeyboardKey.arrowLeft
        ? -1
        : event.logicalKey == LogicalKeyboardKey.arrowRight
        ? 1
        : 0;
    if (delta == 0) return KeyEventResult.ignored;
    final target = index + delta;
    if (target >= 0 && target < _focusNodes.length) {
      _focusNodes[target].requestFocus();
    } else if (target < 0 &&
        widget.leftExitFocusNode?.canRequestFocus == true) {
      widget.leftExitFocusNode!.requestFocus();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
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
              for (var index = 0; index < _opts.length; index++)
                Expanded(
                  child: RemoteTap(
                    focusNode: _focusNodes[index],
                    onKeyEvent: (_, event) => _route(index, event),
                    behavior: HitTestBehavior.opaque,
                    semanticLabel: '${_opts[index].label} appearance',
                    onTap: () =>
                        ThemeController.instance.set(_opts[index].mode),
                    child: AnimatedContainer(
                      key: ValueKey(
                        'profile-theme-${_opts[index].label.toLowerCase()}',
                      ),
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: current == _opts[index].mode
                            ? accent
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            _opts[index].icon,
                            size: 20,
                            color: current == _opts[index].mode
                                ? onAccent
                                : muted,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _opts[index].label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: current == _opts[index].mode
                                  ? onAccent
                                  : muted,
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

/// Accent picker: five named Lumen directions plus D-pad-friendly sliders.
class _AccentPicker extends StatefulWidget {
  const _AccentPicker({
    required this.entryFocusNode,
    required this.upFocusNode,
    required this.downFocusNode,
    this.leftExitFocusNode,
  });

  final FocusNode entryFocusNode;
  final FocusNode upFocusNode;
  final FocusNode downFocusNode;
  final FocusNode? leftExitFocusNode;

  @override
  State<_AccentPicker> createState() => _AccentPickerState();
}

class _AccentPickerState extends State<_AccentPicker> {
  late final List<FocusNode> _focusNodes = [
    widget.entryFocusNode,
    for (var index = 1; index < accentSchemes.length + 1; index++)
      FocusNode(
        debugLabel: index < accentSchemes.length
            ? '${accentSchemes[index].name} accent'
            : 'Custom accent',
      ),
  ];

  @override
  void dispose() {
    for (final node in _focusNodes.skip(1)) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult _route(int index, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.upFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      widget.downFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    final delta = event.logicalKey == LogicalKeyboardKey.arrowLeft
        ? -1
        : event.logicalKey == LogicalKeyboardKey.arrowRight
        ? 1
        : 0;
    if (delta == 0) return KeyEventResult.ignored;
    final target = index + delta;
    if (target >= 0 && target < _focusNodes.length) {
      _focusNodes[target].requestFocus();
    } else if (target < 0 &&
        widget.leftExitFocusNode?.canRequestFocus == true) {
      widget.leftExitFocusNode!.requestFocus();
    }
    return KeyEventResult.handled;
  }

  Future<void> _pickCustom(BuildContext context, Color initial) async {
    var picked = initial;
    var hsv = HSVColor.fromColor(initial);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: surface,
          title: const Text('Custom accent'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 54,
                  decoration: BoxDecoration(
                    color: picked,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Use Left/Right on the remote to adjust each value.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                _colorSlider(
                  label: 'Hue',
                  value: hsv.hue,
                  max: 360,
                  divisions: 360,
                  onChanged: (value) => setLocal(() {
                    hsv = hsv.withHue(value);
                    picked = hsv.toColor();
                  }),
                ),
                _colorSlider(
                  label: 'Saturation',
                  value: hsv.saturation * 100,
                  max: 100,
                  divisions: 100,
                  onChanged: (value) => setLocal(() {
                    hsv = hsv.withSaturation(value / 100);
                    picked = hsv.toColor();
                  }),
                ),
                _colorSlider(
                  label: 'Brightness',
                  value: hsv.value * 100,
                  max: 100,
                  divisions: 100,
                  onChanged: (value) => setLocal(() {
                    hsv = hsv.withValue(value / 100);
                    picked = hsv.toColor();
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              autofocus: true,
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
      ),
    );
    if (ok == true) ThemeController.instance.setAccent(picked);
  }

  Widget _colorSlider({
    required String label,
    required double value,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) => Row(
    children: [
      SizedBox(
        width: 82,
        child: Text(label, style: TextStyle(color: textHi, fontSize: 12)),
      ),
      Expanded(
        child: Slider(
          value: value.clamp(0, max),
          min: 0,
          max: max,
          divisions: divisions,
          label: value.round().toString(),
          onChanged: onChanged,
        ),
      ),
      SizedBox(
        width: 36,
        child: Text(
          value.round().toString(),
          textAlign: TextAlign.right,
          style: TextStyle(color: muted, fontSize: 11),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
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
            for (var index = 0; index < accentSchemes.length; index++)
              _schemeChoice(
                label: accentSchemes[index].name,
                color: accentSchemes[index].color,
                selected: accentSchemes[index].color.toARGB32() == cur,
                onTap: () => ThemeController.instance.setAccent(
                  accentSchemes[index].color,
                ),
                focusNode: _focusNodes[index],
                onKeyEvent: (_, event) => _route(index, event),
              ),
            // Custom colour is available without competing visually with the
            // curated directions above.
            RemoteTap(
              focusNode: _focusNodes.last,
              onKeyEvent: (_, event) => _route(_focusNodes.length - 1, event),
              semanticLabel: 'Custom accent',
              onTap: () => _pickCustom(context, current),
              child: Container(
                key: const ValueKey('profile-accent-custom'),
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
    required FocusNode focusNode,
    required FocusOnKeyEventCallback onKeyEvent,
  }) {
    return RemoteTap(
      focusNode: focusNode,
      onKeyEvent: onKeyEvent,
      semanticLabel: '$label accent',
      onTap: onTap,
      child: AnimatedContainer(
        key: ValueKey('profile-accent-${label.toLowerCase()}'),
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
