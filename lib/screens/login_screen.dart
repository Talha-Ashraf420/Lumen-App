import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../distribution.dart';
import '../responsive.dart';
import '../store.dart';
import '../widgets.dart';
import '../theme.dart';
import '../xtream.dart';

typedef LoginClientFactory = XtreamClient Function(XtreamCredentials);
typedef LoginCredentialSaver = Future<void> Function(XtreamCredentials);

class _LoginCancelled implements Exception {
  const _LoginCancelled();
}

class LoginScreen extends StatefulWidget {
  final void Function(XtreamCredentials) onLogin;
  final LoginClientFactory? clientFactory;
  final LoginCredentialSaver? credentialSaver;
  final Duration connectionTimeout;
  final Duration storageTimeout;

  const LoginScreen({
    super.key,
    required this.onLogin,
    this.clientFactory,
    this.credentialSaver,
    this.connectionTimeout = const Duration(seconds: 18),
    this.storageTimeout = const Duration(seconds: 6),
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  late final FocusNode _urlFocus;
  late final FocusNode _userFocus;
  late final FocusNode _passFocus;
  late final FocusNode _submitFocus;
  late final FocusNode _playlistFocus;
  late final FocusNode _demoFocus;
  final Map<String, FocusNode> _profileFocus = {};
  bool _busy = false;
  String? _error;
  String? _status;
  List<XtreamCredentials> _profiles = [];
  XtreamClient? _pendingClient;
  Completer<dynamic>? _pendingWait;
  Timer? _pendingDeadline;
  int _connectAttempt = 0;

  @override
  void initState() {
    super.initState();
    _urlFocus = _createFocusNode('login-url');
    _userFocus = _createFocusNode('login-username');
    _passFocus = _createFocusNode('login-password');
    _submitFocus = _createFocusNode('login-submit');
    _playlistFocus = _createFocusNode('login-playlist');
    _demoFocus = _createFocusNode('login-demo');
    _urlFocus.onKeyEvent = (_, event) =>
        _moveFromField(event, up: _lastProfileFocus, down: _userFocus);
    _userFocus.onKeyEvent = (_, event) => _moveFromField(
      event,
      up: _urlFocus,
      right: _passFocus,
      down: _submitFocus,
    );
    _passFocus.onKeyEvent = (_, event) => _moveFromField(
      event,
      up: _urlFocus,
      left: _userFocus,
      down: _submitFocus,
    );
    _submitFocus.onKeyEvent = (_, event) =>
        _moveFromControl(event, up: _userFocus, down: _playlistFocus);
    _playlistFocus.onKeyEvent = (_, event) =>
        _moveFromControl(event, up: _submitFocus, down: _demoFocus);
    _demoFocus.onKeyEvent = (_, event) =>
        _moveFromControl(event, up: _playlistFocus);
    Store.savedProfiles().then((profiles) {
      if (!mounted) return;
      _syncProfileFocus(profiles);
      setState(() => _profiles = profiles);
    });
  }

  FocusNode _createFocusNode(String label) {
    late final FocusNode node;
    node = FocusNode(debugLabel: label);
    node.addListener(() {
      if (!node.hasFocus) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final focusContext = node.context;
        if (!mounted || focusContext == null) return;
        Scrollable.ensureVisible(
          focusContext,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      });
    });
    return node;
  }

  FocusNode? get _lastProfileFocus =>
      _profiles.isEmpty ? null : _profileFocus[_profileKey(_profiles.last)];

  String _profileKey(XtreamCredentials profile) =>
      '${profile.baseUrl}|${profile.username}|${profile.m3uUrl}|${profile.demo}';

  void _syncProfileFocus(List<XtreamCredentials> profiles) {
    final liveKeys = profiles.map(_profileKey).toSet();
    final removed = _profileFocus.keys
        .where((key) => !liveKeys.contains(key))
        .toList();
    for (final key in removed) {
      _profileFocus.remove(key)?.dispose();
    }
    for (var index = 0; index < profiles.length; index++) {
      final key = _profileKey(profiles[index]);
      final node = _profileFocus.putIfAbsent(
        key,
        () => _createFocusNode('saved-profile-$index'),
      );
      node.onKeyEvent = (_, event) => _moveFromControl(
        event,
        up: index == 0 ? null : _profileFocus[_profileKey(profiles[index - 1])],
        down: index == profiles.length - 1
            ? _urlFocus
            : _profileFocus[_profileKey(profiles[index + 1])],
      );
    }
  }

  bool _isNavigationKeyEvent(KeyEvent event) =>
      event is KeyDownEvent || event is KeyRepeatEvent;

  KeyEventResult _moveFromField(
    KeyEvent event, {
    FocusNode? up,
    FocusNode? down,
    FocusNode? left,
    FocusNode? right,
  }) {
    if (!_isNavigationKeyEvent(event)) return KeyEventResult.ignored;
    final key = event.logicalKey;
    FocusNode? target;
    if (key == LogicalKeyboardKey.arrowUp) {
      target = up;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      target = down;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      target = left;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      target = right;
    }
    if (target == null) return KeyEventResult.ignored;
    target.requestFocus();
    return KeyEventResult.handled;
  }

  KeyEventResult _moveFromControl(
    KeyEvent event, {
    FocusNode? up,
    FocusNode? down,
  }) {
    if (!_isNavigationKeyEvent(event)) return KeyEventResult.ignored;
    FocusNode? target;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      target = up;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      target = down;
    }
    if (target == null) return KeyEventResult.ignored;
    target.requestFocus();
    return KeyEventResult.handled;
  }

