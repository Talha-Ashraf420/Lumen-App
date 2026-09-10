import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Coarse network information suitable for playback recovery and redacted
/// diagnostics. Connectivity describes the active route; it deliberately does
/// not claim that the IPTV provider itself is reachable.
class NetworkPathSnapshot {
  const NetworkPathSnapshot(this.transports);

  final Set<ConnectivityResult> transports;

  bool get hasNetwork =>
      transports.isNotEmpty && !transports.contains(ConnectivityResult.none);

  String get label {
    if (!hasNetwork) return 'Offline';
    const names = <ConnectivityResult, String>{
      ConnectivityResult.wifi: 'Wi-Fi',
      ConnectivityResult.mobile: 'Cellular',
      ConnectivityResult.ethernet: 'Ethernet',
      ConnectivityResult.vpn: 'VPN',
      ConnectivityResult.bluetooth: 'Bluetooth',
      ConnectivityResult.other: 'Other',
    };
    final values =
        transports
            .where((value) => value != ConnectivityResult.none)
            .map((value) => names[value] ?? value.name)
            .toSet()
            .toList()
          ..sort();
    return values.isEmpty ? 'Unknown' : values.join(' + ');
  }

  String get signature =>
      (transports.map((value) => value.name).toList()..sort()).join(',');
}

/// Watches the platform's default network so an IPTV socket opened on mobile
/// data is not left stale after Android moves the app to Wi-Fi (or vice versa).
class NetworkPathMonitor {
  NetworkPathMonitor._();

  static final NetworkPathMonitor instance = NetworkPathMonitor._();

  final _changes = StreamController<NetworkPathSnapshot>.broadcast();
  NetworkPathSnapshot _current = const NetworkPathSnapshot({});
  bool _initialized = false;

  NetworkPathSnapshot get current => _current;
  Stream<NetworkPathSnapshot> get changes => _changes.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final connectivity = Connectivity();
    try {
      _current = NetworkPathSnapshot(
        (await connectivity.checkConnectivity()).toSet(),
      );
    } catch (_) {
      // Playback still has its own timeouts when a platform cannot expose the
      // active transport (for example, some desktop test environments).
    }
    connectivity.onConnectivityChanged.listen(_accept, onError: (_) {});
  }

  void _accept(List<ConnectivityResult> values) {
    final next = NetworkPathSnapshot(values.toSet());
    if (next.signature == _current.signature) return;
    _current = next;
    _changes.add(next);
  }
}

enum ProviderPathState { reachable, dnsFailure, routeFailure, unsupported }

class ProviderPathCheck {
  const ProviderPathCheck({
    required this.state,
    required this.hasIpv4,
    required this.hasIpv6,
  });

  final ProviderPathState state;
  final bool hasIpv4;
  final bool hasIpv6;

  String get safeSummary => switch (state) {
    ProviderPathState.reachable =>
      hasIpv4 && hasIpv6
          ? 'Provider port reachable over a resolved IPv4/IPv6 host'
          : hasIpv6
          ? 'Provider port reachable over an IPv6-only host'
          : 'Provider port reachable over IPv4',
    ProviderPathState.dnsFailure =>
      'Provider hostname could not be resolved on this network',
    ProviderPathState.routeFailure =>
      hasIpv4 || hasIpv6
          ? 'Provider resolved, but its port is unreachable on this network'
          : 'Provider route is unavailable on this network',
    ProviderPathState.unsupported =>
      'Provider path check is unavailable for this stream protocol',
  };
}

/// Performs a credential-free DNS + TCP reachability check. It never requests
/// a playlist or stream path, so usernames, passwords and viewing activity are
/// not sent anywhere by the diagnostic.
Future<ProviderPathCheck> checkProviderPath(String rawUrl) async {
  final uri = Uri.tryParse(rawUrl.trim());
  if (uri == null ||
      uri.host.isEmpty ||
      !const {'http', 'https'}.contains(uri.scheme.toLowerCase())) {
    return const ProviderPathCheck(
      state: ProviderPathState.unsupported,
      hasIpv4: false,
      hasIpv6: false,
    );
  }

  List<InternetAddress> addresses;
  try {
    addresses = await InternetAddress.lookup(
      uri.host,
    ).timeout(const Duration(seconds: 5));
  } on Object {
    return const ProviderPathCheck(
      state: ProviderPathState.dnsFailure,
      hasIpv4: false,
      hasIpv6: false,
    );
  }
  final hasIpv4 = addresses.any(
    (value) => value.type == InternetAddressType.IPv4,
  );
  final hasIpv6 = addresses.any(
    (value) => value.type == InternetAddressType.IPv6,
  );
  if (addresses.isEmpty) {
    return const ProviderPathCheck(
      state: ProviderPathState.dnsFailure,
      hasIpv4: false,
      hasIpv6: false,
    );
  }

  final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
  Future<bool> reaches(InternetAddress address) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        address,
        port,
        timeout: const Duration(seconds: 4),
      );
      return true;
    } on Object {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  try {
    final results = await Future.wait(
      addresses.take(4).map(reaches),
    ).timeout(const Duration(seconds: 6));
    return ProviderPathCheck(
      state: results.any((value) => value)
          ? ProviderPathState.reachable
          : ProviderPathState.routeFailure,
      hasIpv4: hasIpv4,
      hasIpv6: hasIpv6,
    );
  } on Object {
    return ProviderPathCheck(
      state: ProviderPathState.routeFailure,
      hasIpv4: hasIpv4,
      hasIpv6: hasIpv6,
    );
  }
}
