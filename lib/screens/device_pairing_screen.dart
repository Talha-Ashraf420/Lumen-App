import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../device_pairing.dart';
import '../models.dart';
import '../responsive.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';

/// Both entry points use the same responsive, scrollable page shell.
Widget _page(BuildContext context, String title, List<Widget> children) =>
    Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: pageInsets(context),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );

Widget _message(String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 12),
  child: Text(value, textAlign: TextAlign.center),
);

class TvPairingScreen extends StatefulWidget {
  final Future<List<String>> Function()? addresses;
  final Future<PairingReceiver> Function(String)? receiverFactory;
  const TvPairingScreen({super.key, this.addresses, this.receiverFactory});
  @override
  State<TvPairingScreen> createState() => _TvPairingScreenState();
}

class _TvPairingScreenState extends State<TvPairingScreen>
    with WidgetsBindingObserver {
  PairingReceiver? _receiver;
  List<String> _addresses = [];
  String? _address;
  String? _error;
  bool _starting = false;
  int _generation = 0;
  Timer? _ticker;
  final _rejectFocus = FocusNode(debugLabel: 'Reject phone setup');
  final _approveFocus = FocusNode(debugLabel: 'Approve phone setup');
  PairingState? _previousState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  Future<void> _start() async {
    final generation = ++_generation;
    _ticker?.cancel();
    _receiver?.removeListener(_changed);
    _receiver?.dispose();
    _receiver = null;
    _previousState = null;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final addresses =
          await (widget.addresses ?? PairingReceiver.localAddresses)();
      if (!mounted || generation != _generation) return;
      if (addresses.isEmpty) throw const FormatException();
      _addresses = addresses;
      _address = addresses.contains(_address) ? _address : addresses.first;
      final receiver = await (widget.receiverFactory ?? PairingReceiver.start)(
        _address!,
      );
      if (!mounted || generation != _generation) {
        receiver.dispose();
        return;
      }
      _receiver = receiver..addListener(_changed);
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      setState(() => _starting = false);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _starting = false;
        _error =
            'Could not start local setup. Connect the TV to your home Wi-Fi or Ethernet, then try again. You can still sign in manually.';
      });
    }
  }

  void _changed() {
    if (!mounted) return;
    final state = _receiver?.state;
    if (state == PairingState.pending && state != _previousState) {
      // Default to reject, never approve an unsolicited proposal accidentally.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _rejectFocus.requestFocus();
          final c = _rejectFocus.context;
          if (c != null) Scrollable.ensureVisible(c);
        }
      });
    }
    _previousState = state;
    setState(() {});
  }

  Future<void> _approve() async {
    final credentials = await _receiver?.approve();
    if (mounted && credentials != null) Navigator.pop(context, credentials);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      ++_generation;
      _ticker?.cancel();
      _receiver?.close();
      if (mounted) {
        setState(() {
          _starting = false;
          _error = 'Setup paused. Generate a new QR when you are ready.';
        });
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _receiver?.removeListener(_changed);
    _receiver?.dispose();
    _rejectFocus.dispose();
    _approveFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final receiver = _receiver;
    final state = receiver?.state;
    final seconds = receiver == null
        ? 0
        : receiver.ticket.expires
              .difference(DateTime.now())
              .inSeconds
              .clamp(0, 180);
    return _page(context, 'Connect using phone', [
      if (_starting) const LinearProgressIndicator(),
      if (_error != null) _message(_error!),
      if (receiver != null && state == PairingState.waiting) ...[
        _message(
          'On your phone, open Lumen → Profile → Set up a TV.\nChoose Scan TV QR. Both devices must use the same home network.',
        ),
        Center(
          child: Semantics(
            label: 'Temporary Lumen pairing QR. Scan with the Lumen phone app.',
            child: SizedBox(
              width: 300,
              height: 300,
              child: QrImageView(
                data: receiver.ticket.link,
                backgroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
                version: QrVersions.auto,
              ),
            ),
          ),
        ),
        _message(
          'Expires in ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')} · ${receiver.ticket.host}',
        ),
        _message(
          'No provider password is in this QR. Keep it private: it authorizes an encrypted setup request, which you must approve here.',
        ),
        if (_addresses.length > 1)
          DropdownButtonFormField<String>(
            initialValue: _address,
            decoration: const InputDecoration(labelText: 'TV network address'),
            items: _addresses
                .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                .toList(),
            onChanged: (value) {
              _address = value;
              unawaited(_start());
            },
          ),
      ],
      if (receiver != null && state == PairingState.pending) ...[
        Text(
          'Confirm on this TV',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        _message(
          'Only approve if you started this setup and your phone shows the same code.',
        ),
        Text(
          receiver.comparisonCode!,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineLarge?.copyWith(letterSpacing: 8),
        ),
        _message('Provider: ${receiver.providerHost}'),
        _message(
          'The TV will verify this account with the provider after you approve.',
        ),
        OutlinedButton(
          focusNode: _rejectFocus,
          onPressed: receiver.reject,
          child: const Text('Reject'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          focusNode: _approveFocus,
          onPressed: _approve,
          child: const Text('Approve and connect'),
        ),
      ],
      if (state == PairingState.approved)
        _message('Approved. Continuing to provider sign-in…'),
      if (state == PairingState.rejected)
        _message('Request rejected. No account was saved.'),
      if (state == PairingState.expired)
        _message('This QR has expired. No account was saved.'),
      if (!_starting &&
          state != PairingState.pending &&
          state != PairingState.approved) ...[
        const SizedBox(height: 16),
        OutlinedButton(onPressed: _start, child: const Text('Generate new QR')),
      ],
      const SizedBox(height: 12),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel and use manual login'),
      ),
    ]);
  }
}