  Future<void> _connect(XtreamCredentials c) async {
    final validationError = _validate(c);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    final attempt = ++_connectAttempt;
    _pendingClient?.close();
    final client = (widget.clientFactory ?? XtreamClient.new)(c);
    _pendingClient = client;
    setState(() {
      _busy = true;
      _error = null;
      _status = c.isDemo ? 'Opening offline demo…' : 'Checking provider…';
    });
    var authenticated = false;
    try {
      await _bounded(
        client.authenticate(),
        widget.connectionTimeout,
        'The provider did not respond within '
        '${_durationLabel(widget.connectionTimeout)}. '
        'Check the server address or try again.',
      );
      if (!mounted || attempt != _connectAttempt) return;
      setState(
        () => _status = c.isDemo
            ? 'Preparing sample library…'
            : 'Securing this account…',
      );
      final save = widget.credentialSaver ?? Store.setActive;
      await _bounded(
        save(c),
        widget.storageTimeout,
        'Lumen reached the provider but could not save this account. '
        'Restart the app and try again.',
      );
      if (!mounted || attempt != _connectAttempt) return;
      authenticated = true;
      setState(() => _status = 'Opening your library…');
      widget.onLogin(c);
      if (mounted && attempt == _connectAttempt) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    } catch (e, stack) {
      if (!mounted || attempt != _connectAttempt) return;
      // Authentication and persistence have already succeeded. A failure in
      // the host's screen transition is not a provider/login failure, and
      // reporting it as one leaves users retrying valid credentials that will
      // appear signed in after restart.
      if (authenticated) {
        debugPrint('Post-login transition failed: $e\n$stack');
        setState(() {
          _busy = false;
          _status = null;
          _error = null;
        });
        return;
      }
      setState(() {
        _error = safeProviderError(e);
        _busy = false;
        _status = null;
      });
    } finally {
      client.close();
      if (identical(_pendingClient, client)) _pendingClient = null;
      if (!authenticated && mounted && attempt == _connectAttempt && _busy) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  String _durationLabel(Duration value) {
    final seconds = value.inSeconds.clamp(1, 999);
    return '$seconds ${seconds == 1 ? 'second' : 'seconds'}';
  }

  Future<T> _bounded<T>(
    Future<T> operation,
    Duration timeout,
    String timeoutMessage,
  ) {
    final result = Completer<dynamic>();
    _pendingWait = result;
    late final Timer deadline;
    deadline = Timer(timeout, () {
      if (!result.isCompleted) {
        result.completeError(XtreamException(timeoutMessage));
      }
    });
    _pendingDeadline = deadline;
    operation.then(
      (value) {
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    return result.future.then((value) => value as T).whenComplete(() {
      deadline.cancel();
      if (identical(_pendingDeadline, deadline)) _pendingDeadline = null;
      if (identical(_pendingWait, result)) _pendingWait = null;
    });
  }

  void _cancelPendingWait() {
    _pendingDeadline?.cancel();
    _pendingDeadline = null;
    final wait = _pendingWait;
    _pendingWait = null;
    if (wait != null && !wait.isCompleted) {
      wait.completeError(const _LoginCancelled());
    }
  }

  String? _validate(XtreamCredentials credentials) {
    if (credentials.isDemo) return null;
    if (credentials.isM3u) {
      final value = credentials.m3uUrl?.trim() ?? '';
      if (value.isEmpty || Uri.tryParse(value)?.host.isEmpty != false) {
        return 'Enter a valid playlist URL.';
      }
      return null;
    }
    if (credentials.baseUrl.trim().isEmpty ||
        Uri.tryParse(credentials.baseUrl)?.host.isEmpty != false) {
      return 'Enter a valid server address.';
    }
    if (credentials.username.trim().isEmpty || credentials.password.isEmpty) {
      return 'Enter both the username and password.';
    }
    return null;
  }

  void _cancelConnect() {
    if (!_busy) return;
    _connectAttempt++;
    _cancelPendingWait();
    _pendingClient?.close();
    _pendingClient = null;
    setState(() {
      _busy = false;
      _status = null;
      _error = 'Connection cancelled. Check the details and try again.';
    });
  }

  Future<void> _startDemo() => _connect(XtreamCredentials.demoProfile);

  @override
  void dispose() {
    _connectAttempt++;
    _cancelPendingWait();
    _pendingClient?.close();
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    _urlFocus.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    _submitFocus.dispose();
    _playlistFocus.dispose();
    _demoFocus.dispose();
    for (final node in _profileFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Add a playlist. Two cases are handled:
  ///  • an Xtream-backed link (get.php?username=…&password=…) → full catalog+EPG;
  ///  • a plain .m3u playlist URL (+ optional XMLTV EPG URL) → live channels.
  Future<void> _pasteUrl() async {
    final urlCtrl = TextEditingController();
    final epgCtrl = TextEditingController();
    String? err;
    final creds = await showDialog<XtreamCredentials>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: surface,
          title: const Text('Add M3U / playlist'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: urlCtrl,
                autocorrect: false,
                enableSuggestions: false,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Playlist URL',
                  hintText: 'https://…/playlist.m3u  or  get.php?username=…',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: epgCtrl,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'XMLTV EPG URL (optional)',
                  hintText: 'https://…/epg.xml',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tip: Xtream links bring the full catalog. Plain .m3u links load live channels.',
                style: TextStyle(color: subtle, fontSize: 11.5),
              ),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    err!,
                    style: const TextStyle(
                      color: Color(0xFFFFB4B4),
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: muted)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: bg,
              ),
              onPressed: () {
                final raw = urlCtrl.text.trim();
                if (raw.isEmpty) {
                  setLocal(() => err = 'Enter a playlist URL.');
                  return;
                }
                if (!isAllowedProviderUrl(raw)) {
                  setLocal(() => err = 'Enter a valid HTTP or HTTPS URL.');
                  return;
                }
                // Xtream-backed link → full login.
                final x = credentialsFromUrl(raw);
                if (x != null) {
                  Navigator.pop(ctx, x);
                  return;
                }
                // Plain M3U playlist.
                final epg = epgCtrl.text.trim();
                if (epg.isNotEmpty && !isAllowedProviderUrl(epg)) {
                  setLocal(() => err = 'Enter a valid HTTP or HTTPS EPG URL.');
                  return;
                }
                Navigator.pop(
                  ctx,
                  XtreamCredentials(
                    baseUrl: raw,
                    username: Uri.tryParse(raw)?.host ?? 'playlist',
                    password: '',
                    m3uUrl: raw,
                    epgUrl: epg.isEmpty ? null : epg,
                  ),
                );
              },
              child: const Text('Connect'),
            ),
          ],
        ),
      ),
    );
    if (creds != null) _connect(creds);
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    return Scaffold(
      body: Stack(
        children: [
          Aurora(),
          Positioned(
            top: -120,
            left: -80,
            child: _blob(accent.withValues(alpha: 0.18), 320),
          ),
          Positioned(
            bottom: -100,
            right: -60,
            child: _blob(accent2.withValues(alpha: 0.12), 280),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(child: _brandPanel()),
                          const SizedBox(width: 56),
                          SizedBox(width: 440, child: _formCard()),
                        ],
                      )
                    : _formCard(showWordmark: true),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _brandPanel() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Wordmark(size: 46),
        const SizedBox(height: 34),
        Text(
          'Your screen.\nYour signal.',
          style: kDisplay().copyWith(fontSize: 52, height: 0.98),
        ),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 470),
          child: Text(
            'Bring an authorized provider or playlist and turn it into a calm, personal cinema across phone, desktop and TV.',
            style: TextStyle(color: muted, fontSize: 15, height: 1.55),
          ),
        ),
        const SizedBox(height: 30),
        const Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _TrustPill(
              icon: Icons.lock_outline_rounded,
              label: 'Private by default',
            ),
            _TrustPill(icon: Icons.tv_rounded, label: 'Remote ready'),
            _TrustPill(icon: Icons.download_rounded, label: 'Offline playback'),
          ],
        ),
      ],
    ),
  );

  Widget _formCard({bool showWordmark = false}) => Glass(
    radius: 28,
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showWordmark) ...[
          const Center(child: Wordmark(size: 38)),
          const SizedBox(height: 24),
        ],
        Text('CONNECT YOUR LIBRARY', style: kSection(color: accentInk)),
        const SizedBox(height: 7),
        const Text(
          'Welcome to Lumen',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Use provider credentials or bring a playlist URL.',
          style: TextStyle(color: muted, fontSize: 13),
        ),
        const SizedBox(height: 20),
        if (_profiles.isNotEmpty) ...[
          Text('SAVED ACCOUNTS', style: kSection()),
          const SizedBox(height: 9),
          ..._profiles.map(
            (profile) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ProfileTile(
                profile: profile,
                busy: _busy,
                focusNode: _profileFocus[_profileKey(profile)],
                onTap: () => _connect(profile),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(child: Divider(color: line)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('OR NEW ACCOUNT', style: kSection()),
                ),
                Expanded(child: Divider(color: line)),
              ],
            ),
          ),
        ],
        _field(
          _url,
          'Server URL',
          focusNode: _urlFocus,
          nextFocus: _userFocus,
          hint: 'https://host:443',
        ),
        const SizedBox(height: 11),
        Row(
          children: [
            Expanded(
              child: _field(
                _user,
                'Username',
                focusNode: _userFocus,
                nextFocus: _passFocus,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _field(
                _pass,
                'Password',
                focusNode: _passFocus,
                nextFocus: _submitFocus,
                obscure: true,
              ),
            ),
          ],
        ),
        if (_url.text.trim().toLowerCase().startsWith('http://')) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFB84D).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFFB84D).withValues(alpha: 0.24),
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFFFC66B),
                  size: 18,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Legacy HTTP is supported, but it does not encrypt your '
                    'provider credentials or viewing traffic.',
                    style: TextStyle(
                      color: Color(0xFFFFD9A0),
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFFFFB4B4), fontSize: 12.5),
            ),
          ),
        ],
        const SizedBox(height: 15),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            focusNode: _submitFocus,
            autofocus: true,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: onAccent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _busy
                ? null
                : () => _connect(
                    XtreamCredentials(
                      baseUrl: normalizeBaseUrl(_url.text),
                      username: _user.text.trim(),
                      password: _pass.text.trim(),
                    ),
                  ),
            icon: _busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: onAccent,
                    ),
                  )
                : const Icon(Icons.arrow_forward_rounded, size: 19),
            label: Text(
              _status ?? 'Enter Lumen',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: TextButton.icon(
            focusNode: _playlistFocus,
            onPressed: _busy ? _cancelConnect : _pasteUrl,
            icon: Icon(
              _busy ? Icons.close_rounded : Icons.link_rounded,
              size: 18,
              color: _busy ? muted : accentInk,
            ),
            label: Text(
              _busy ? 'Cancel connection' : 'Connect a playlist URL instead',
              style: TextStyle(
                color: _busy ? muted : accentInk,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (!_busy) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(child: Divider(color: line)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('NO PROVIDER YET?', style: kSection()),
                ),
                Expanded(child: Divider(color: line)),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              focusNode: _demoFocus,
              onPressed: _startDemo,
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text('Explore offline demo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: accentInk,
                side: BorderSide(color: accentInk.withValues(alpha: .45)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'A fictional sample library. No account or internet required.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subtle, fontSize: 11.5),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_rounded, color: subtle, size: 12),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                'Credentials stay encrypted on this device.',
                textAlign: TextAlign.center,
                style: TextStyle(color: subtle, fontSize: 11.5),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _field(
    TextEditingController c,
    String label, {
    required FocusNode focusNode,
    required FocusNode nextFocus,
    String? hint,
    bool obscure = false,
  }) {
    return TextField(
      controller: c,
      focusNode: focusNode,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.next,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => nextFocus.requestFocus(),
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
  final FocusNode? focusNode;
  final VoidCallback onTap;
  const _ProfileTile({
    required this.profile,
    required this.busy,
    required this.focusNode,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return RemoteTap(
      onTap: busy ? null : onTap,
      focusNode: focusNode,
      focusRadius: 15,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: surfaceHi.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: line),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accentInk.withValues(alpha: isDark ? 0.13 : 0.09),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.tv_rounded, color: accentInk, size: 19),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.isDemo ? 'Demo Mode' : profile.username,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    profile.isDemo
                        ? 'Offline sample library'
                        : profile.baseUrl.replaceFirst(
                            RegExp(r'^https?://'),
                            '',
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: subtle, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_rounded, size: 17, color: accentInk),
          ],
        ),
      ),
    );
  }
}

class _TrustPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _TrustPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: surfaceHi.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: line),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: accentInk, size: 16),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
      ],
    ),
  );
}
