import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../device_profile.dart';
import '../downloads.dart';
import '../library.dart';
import '../legal.dart';
import '../models.dart';
import '../playback_mode.dart';
import '../refresh.dart';
import '../responsive.dart';
import '../store.dart';
import '../viewing_profiles.dart';
import '../theme.dart';
import '../updater.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'downloads_screen.dart';
import 'catalog_organization_screen.dart';
import 'diagnostics_screen.dart';
import 'epg_settings_screen.dart';
import 'login_screen.dart';
import 'legal_screen.dart';
import 'update_dialog.dart';
import 'stats_screen.dart';
import 'viewer_picker_screen.dart';

typedef ProfileCredentialValidator =
    Future<void> Function(XtreamCredentials credentials);

class ProfileScreen extends StatefulWidget {
  final XtreamClient client;
  final Future<void> Function() onLogout;
  final void Function(XtreamCredentials) onSwitch;
  final Future<void> Function()? onServicesChanged;
  final Future<void> Function(String id)? onViewerChanged;
  final FocusNode? shellRailFocusNode;
  final FocusNode? shellTopFocusNode;
  final FocusNode? entryFocusNode;
  final ProfileCredentialValidator? profileValidator;
  const ProfileScreen({
    super.key,
    required this.client,
    required this.onLogout,
    required this.onSwitch,
    this.onServicesChanged,
    this.onViewerChanged,
    this.shellRailFocusNode,
    this.shellTopFocusNode,
    this.entryFocusNode,
    this.profileValidator,
  });
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _pageScroll = ScrollController();
  final _entryFocus = FocusNode(debugLabel: 'Profile add account');
  final _viewerManageFocus = FocusNode(debugLabel: 'Switch or manage viewers');
  final _themeEntryFocus = FocusNode(debugLabel: 'Dark appearance');
  final _fontEntryFocus = FocusNode(debugLabel: 'Lumen font');
  final _cornerEntryFocus = FocusNode(debugLabel: 'Crisp corners');
  final _focusStyleEntryFocus = FocusNode(debugLabel: 'Outline focus');
  final _accentEntryFocus = FocusNode(debugLabel: 'Signal lime accent');
  final _playbackModeFocus = FocusNode(debugLabel: 'Live playback mode');
  final _insightsFocus = FocusNode(debugLabel: 'Watch insights');
  final _downloadsFocus = FocusNode(debugLabel: 'Downloads');
  final _refreshFocus = FocusNode(debugLabel: 'Refresh library');
  final _organizeFocus = FocusNode(debugLabel: 'Organize library');
  final _guideSettingsFocus = FocusNode(debugLabel: 'TV guide setup');
  final _historyFocus = FocusNode(debugLabel: 'Clear watch history');
  final _diagnosticsFocus = FocusNode(debugLabel: 'Diagnostics & feedback');
  final _communityFocus = FocusNode(debugLabel: 'Lumen community');
  final _legalFocus = FocusNode(debugLabel: 'Legal & privacy');
  final _updateFocus = FocusNode(debugLabel: 'Check for updates');
  final _signOutFocus = FocusNode(debugLabel: 'Sign out of Lumen');
  final _currentEditFocus = FocusNode(debugLabel: 'Edit current service');
  final Map<String, FocusNode> _profileSwitchFocus = {};
  final Map<String, FocusNode> _profileCombineFocus = {};
  final Map<String, FocusNode> _profileEditFocus = {};
  final Map<String, FocusNode> _profileDeleteFocus = {};
  Map<String, dynamic>? _info;
  List<XtreamCredentials> _profiles = [];
  Set<String> _enabledScopes = {};
  bool _accountInfoLoading = true;
  bool _signingOut = false;