class PhonePairingScreen extends StatefulWidget {
  final Future<List<XtreamCredentials>> Function()? profiles;
  final Future<String?> Function(BuildContext)? scan;
  const PhonePairingScreen({super.key, this.profiles, this.scan});
  @override
  State<PhonePairingScreen> createState() => _PhonePairingScreenState();
}

class _PhonePairingScreenState extends State<PhonePairingScreen>
    with WidgetsBindingObserver {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _playlist = TextEditingController();
  List<XtreamCredentials> _profiles = [];
  XtreamCredentials? _selected;
  PairingTicket? _ticket;
  PairingSender? _sender;
  PairingReply? _reply;
  String? _error;
  bool _busy = false;
  bool _m3u = false;
  int _generation = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    (widget.profiles ?? Store.savedProfiles)()
        .then((profiles) {
          if (mounted) {
            setState(
              () => _profiles = profiles.where((p) => !p.isDemo).toList(),
            );
          }
        })
        .catchError((_) {
          if (mounted) {
            setState(
              () => _error =
                  'Saved accounts are unavailable. You can enter an account below.',
            );
          }
        });
  }

  void _cancel() {
    ++_generation;
    _poll?.cancel();
    _sender?.close();
    _sender = null;
    _ticket = null;
    _busy = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The scanner owns camera permission/lifecycle. Only cancel active transfers.
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.detached) &&
        _sender != null) {
      _cancel();
      if (mounted) {
        setState(() {
          _reply = null;
          _error =
              'Setup paused. Reject any pending request on the TV and scan a new QR.';
        });
      }
    }
  }

  Future<void> _scan() async {
    _cancel();
    setState(() {
      _reply = null;
      _error = null;
    });
    final result =
        await (widget.scan?.call(context) ??
            Navigator.of(context).push<String>(
              MaterialPageRoute(builder: (_) => const _PairingScannerScreen()),
            ));
    if (!mounted || result == null) return;
    try {
      final ticket = PairingTicket.parse(result);
      setState(() => _ticket = ticket);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _send() async {
    final ticket = _ticket;
    if (ticket == null || _busy) return;
    XtreamCredentials credentials;
    try {
      final raw = _playlist.text.trim();
      credentials =
          _selected ??
          (_m3u
              ? credentialsFromUrl(raw) ??
                    XtreamCredentials(
                      baseUrl: raw,
                      username: Uri.tryParse(raw)?.host ?? '',
                      password: '',
                      m3uUrl: raw,
                    )
              : XtreamCredentials(
                  baseUrl: normalizeBaseUrl(_url.text),
                  username: _user.text.trim(),
                  password: _pass.text,
                ));
      credentials = pairingCredentials(credentials.toJson());
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    final generation = ++_generation;
    final sender = PairingSender(ticket);
    _sender = sender;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final reply = await sender.send(credentials);
      if (!mounted || generation != _generation) return;
      // Discard typed secrets after transfer. No new account is saved on phone.
      _pass.clear();
      _playlist.clear();
      setState(() => _reply = reply);
      _pollStatus(sender, generation);
    } on FormatException catch (e) {
      if (!mounted || generation != _generation) return;
      _cancel();
      setState(() => _error = e.message);
    }
  }

  void _pollStatus(PairingSender sender, int generation) {
    _poll = Timer(const Duration(seconds: 1), () async {
      if (!mounted || generation != _generation) return;
      try {
        final reply = await sender.status();
        if (!mounted || generation != _generation) return;
        setState(() => _reply = reply);
        if (reply.state == PairingState.pending) {
          _pollStatus(sender, generation);
        } else {
          _cancel();
          setState(() {});
        }
      } on FormatException catch (e) {
        if (!mounted || generation != _generation) return;
        _cancel();
        setState(() {
          _reply = null;
          _error = '${e.message} Check the TV before trying again.';
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancel();
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    _playlist.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _page(context, 'Set up a TV', [
    _message(
      'On the TV login screen, choose Connect using phone. Connect both devices to the same home network, then scan its QR below.',
    ),
    if (_error != null) _message(_error!),
    if (_reply != null) ...[
      if (_reply!.state == PairingState.pending) ...[
        _message(
          'Check that this code matches the TV, then choose Approve and connect on the TV.',
        ),
        Text(
          _reply!.code,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineLarge?.copyWith(letterSpacing: 8),
        ),
        _message('Waiting for your confirmation on the TV…'),
      ],
      if (_reply!.state == PairingState.approved)
        _message(
          'The TV accepted the account. Check the TV for provider sign-in and library loading.',
        ),
      if (_reply!.state == PairingState.rejected)
        _message(
          'The TV rejected the request. No account was saved by pairing.',
        ),
    ],
    if (!_busy) ...[
      FilledButton.icon(
        onPressed: _scan,
        icon: const Icon(Icons.qr_code_scanner),
        label: Text(_ticket == null ? 'Scan TV QR' : 'Scan a different TV'),
      ),
      if (_ticket != null) ...[
        _message('TV at ${_ticket!.host} · Choose one service to send'),
        if (_profiles.isNotEmpty) ...[
          Text('Saved services', style: Theme.of(context).textTheme.titleLarge),
          for (final profile in _profiles)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: OutlinedButton.icon(
                icon: Icon(
                  identical(_selected, profile)
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                label: Text(
                  '${profile.username}\n${Uri.tryParse(profile.m3uUrl ?? profile.baseUrl)?.host ?? 'Saved service'}',
                  textAlign: TextAlign.center,
                ),
                onPressed: () => setState(() => _selected = profile),
              ),
            ),
          TextButton(
            onPressed: () => setState(() => _selected = null),
            child: const Text('Enter another service'),
          ),
        ],
        if (_selected == null) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Use a playlist URL'),
            value: _m3u,
            onChanged: (v) => setState(() => _m3u = v),
          ),
          if (_m3u)
            _field(_playlist, 'M3U / playlist URL', secret: true)
          else ...[
            _field(_url, 'Server URL'),
            _field(_user, 'Username'),
            _field(_pass, 'Password', secret: true),
          ],
        ],
        _message(
          'Account details are encrypted in transit to this TV. You must approve on the TV before they are used. New details are not saved on this phone.',
        ),
        FilledButton(onPressed: _send, child: const Text('Send account to TV')),
      ],
    ],
    if (_busy && _reply == null) const LinearProgressIndicator(),
    const SizedBox(height: 12),
    TextButton(
      onPressed: () => Navigator.pop(context),
      child: Text(_busy ? 'Leave setup' : 'Done'),
    ),
    if (_busy)
      _message(
        'Leaving stops the phone connection. Reject the request on the TV to cancel it there too.',
      ),
  ]);

  Widget _field(
    TextEditingController controller,
    String label, {
    bool secret = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: RemoteTextInput(
      child: TextField(
        controller: controller,
        obscureText: secret,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(labelText: label),
      ),
    ),
  );
}

class _PairingScannerScreen extends StatefulWidget {
  const _PairingScannerScreen();
  @override
  State<_PairingScannerScreen> createState() => _PairingScannerScreenState();
}

class _PairingScannerScreenState extends State<_PairingScannerScreen> {
  bool _returned = false;
  String? _error;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan the Lumen TV QR')),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: MobileScanner(
              // The widget owns its controller and handles app lifecycle/disposal.
              onDetect: (capture) {
                if (_returned) return;
                for (final barcode in capture.barcodes) {
                  final value = barcode.rawValue;
                  if (value == null) continue;
                  try {
                    PairingTicket.parse(value);
                    _returned = true;
                    Navigator.pop(context, value);
                    return;
                  } on FormatException {
                    if (_error == null) {
                      setState(
                        () => _error =
                            'Use a current QR from Lumen → Connect using phone on your TV.',
                      );
                    }
                  }
                }
              },
              errorBuilder: (_, _) => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Camera unavailable. Allow camera access for Lumen in device settings, or sign in manually on the TV.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _error ??
                  'Camera access is used only to scan the pairing QR. No camera images are saved or uploaded.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
          ),
        ],
      ),
    ),
  );
}