  KeyEventResult _handlePageKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
        _viewerManageFocus.hasFocus &&
        widget.client.creds.isDemo) {
      _restoreProfileTop();
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
    if (focusedContext == null || !focusedContext.mounted) {
      return KeyEventResult.ignored;
    }
    final pageBox = context.findRenderObject();
    final focusedBox = focusedContext.findRenderObject();
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

  void _restoreProfileTop() {
    if (!_pageScroll.hasClients) return;
    final position = _pageScroll.position;
    if (position.pixels <= position.minScrollExtent) return;
    if (DeviceProfile.isTelevision) {
      _pageScroll.jumpTo(position.minScrollExtent);
    } else {
      _pageScroll.animateTo(
        position.minScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _restoreTopWhenEntryFocused() {
    if (!DeviceProfile.isTelevision || !_entryFocusNode.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _entryFocusNode.hasFocus) _restoreProfileTop();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  String _profileKey(XtreamCredentials profile) => Store.profileScope(profile);

  List<XtreamCredentials> get _otherProfiles =>
      _profiles.where((profile) => !_isActive(profile)).toList();

  FocusNode? get _firstProfileSwitchFocus {
    final profiles = _otherProfiles;
    return profiles.isEmpty
        ? null
        : _profileSwitchFocus[_profileKey(profiles.first)];
  }

  FocusNode? get _lastProfileSwitchFocus {
    final profiles = _otherProfiles;
    return profiles.isEmpty
        ? null
        : _profileSwitchFocus[_profileKey(profiles.last)];
  }

  void _syncProfileFocus(List<XtreamCredentials> profiles) {
    final visible = profiles.where((profile) => !_isActive(profile)).toList();
    final liveKeys = visible.map(_profileKey).toSet();
    for (final nodes in [
      _profileSwitchFocus,
      _profileCombineFocus,
      _profileEditFocus,
      _profileDeleteFocus,
    ]) {
      final removed = nodes.keys
          .where((key) => !liveKeys.contains(key))
          .toList();
      for (final key in removed) {
        final node = nodes.remove(key);
        if (node != null) {
          // Let RemoteTap detach its key handler during this rebuild before
          // disposing the external node it was using.
          WidgetsBinding.instance.addPostFrameCallback((_) => node.dispose());
        }
      }
    }
    for (final profile in visible) {
      final key = _profileKey(profile);
      final label = profile.isDemo ? 'Demo Mode' : profile.username;
      _profileSwitchFocus.putIfAbsent(
        key,
        () => FocusNode(debugLabel: 'Switch account $label'),
      );
      _profileDeleteFocus.putIfAbsent(
        key,
        () => FocusNode(debugLabel: 'Remove account $label'),
      );
      _profileCombineFocus.putIfAbsent(
        key,
        () => FocusNode(debugLabel: 'Combine service $label'),
      );
      _profileEditFocus.putIfAbsent(
        key,
        () => FocusNode(debugLabel: 'Edit service $label'),
      );
    }
  }

  void _setProfiles(
    List<XtreamCredentials> profiles, {
    FocusNode? restoreFocus,
  }) {
    _syncProfileFocus(profiles);
    setState(() => _profiles = profiles);
    if (restoreFocus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && restoreFocus.canRequestFocus) {
          restoreFocus.requestFocus();
        }
      });
    }
  }

  KeyEventResult _moveInFocusGraph(
    KeyEvent event,
    Map<LogicalKeyboardKey, FocusNode?> routes,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final target = routes[event.logicalKey];
    if (target == null || !target.canRequestFocus) {
      return KeyEventResult.ignored;
    }
    target.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = target.context;
      if (!mounted ||
          !target.hasFocus ||
          targetContext == null ||
          !targetContext.mounted) {
        return;
      }
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
      if (!mounted ||
          !target.hasFocus ||
          targetContext == null ||
          !targetContext.mounted) {
        return;
      }
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
    Updater.instance.initialize().then((_) {
      if (mounted) setState(() {});
    });
    _entryFocusNode.onKeyEvent = (_, event) => _moveVertically(
      event,
      up: _viewerManageFocus,
      down: _firstProfileSwitchFocus ?? _themeEntryFocus,
    );
    _viewerManageFocus.onKeyEvent = (_, event) => _moveVertically(
      event,
      up: widget.client.creds.isDemo ? null : _currentEditFocus,
      down: _entryFocusNode,
    );
    _currentEditFocus.onKeyEvent = (_, event) => _moveInFocusGraph(event, {
      LogicalKeyboardKey.arrowLeft: widget.shellRailFocusNode,
      LogicalKeyboardKey.arrowUp: widget.shellTopFocusNode,
      LogicalKeyboardKey.arrowDown: _viewerManageFocus,
    });
    _entryFocusNode.addListener(_restoreTopWhenEntryFocused);
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
    Store.savedProfiles().then((profiles) {
      if (!mounted) return;
      _setProfiles(profiles);
    });
    Store.enabledSourceScopes().then((scopes) {
      if (mounted) setState(() => _enabledScopes = scopes);
    });
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
    if (mounted) _setProfiles(p, restoreFocus: _entryFocusNode);
  }

  void _switch(XtreamCredentials p) {
    if (_isActive(p)) return;
    HapticFeedback.selectionClick();
    widget.onSwitch(p);
  }

  Future<void> _toggleCombined(XtreamCredentials profile) async {
    if (profile.isDemo) return;
    final scope = _profileKey(profile);
    final enabled = !_enabledScopes.contains(scope);
    await Store.setProfileEnabled(profile, enabled);
    if (!mounted) return;
    setState(() {
      if (enabled) {
        _enabledScopes.add(scope);
      } else {
        _enabledScopes.remove(scope);
      }
    });
    await widget.onServicesChanged?.call();
  }

  Future<void> _edit(XtreamCredentials profile) async {
    if (profile.isDemo) return;
    final replacement = await showDialog<XtreamCredentials>(
      context: context,
      builder: (_) => _EditServiceDialog(
        profile: profile,
        validator: widget.profileValidator,
      ),
    );
    if (replacement == null || !mounted) return;
    try {
      final wasEnabled = _enabledScopes.contains(_profileKey(profile));
      final profiles = await Store.updateProfile(profile, replacement);
      if (!mounted) return;
      if (_isActive(profile)) {
        widget.onSwitch(replacement);
        return;
      }
      if (wasEnabled) {
        setState(() {
          _enabledScopes
            ..remove(_profileKey(profile))
            ..add(_profileKey(replacement));
        });
        await widget.onServicesChanged?.call();
        if (!mounted) return;
      }
      _setProfiles(profiles, restoreFocus: _entryFocusNode);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Service address updated'),
            duration: Duration(seconds: 2),
          ),
        );
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${error.message}'),
            duration: const Duration(seconds: 3),
          ),
        );
    }
  }

  Future<void> _delete(XtreamCredentials p) async {
    final wasActive = _isActive(p);
    final wasEnabled = _enabledScopes.contains(_profileKey(p));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) =>
          _AccountRemovalDialog(username: p.username, active: wasActive),
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
    if (wasEnabled) {
      setState(() => _enabledScopes.remove(_profileKey(p)));
      await widget.onServicesChanged?.call();
      if (!mounted) return;
    }
    _setProfiles(left, restoreFocus: _entryFocusNode);
  }

  Future<void> _clearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        title: const Text('Clear watch history?'),
        content: const Text(
          'This removes Continue watching and Recent channels. Your favourites and downloads are kept.',
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

  Future<void> _openCommunity() async {
    final opened = await launchUrl(
      Uri.parse(communityUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not open the Lumen community link.'),
            duration: Duration(seconds: 3),
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
    await Updater.instance.initialize();
    if (Updater.instance.distribution == AppDistribution.playStore) {
      final opened = await Updater.instance.openStorePage();
      if (!mounted) return;
      setState(() => _checkingUpdate = false);
      if (!opened) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Could not open Lumen in Google Play.'),
              duration: Duration(seconds: 3),
            ),
          );
      }
      return;
    }
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
    _entryFocusNode.removeListener(_restoreTopWhenEntryFocused);
    _entryFocusNode.onKeyEvent = null;
    _viewerManageFocus.dispose();
    _pageScroll.dispose();
    _entryFocus.dispose();
    _themeEntryFocus.dispose();
    _fontEntryFocus.dispose();
    _cornerEntryFocus.dispose();
    _focusStyleEntryFocus.dispose();
    _accentEntryFocus.dispose();
    _playbackModeFocus.dispose();
    _insightsFocus.dispose();
    _downloadsFocus.dispose();
    _refreshFocus.dispose();
    _organizeFocus.dispose();
    _guideSettingsFocus.dispose();
    _historyFocus.dispose();
    _diagnosticsFocus.dispose();
    _communityFocus.dispose();
    _legalFocus.dispose();
    _updateFocus.dispose();
    _signOutFocus.dispose();
    _currentEditFocus.dispose();
    for (final node in _profileSwitchFocus.values) {
      node.dispose();
    }
    for (final node in _profileCombineFocus.values) {
      node.dispose();
    }
    for (final node in _profileEditFocus.values) {
      node.dispose();
    }
    for (final node in _profileDeleteFocus.values) {
      node.dispose();
    }
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
            _viewingCard(),
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
            controller: _pageScroll,
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

  Widget _viewingCard() => AnimatedBuilder(
    animation: ViewingProfiles.instance,
    builder: (context, _) {
      final viewer = ViewingProfiles.instance.active;
      return Glass(
        radius: 24,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('VIEWING PROFILE', style: kSection()),
            const SizedBox(height: 10),
            Text(
              viewer.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Your own My List, history, and Continue Watching. Services are shared.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              focusNode: _viewerManageFocus,
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => Dialog(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ViewerPickerScreen(
                      embedded: true,
                      onSelect: (id) async {
                        Navigator.pop(dialogContext);
                        await widget.onViewerChanged?.call(id);
                      },
                    ),
                  ),
                ),
              ),
              icon: const Icon(Icons.switch_account_outlined),
              label: const Text('Switch or manage viewers'),
            ),
          ],
        ),
      );
    },
  );

  Widget _accountCard() {
    final c = widget.client.creds;
    final combinedCount = {..._enabledScopes, _profileKey(c)}.length;
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
          const SizedBox(height: 5),
          Text(
            '$combinedCount ${combinedCount == 1 ? 'service' : 'services'} in this combined library',
            style: TextStyle(color: subtle, fontSize: 11.5),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(lumenCorner(18)),
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
              if (!c.isDemo) ...[
                const SizedBox(width: 10),
                RemoteTap(
                  key: const ValueKey('edit-current-service'),
                  focusNode: _currentEditFocus,
                  semanticLabel: 'Edit current service address',
                  focusRadius: 11,
                  onTap: () => _edit(c),
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: surfaceHi,
                      borderRadius: BorderRadius.circular(lumenCorner(11)),
                      border: Border.all(color: line),
                    ),
                    child: Icon(
                      Icons.edit_outlined,
                      color: accentInk,
                      size: 19,
                    ),
                  ),
                ),
              ],
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
    final profiles = _otherProfiles;
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
                    'IPTV services',
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
                      borderRadius: BorderRadius.circular(lumenCorner(11)),
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
                      'Add another service, then include it in your combined library.',
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
              _profileRow(profiles, i),
            ],
        ],
      ),
    );
  }

  Widget _personalizationCard() => _profileSection(
    eyebrow: 'PERSONALIZATION',
    title: 'Appearance',
    subtitle: 'Choose a look that stays consistent on every screen.',
    icon: Icons.tune_rounded,
    body: [
      _controlHeading(
        'Color mode',
        'Use a dark, light, or device-matched interface.',
      ),
      const SizedBox(height: 12),
      _ThemeSelector(
        entryFocusNode: _themeEntryFocus,
        upFocusNode: _lastProfileSwitchFocus ?? _entryFocusNode,
        downFocusNode: _fontEntryFocus,
        leftExitFocusNode: widget.shellRailFocusNode,
      ),
      const SizedBox(height: 24),
      _controlHeading('Typeface', 'Set the reading style across Lumen.'),
      const SizedBox(height: 12),
      _FontSelector(
        entryFocusNode: _fontEntryFocus,
        upFocusNode: _themeEntryFocus,
        downFocusNode: _cornerEntryFocus,
        leftExitFocusNode: widget.shellRailFocusNode,
      ),
      const SizedBox(height: 24),
      _controlHeading('Shape', 'Control the roundness of cards and controls.'),
      const SizedBox(height: 12),
      _PreferenceSelector<LumenCornerStyle>(
        entryFocusNode: _cornerEntryFocus,
        upFocusNode: _fontEntryFocus,
        downFocusNode: _focusStyleEntryFocus,
        leftExitFocusNode: widget.shellRailFocusNode,
        values: LumenCornerStyle.values,
        current: ThemeController.instance.corners,
        semanticSuffix: 'corners',
        keyPrefix: 'profile-corners',
        labelOf: (value) => value.label,
        descriptionOf: (value) => value.description,
        onSelected: ThemeController.instance.setCorners,
        previewBuilder: (value, selected) => Container(
          width: 28,
          height: 20,
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: .28)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(
              (14 * value.multiplier).clamp(3.5, 20),
            ),
            border: Border.all(color: selected ? accentInk : muted, width: 2),
          ),
        ),
      ),
      const SizedBox(height: 24),
      _controlHeading(
        'Focus style',
        'Choose how the selected item stands out on TV and keyboard devices.',
      ),
      const SizedBox(height: 12),
      _PreferenceSelector<LumenFocusStyle>(
        entryFocusNode: _focusStyleEntryFocus,
        upFocusNode: _cornerEntryFocus,
        downFocusNode: _accentEntryFocus,
        leftExitFocusNode: widget.shellRailFocusNode,
        values: LumenFocusStyle.values,
        current: ThemeController.instance.focus,
        semanticSuffix: 'focus',
        keyPrefix: 'profile-focus',
        labelOf: (value) => value.label,
        descriptionOf: (value) => value.description,
        onSelected: ThemeController.instance.setFocus,
        previewBuilder: (value, selected) => Container(
          width: 28,
          height: 20,
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(lumenCorner(7)),
            border: Border.all(
              color: selected ? accentInk : muted,
              width: value.ringWidth,
            ),
            boxShadow: value.blurRadius <= 0
                ? const []
                : [
                    BoxShadow(
                      color: accent.withValues(alpha: .32),
                      blurRadius: value.blurRadius,
                    ),
                  ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      _controlHeading(
        'Accent color',
        'Applied to focus, progress, selections, and primary actions.',
      ),
      const SizedBox(height: 12),
      _AccentPicker(
        entryFocusNode: _accentEntryFocus,
        upFocusNode: _focusStyleEntryFocus,
        downFocusNode: _playbackModeFocus,
        leftExitFocusNode: widget.shellRailFocusNode,
      ),
    ],
  );

  Future<void> _choosePlaybackMode() async {
    final current = PlaybackModeController.instance.mode.value;
    final selected = await showDialog<PlaybackMode>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surface,
        title: const Text('Live playback mode'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final mode in PlaybackMode.values)
                ListTile(
                  autofocus: mode == current,
                  leading: Icon(
                    mode == current
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: mode == current ? accentInk : muted,
                  ),
                  title: Text(
                    mode.label,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(mode.description),
                  onTap: () => Navigator.pop(dialogContext, mode),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selected == null) return;
    await PlaybackModeController.instance.set(selected);
  }

  Widget _libraryCard() => _profileSection(
    eyebrow: 'VIEWING',
    icon: Icons.video_library_outlined,
    title: 'Playback & library',
    subtitle: 'Tune streaming and manage the catalog stored on this device.',
    body: [
      ValueListenableBuilder<PlaybackMode>(
        valueListenable: PlaybackModeController.instance.mode,
        builder: (context, mode, _) => _actionRow(
          focusNode: _playbackModeFocus,
          onKeyEvent: (_, event) => _moveVertically(
            event,
            up: _accentEntryFocus,
            down: _insightsFocus,
          ),
          icon: Icons.network_check_rounded,
          title: 'Live playback · ${mode.label}',
          subtitle: mode.description,
          onTap: _choosePlaybackMode,
        ),
      ),
      _divider(),
      _actionRow(
        focusNode: _insightsFocus,
        onKeyEvent: (_, event) => _moveVertically(
          event,
          up: _playbackModeFocus,
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
            _moveVertically(event, up: _downloadsFocus, down: _organizeFocus),
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
        focusNode: _organizeFocus,
        onKeyEvent: (_, event) => _moveVertically(
          event,
          up: _refreshFocus,
          down: DeviceProfile.isMobileApp ? _historyFocus : _guideSettingsFocus,
        ),
        icon: Icons.tune_rounded,
        title: 'Organize library',
        subtitle: 'Rename, hide, reorder, and combine provider categories',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CatalogOrganizationScreen(client: widget.client),
          ),
        ),
      ),
      if (!DeviceProfile.isMobileApp) ...[
        _divider(),
        _actionRow(
          focusNode: _guideSettingsFocus,
          onKeyEvent: (_, event) =>
              _moveVertically(event, up: _organizeFocus, down: _historyFocus),
          icon: Icons.calendar_view_week_outlined,
          title: 'TV guide setup',
          subtitle: 'Manage EPG source, timing, refresh and cache',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EpgSettingsScreen(client: widget.client),
            ),
          ),
        ),
      ],
      _divider(),
      _actionRow(
        focusNode: _historyFocus,
        onKeyEvent: (_, event) => _moveVertically(
          event,
          up: DeviceProfile.isMobileApp ? _organizeFocus : _guideSettingsFocus,
          down: _diagnosticsFocus,
        ),
        icon: Icons.history_rounded,
        title: 'Clear watch history',
        subtitle: 'Remove Continue watching and Recent channels',
        onTap: _clearHistory,
        danger: true,
        showChevron: false,
      ),
    ],
  );

  Widget _privacyCard() => _profileSection(
    eyebrow: 'LUMEN',
    icon: Icons.shield_outlined,
    title: 'App & support',
    subtitle: 'Get help, review policies, and keep Lumen current.',
    body: [
      _actionRow(
        focusNode: _diagnosticsFocus,
        onKeyEvent: (_, event) =>
            _moveVertically(event, up: _historyFocus, down: _communityFocus),
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
        focusNode: _communityFocus,
        onKeyEvent: (_, event) =>
            _moveVertically(event, up: _diagnosticsFocus, down: _legalFocus),
        icon: Icons.forum_outlined,
        title: 'Join the Lumen community',
        subtitle: 'Chat with other users and share feedback on Discord',
        onTap: _openCommunity,
      ),
      _divider(),
      _actionRow(
        focusNode: _legalFocus,
        onKeyEvent: (_, event) => _moveVertically(
          event,
          up: _communityFocus,
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
          title: 'App version & updates',
          subtitle: _checkingUpdate
              ? 'Checking…'
              : '${Updater.instance.currentLabel} · '
                    '${Updater.instance.distributionLabel}',
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

  Widget _profileSection({
    required String eyebrow,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> body,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? .18 : .13),
                borderRadius: BorderRadius.circular(lumenCorner(13)),
              ),
              child: Icon(icon, color: accentInk, size: 20),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow,
                    style: TextStyle(
                      color: accentInk,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.35,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.35,
                    ),
                  ),
                  const SizedBox(height: 5),
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
      ),
      const SizedBox(height: 12),
      Glass(
        radius: 24,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: body,
        ),
      ),
    ],
  );

  Widget _controlHeading(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 3),
      Text(subtitle, style: TextStyle(color: subtle, fontSize: 11.5)),
    ],
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
                borderRadius: BorderRadius.circular(lumenCorner(12)),
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
        borderRadius: BorderRadius.circular(lumenCorner(18)),
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

  Widget _profileRow(List<XtreamCredentials> profiles, int index) {
    final p = profiles[index];
    final key = _profileKey(p);
    final switchFocus = _profileSwitchFocus[key]!;
    final combineFocus = _profileCombineFocus[key]!;
    final editFocus = _profileEditFocus[key]!;
    final deleteFocus = _profileDeleteFocus[key]!;
    FocusNode? switchAt(int target) => target >= 0 && target < profiles.length
        ? _profileSwitchFocus[_profileKey(profiles[target])]
        : null;
    FocusNode? deleteAt(int target) => target >= 0 && target < profiles.length
        ? _profileDeleteFocus[_profileKey(profiles[target])]
        : null;
    FocusNode? combineAt(int target) => target >= 0 && target < profiles.length
        ? _profileCombineFocus[_profileKey(profiles[target])]
        : null;
    FocusNode? editAt(int target) => target >= 0 && target < profiles.length
        ? _profileEditFocus[_profileKey(profiles[target])]
        : null;
    final host = p.isDemo
        ? 'Offline sample library'
        : p.baseUrl.replaceFirst(RegExp(r'^https?://'), '');
    return RemoteTap(
      key: ValueKey('profile-switch-$key'),
      behavior: HitTestBehavior.opaque,
      focusNode: switchFocus,
      semanticLabel: 'Switch to ${p.isDemo ? 'Demo Mode' : p.username}',
      onKeyEvent: (_, event) => _moveInFocusGraph(event, {
        LogicalKeyboardKey.arrowLeft: widget.shellRailFocusNode,
        LogicalKeyboardKey.arrowRight: p.isDemo ? deleteFocus : combineFocus,
        LogicalKeyboardKey.arrowUp: index == 0
            ? _entryFocusNode
            : switchAt(index - 1),
        LogicalKeyboardKey.arrowDown: index == profiles.length - 1
            ? _themeEntryFocus
            : switchAt(index + 1),
      }),
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
                color: surfaceHi,
                shape: BoxShape.circle,
              ),
              child: p.isDemo
                  ? Icon(Icons.auto_awesome_rounded, color: muted, size: 19)
                  : Text(
                      p.username.isNotEmpty ? p.username[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: muted,
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
                  if (!p.isDemo && _enabledScopes.contains(key))
                    Text(
                      'Included in combined library',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accentInk,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
            if (!p.isDemo) ...[
              RemoteTap(
                key: ValueKey('profile-combine-$key'),
                focusNode: combineFocus,
                semanticLabel: _enabledScopes.contains(key)
                    ? 'Remove ${p.username} from combined library'
                    : 'Include ${p.username} in combined library',
                focusRadius: 10,
                onKeyEvent: (_, event) => _moveInFocusGraph(event, {
                  LogicalKeyboardKey.arrowLeft: switchFocus,
                  LogicalKeyboardKey.arrowRight: editFocus,
                  LogicalKeyboardKey.arrowUp: index == 0
                      ? _entryFocusNode
                      : combineAt(index - 1),
                  LogicalKeyboardKey.arrowDown: index == profiles.length - 1
                      ? _themeEntryFocus
                      : combineAt(index + 1),
                }),
                onTap: () => _toggleCombined(p),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _enabledScopes.contains(key)
                        ? accentInk.withValues(alpha: .14)
                        : surfaceHi,
                    borderRadius: BorderRadius.circular(lumenCorner(10)),
                    border: Border.all(
                      color: _enabledScopes.contains(key) ? accentInk : line,
                    ),
                  ),
                  child: Icon(
                    Icons.add_link_rounded,
                    color: _enabledScopes.contains(key) ? accentInk : subtle,
                    size: 19,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              RemoteTap(
                key: ValueKey('profile-edit-$key'),
                focusNode: editFocus,
                semanticLabel: 'Edit ${p.username} service address',
                focusRadius: 10,
                onKeyEvent: (_, event) => _moveInFocusGraph(event, {
                  LogicalKeyboardKey.arrowLeft: combineFocus,
                  LogicalKeyboardKey.arrowRight: deleteFocus,
                  LogicalKeyboardKey.arrowUp: index == 0
                      ? _entryFocusNode
                      : editAt(index - 1),
                  LogicalKeyboardKey.arrowDown: index == profiles.length - 1
                      ? _themeEntryFocus
                      : editAt(index + 1),
                }),
                onTap: () => _edit(p),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: surfaceHi,
                    borderRadius: BorderRadius.circular(lumenCorner(10)),
                    border: Border.all(color: line),
                  ),
                  child: Icon(Icons.edit_outlined, color: subtle, size: 19),
                ),
              ),
              const SizedBox(width: 7),
            ],
            RemoteTap(
              key: ValueKey('profile-remove-$key'),
              focusNode: deleteFocus,
              semanticLabel:
                  'Remove ${p.isDemo ? 'Demo Mode' : p.username} account',
              focusRadius: 10,
              onKeyEvent: (_, event) => _moveInFocusGraph(event, {
                LogicalKeyboardKey.arrowLeft: p.isDemo
                    ? switchFocus
                    : editFocus,
                LogicalKeyboardKey.arrowUp: index == 0
                    ? _entryFocusNode
                    : deleteAt(index - 1),
                LogicalKeyboardKey.arrowDown: index == profiles.length - 1
                    ? _themeEntryFocus
                    : deleteAt(index + 1),
              }),
              onTap: () => _delete(p),
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: surfaceHi,
                  borderRadius: BorderRadius.circular(lumenCorner(10)),
                  border: Border.all(color: line),
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: subtle,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditServiceDialog extends StatefulWidget {
  const _EditServiceDialog({required this.profile, this.validator});

  final XtreamCredentials profile;
  final ProfileCredentialValidator? validator;

  @override
  State<_EditServiceDialog> createState() => _EditServiceDialogState();
}

class _EditServiceDialogState extends State<_EditServiceDialog> {
  late final TextEditingController _address;
  final _addressFocus = FocusNode(debugLabel: 'Service address');
  final _cancelFocus = FocusNode(debugLabel: 'Cancel service edit');
  final _saveFocus = FocusNode(debugLabel: 'Save service address');
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _address = TextEditingController(
      text: widget.profile.isM3u
          ? widget.profile.m3uUrl ?? ''
          : widget.profile.baseUrl,
    );
  }

  XtreamCredentials? _replacement() {
    var value = _address.text.trim();
    if (value.isEmpty) return null;
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(value)) {
      value = 'https://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    final profile = widget.profile;
    if (profile.isM3u) {
      final port = uri.hasPort ? ':${uri.port}' : '';
      return XtreamCredentials(
        baseUrl: '${uri.scheme}://${uri.host}$port',
        username: profile.username,
        password: profile.password,
        m3uUrl: uri.toString(),
      );
    }
    return XtreamCredentials(
      baseUrl: normalizeBaseUrl(value),
      username: profile.username,
      password: profile.password,
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    final replacement = _replacement();
    if (replacement == null) {
      setState(() => _error = 'Enter a complete HTTP or HTTPS address.');
      return;
    }
    if (replacement.baseUrl == widget.profile.baseUrl &&
        replacement.m3uUrl == widget.profile.m3uUrl) {
      setState(() => _error = 'Enter the provider’s new address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    XtreamClient? validationClient;
    try {
      final validator = widget.validator;
      if (validator != null) {
        await validator(replacement);
      } else {
        validationClient = XtreamClient(replacement);
        await validationClient.authenticate().timeout(
          const Duration(seconds: 18),
          onTimeout: () => throw XtreamException(
            'The new server did not respond. Check the address and try again.',
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(replacement);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = safeProviderError(error);
        });
      }
    } finally {
      validationClient?.close();
    }
  }

  @override
  void dispose() {
    _address.dispose();
    _addressFocus.dispose();
    _cancelFocus.dispose();
    _saveFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: surface,
    title: Text(widget.profile.isM3u ? 'Edit playlist' : 'Edit server'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.profile.isM3u
                ? 'Replace the playlist URL. Your saved library and settings will stay with this service.'
                : 'Use this when your IPTV provider moves the same account to a new hostname. Your username and password will be kept.',
            style: TextStyle(color: subtle, height: 1.4),
          ),
          const SizedBox(height: 16),
          RemoteTextInput(
            child: TextField(
              key: const ValueKey('edit-service-address'),
              controller: _address,
              focusNode: _addressFocus,
              autofocus: true,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: widget.profile.isM3u
                    ? 'Playlist URL'
                    : 'Server address',
                hintText: 'https://provider.example',
                errorText: _error,
              ),
              onSubmitted: (_) => _save(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.person_outline_rounded, size: 17, color: muted),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  widget.profile.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        focusNode: _cancelFocus,
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        key: const ValueKey('save-service-address'),
        focusNode: _saveFocus,
        onPressed: _busy ? null : _save,
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check_rounded),
        label: Text(_busy ? 'Checking…' : 'Save'),
      ),
    ],
  );
}

class _AccountRemovalDialog extends StatefulWidget {
  const _AccountRemovalDialog({required this.username, required this.active});

  final String username;
  final bool active;

  @override
  State<_AccountRemovalDialog> createState() => _AccountRemovalDialogState();
}

class _AccountRemovalDialogState extends State<_AccountRemovalDialog> {
  final _cancelFocus = FocusNode(debugLabel: 'Cancel account removal');
  final _removeFocus = FocusNode(debugLabel: 'Confirm account removal');

  KeyEventResult _move(KeyEvent event, FocusNode target) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.arrowLeft &&
        event.logicalKey != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }
    target.requestFocus();
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _cancelFocus.dispose();
    _removeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const danger = Color(0xFFFF5277);
    return AlertDialog(
      backgroundColor: surface,
      title: const Text('Remove account?'),
      content: Text(
        '“${widget.username}” will be removed from this device.'
        '${widget.active ? '\n\nYou’re currently signed in to it — you’ll be switched out.' : ''}',
      ),
      actions: [
        RemoteTap(
          autofocus: true,
          focusNode: _cancelFocus,
          semanticLabel: 'Cancel account removal',
          onKeyEvent: (_, event) => _move(event, _removeFocus),
          onTap: () => Navigator.pop(context, false),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
            child: Text(
              'Cancel',
              style: TextStyle(color: muted, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        RemoteTap(
          focusNode: _removeFocus,
          semanticLabel: 'Confirm account removal',
          focusRadius: 12,
          focusRingColor: Colors.white,
          onKeyEvent: (_, event) => _move(event, _cancelFocus),
          onTap: () => Navigator.pop(context, true),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: danger,
              borderRadius: BorderRadius.circular(lumenCorner(12)),
            ),
            child: Text(
              'Remove',
              style: TextStyle(
                color: foregroundFor(danger),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// App-wide, offline-safe type selector. Font files are bundled in the app so
/// the setting behaves the same on TVs without network access.
class _FontSelector extends StatefulWidget {
  const _FontSelector({
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
  State<_FontSelector> createState() => _FontSelectorState();
}

class _FontSelectorState extends State<_FontSelector> {
  int _columns = LumenFont.values.length;
  late final List<FocusNode> _focusNodes = [
    widget.entryFocusNode,
    for (final option in LumenFont.values.skip(1))
      FocusNode(debugLabel: '${option.label} font'),
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
      final target = index - _columns;
      (target >= 0 ? _focusNodes[target] : widget.upFocusNode).requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final target = index + _columns;
      (target < _focusNodes.length ? _focusNodes[target] : widget.downFocusNode)
          .requestFocus();
      return KeyEventResult.handled;
    }
    final delta = event.logicalKey == LogicalKeyboardKey.arrowLeft
        ? -1
        : event.logicalKey == LogicalKeyboardKey.arrowRight
        ? 1
        : 0;
    if (delta == 0) return KeyEventResult.ignored;
    final target = index + delta;
    final sameRow =
        target >= 0 &&
        target < _focusNodes.length &&
        target ~/ _columns == index ~/ _columns;
    if (sameRow) {
      _focusNodes[target].requestFocus();
    } else if (target < 0 &&
        widget.leftExitFocusNode?.canRequestFocus == true) {
      widget.leftExitFocusNode!.requestFocus();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LumenFont>(
      valueListenable: ThemeController.instance.font,
      builder: (context, current, _) => LayoutBuilder(
        builder: (context, constraints) {
          _columns = constraints.maxWidth >= 300 ? LumenFont.values.length : 2;
          const gap = 8.0;
          final itemWidth =
              (constraints.maxWidth - gap * (_columns - 1)) / _columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var index = 0; index < LumenFont.values.length; index++)
                SizedBox(
                  width: itemWidth,
                  child: RemoteTap(
                    focusNode: _focusNodes[index],
                    focusRadius: 14,
                    onKeyEvent: (_, event) => _route(index, event),
                    semanticLabel: '${LumenFont.values[index].label} font',
                    onTap: () => ThemeController.instance.setFont(
                      LumenFont.values[index],
                    ),
                    child: AnimatedContainer(
                      key: ValueKey(
                        'profile-font-${LumenFont.values[index].name}',
                      ),
                      duration: lumenMotion,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: current == LumenFont.values[index]
                            ? accent.withValues(alpha: isDark ? .16 : .22)
                            : surfaceHi.withValues(alpha: .55),
                        borderRadius: BorderRadius.circular(lumenCorner(14)),
                        border: Border.all(
                          color: current == LumenFont.values[index]
                              ? accentInk
                              : line,
                          width: current == LumenFont.values[index] ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            LumenFont.values[index].label,
                            maxLines: 1,
                            style: TextStyle(
                              fontFamily: LumenFont.values[index].family,
                              color: textHi,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            LumenFont.values[index].description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: muted, fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A shared, remote-safe selector for visual system preferences. Keeping
/// corner and focus choices on the same primitive prevents their interaction,
/// semantics and D-pad behavior from drifting apart.
class _PreferenceSelector<T> extends StatefulWidget {
  const _PreferenceSelector({
    required this.entryFocusNode,
    required this.upFocusNode,
    required this.downFocusNode,
    required this.values,
    required this.current,
    required this.semanticSuffix,
    required this.keyPrefix,
    required this.labelOf,
    required this.descriptionOf,
    required this.onSelected,
    this.previewBuilder,
    this.leftExitFocusNode,
  });

  final FocusNode entryFocusNode;
  final FocusNode upFocusNode;
  final FocusNode downFocusNode;
  final FocusNode? leftExitFocusNode;
  final List<T> values;
  final ValueNotifier<T> current;
  final String semanticSuffix;
  final String keyPrefix;
  final String Function(T) labelOf;
  final String Function(T) descriptionOf;
  final ValueChanged<T> onSelected;
  final Widget Function(T value, bool selected)? previewBuilder;

  @override
  State<_PreferenceSelector<T>> createState() => _PreferenceSelectorState<T>();
}

class _PreferenceSelectorState<T> extends State<_PreferenceSelector<T>> {
  int _columns = 3;
  late final List<FocusNode> _focusNodes = [
    widget.entryFocusNode,
    for (final value in widget.values.skip(1))
      FocusNode(
        debugLabel:
            '${widget.labelOf(value)} ${widget.semanticSuffix.toLowerCase()}',
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
      final target = index - _columns;
      (target >= 0 ? _focusNodes[target] : widget.upFocusNode).requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final target = index + _columns;
      (target < _focusNodes.length ? _focusNodes[target] : widget.downFocusNode)
          .requestFocus();
      return KeyEventResult.handled;
    }
    final delta = event.logicalKey == LogicalKeyboardKey.arrowLeft
        ? -1
        : event.logicalKey == LogicalKeyboardKey.arrowRight
        ? 1
        : 0;
    if (delta == 0) return KeyEventResult.ignored;
    final target = index + delta;
    final sameRow =
        target >= 0 &&
        target < _focusNodes.length &&
        target ~/ _columns == index ~/ _columns;
    if (sameRow) {
      _focusNodes[target].requestFocus();
    } else if (target < 0 &&
        widget.leftExitFocusNode?.canRequestFocus == true) {
      widget.leftExitFocusNode!.requestFocus();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<T>(
    valueListenable: widget.current,
    builder: (context, current, _) => LayoutBuilder(
      builder: (context, constraints) {
        _columns = constraints.maxWidth >= 300
            ? widget.values.length
            : 2.clamp(1, widget.values.length);
        const gap = 8.0;
        final itemWidth =
            (constraints.maxWidth - gap * (_columns - 1)) / _columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var index = 0; index < widget.values.length; index++)
              SizedBox(
                width: itemWidth,
                child: RemoteTap(
                  focusNode: _focusNodes[index],
                  focusRadius: 14,
                  semanticLabel:
                      '${widget.labelOf(widget.values[index])} ${widget.semanticSuffix}',
                  onKeyEvent: (_, event) => _route(index, event),
                  onTap: () => widget.onSelected(widget.values[index]),
                  child: AnimatedContainer(
                    key: ValueKey(
                      '${widget.keyPrefix}-${widget.labelOf(widget.values[index]).toLowerCase()}',
                    ),
                    duration: lumenMotion,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: current == widget.values[index]
                          ? accent.withValues(alpha: isDark ? .16 : .22)
                          : surfaceHi.withValues(alpha: .55),
                      borderRadius: BorderRadius.circular(lumenCorner(14)),
                      border: Border.all(
                        color: current == widget.values[index]
                            ? accentInk
                            : line,
                        width: current == widget.values[index] ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        if (widget.previewBuilder != null) ...[
                          widget.previewBuilder!(
                            widget.values[index],
                            current == widget.values[index],
                          ),
                          const SizedBox(width: 9),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.labelOf(widget.values[index]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.descriptionOf(widget.values[index]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: muted, fontSize: 9.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
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
            borderRadius: BorderRadius.circular(lumenCorner(18)),
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
                        borderRadius: BorderRadius.circular(lumenCorner(14)),
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
  int _columns = accentSchemes.length + 1;
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
      final target = index - _columns;
      (target >= 0 ? _focusNodes[target] : widget.upFocusNode).requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final target = index + _columns;
      (target < _focusNodes.length ? _focusNodes[target] : widget.downFocusNode)
          .requestFocus();
      return KeyEventResult.handled;
    }
    final delta = event.logicalKey == LogicalKeyboardKey.arrowLeft
        ? -1
        : event.logicalKey == LogicalKeyboardKey.arrowRight
        ? 1
        : 0;
    if (delta == 0) return KeyEventResult.ignored;
    final target = index + delta;
    final sameRow =
        target >= 0 &&
        target < _focusNodes.length &&
        target ~/ _columns == index ~/ _columns;
    if (sameRow) {
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
    final hueFocus = FocusNode(debugLabel: 'Custom accent hue');
    final saturationFocus = FocusNode(debugLabel: 'Custom accent saturation');
    final brightnessFocus = FocusNode(debugLabel: 'Custom accent brightness');
    final cancelFocus = FocusNode(debugLabel: 'Custom accent cancel');
    final applyFocus = FocusNode(debugLabel: 'Custom accent apply');

    KeyEventResult actionKey(
      KeyEvent event, {
      required FocusNode left,
      required FocusNode right,
    }) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        brightnessFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        left.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        right.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    try {
      final result = await showDialog<Color>(
        context: context,
        requestFocus: true,
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
                    key: const ValueKey('custom-accent-preview'),
                    height: 54,
                    decoration: BoxDecoration(
                      color: picked,
                      borderRadius: BorderRadius.circular(lumenCorner(14)),
                      border: Border.all(color: Colors.white24),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Up/Down selects a control. Left/Right adjusts it.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  _colorSlider(
                    label: 'Hue',
                    value: hsv.hue,
                    max: 360,
                    divisions: 360,
                    step: 5,
                    focusNode: hueFocus,
                    autofocus: true,
                    onDown: saturationFocus,
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
                    step: 2,
                    focusNode: saturationFocus,
                    onUp: hueFocus,
                    onDown: brightnessFocus,
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
                    step: 2,
                    focusNode: brightnessFocus,
                    onUp: saturationFocus,
                    onDown: applyFocus,
                    onChanged: (value) => setLocal(() {
                      hsv = hsv.withValue(value / 100);
                      picked = hsv.toColor();
                    }),
                  ),
                ],
              ),
            ),
            actions: [
              RemoteTap(
                focusNode: cancelFocus,
                semanticLabel: 'Cancel custom accent',
                focusRadius: 22,
                onKeyEvent: (_, event) =>
                    actionKey(event, left: cancelFocus, right: applyFocus),
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: surfaceHi,
                    borderRadius: BorderRadius.circular(lumenCorner(22)),
                    border: Border.all(color: line),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: textHi,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              RemoteTap(
                focusNode: applyFocus,
                semanticLabel: 'Apply custom accent',
                focusRadius: 22,
                onKeyEvent: (_, event) =>
                    actionKey(event, left: cancelFocus, right: applyFocus),
                onTap: () => Navigator.pop(ctx, picked),
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: picked,
                    borderRadius: BorderRadius.circular(lumenCorner(22)),
                  ),
                  child: Text(
                    'Apply',
                    style: TextStyle(
                      color: foregroundFor(picked),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      if (result != null && mounted) {
        await ThemeController.instance.setAccent(result);
      }
    } finally {
      hueFocus.dispose();
      saturationFocus.dispose();
      brightnessFocus.dispose();
      cancelFocus.dispose();
      applyFocus.dispose();
    }
  }

  Widget _colorSlider({
    required String label,
    required double value,
    required double max,
    required int divisions,
    required double step,
    required FocusNode focusNode,
    required FocusNode onDown,
    FocusNode? onUp,
    bool autofocus = false,
    required ValueChanged<double> onChanged,
  }) {
    KeyEventResult handleKey(FocusNode _, KeyEvent event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        onUp?.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        onDown.requestFocus();
        return KeyEventResult.handled;
      }
      final direction = event.logicalKey == LogicalKeyboardKey.arrowLeft
          ? -1
          : event.logicalKey == LogicalKeyboardKey.arrowRight
          ? 1
          : 0;
      if (direction == 0) return KeyEventResult.ignored;
      final next = (value + (step * direction)).clamp(0, max).toDouble();
      if (next != value) onChanged(next);
      return KeyEventResult.handled;
    }

    return Focus(
      focusNode: focusNode,
      autofocus: autofocus,
      onKeyEvent: handleKey,
      descendantsAreFocusable: false,
      child: AnimatedBuilder(
        animation: focusNode,
        builder: (context, child) {
          final focused = focusNode.hasFocus;
          return Listener(
            onPointerDown: (_) => focusNode.requestFocus(),
            child: AnimatedContainer(
              key: ValueKey('custom-accent-${label.toLowerCase()}'),
              duration: lumenMotionFast,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: focused
                    ? accentInk.withValues(alpha: isDark ? .14 : .08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(lumenCorner(12)),
                border: Border.all(
                  color: focused ? accentInk : Colors.transparent,
                  width: focused ? activeFocusStyle.ringWidth : 1,
                ),
                boxShadow: focused ? lumenFocusShadows(accentInk) : null,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 82,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: focused ? textHi : muted,
                        fontSize: 12,
                        fontWeight: focused ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
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
                      style: TextStyle(
                        color: focused ? textHi : muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

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
        return LayoutBuilder(
          builder: (context, constraints) {
            final optionCount = accentSchemes.length + 1;
            _columns = constraints.maxWidth >= 680
                ? optionCount
                : constraints.maxWidth >= 300
                ? 3
                : 2;
            const gap = 10.0;
            final itemWidth =
                (constraints.maxWidth - gap * (_columns - 1)) / _columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var index = 0; index < accentSchemes.length; index++)
                  _schemeChoice(
                    width: itemWidth,
                    label: accentSchemes[index].name,
                    color: accentSchemes[index].color,
                    selected: accentSchemes[index].color.toARGB32() == cur,
                    onTap: () => ThemeController.instance.setAccent(
                      accentSchemes[index].color,
                    ),
                    focusNode: _focusNodes[index],
                    onKeyEvent: (_, event) => _route(index, event),
                  ),
                RemoteTap(
                  focusNode: _focusNodes.last,
                  onKeyEvent: (_, event) =>
                      _route(_focusNodes.length - 1, event),
                  semanticLabel: 'Custom accent',
                  onTap: () => _pickCustom(context, current),
                  child: Container(
                    key: const ValueKey('profile-accent-custom'),
                    width: itemWidth,
                    height: 64,
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    decoration: BoxDecoration(
                      color: isCustom
                          ? accentInk.withValues(alpha: isDark ? 0.16 : 0.10)
                          : surfaceHi,
                      borderRadius: BorderRadius.circular(lumenCorner(14)),
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
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: SweepGradient(
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
      },
    );
  }

  Widget _schemeChoice({
    required double width,
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
        width: width,
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: selected
              ? accentInk.withValues(alpha: isDark ? 0.16 : 0.10)
              : surfaceHi,
          borderRadius: BorderRadius.circular(lumenCorner(14)),
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
