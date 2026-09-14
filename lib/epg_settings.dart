import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'catalog_store.dart';
import 'models.dart';
import 'store.dart';

const String kEpgSettingsKey = 'lumen_epg_settings';

/// Notifies already-open Live and Guide screens that their account-scoped EPG
/// configuration or cache changed.
final ValueNotifier<int> epgConfigurationRevision = ValueNotifier<int>(0);

void notifyEpgConfigurationChanged() {
  epgConfigurationRevision.value++;
}

class EpgSettings {
  const EpgSettings({this.manualUrl = '', this.offsetMinutes = 0});

  final String manualUrl;
  final int offsetMinutes;

  static String storageKey(XtreamCredentials credentials) =>
      Store.scopedKey(kEpgSettingsKey, credentials);

  static Future<EpgSettings> load(XtreamCredentials credentials) async {
    String? raw;
    try {
      raw = await Store.readPrivate(storageKey(credentials));
    } catch (_) {
      // A missing preferences plugin in an isolated widget/test host should
      // behave exactly like a first launch, not break guide rendering.
      return const EpgSettings();
    }
    if (raw == null || raw.isEmpty) return const EpgSettings();
    try {
      final value = jsonDecode(raw) as Map<String, dynamic>;
      return EpgSettings(
        manualUrl: '${value['manualUrl'] ?? ''}'.trim(),
        offsetMinutes: _boundedOffset(value['offsetMinutes']),
      );
    } catch (_) {
      return const EpgSettings();
    }
  }

  static Future<void> save(
    XtreamCredentials credentials, {
    required String manualUrl,
    required int offsetMinutes,
  }) async {
    final normalized = manualUrl.trim();
    final validation = validateManualUrl(normalized);
    if (validation != null) throw FormatException(validation);
    await Store.writePrivate(
      storageKey(credentials),
      jsonEncode({
        'manualUrl': normalized,
        'offsetMinutes': _boundedOffset(offsetMinutes),
      }),
    );
    notifyEpgConfigurationChanged();
  }

  static Future<void> clear(XtreamCredentials credentials) async {
    await Store.deletePrivate(storageKey(credentials));
    notifyEpgConfigurationChanged();
  }

  static String? validateManualUrl(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return 'Enter a complete HTTP or HTTPS XMLTV URL.';
    }
    return null;
  }

  static int _boundedOffset(Object? value) {
    final parsed = value is int ? value : int.tryParse('$value') ?? 0;
    return parsed.clamp(-12 * 60, 12 * 60);
  }
}

class EpgCacheDiagnostics {
  const EpgCacheDiagnostics({
    required this.manualSourceConfigured,
    required this.offsetMinutes,
    required this.sourceCount,
    required this.channelCount,
    required this.programmeCount,
    required this.readySourceCount,
    required this.manualMappingCount,
    this.lastFetchedAt,
    this.validFrom,
    this.validUntil,
    this.lastError = '',
  });

  final bool manualSourceConfigured;
  final int offsetMinutes;
  final int sourceCount;
  final int channelCount;
  final int programmeCount;
  final int readySourceCount;
  final int manualMappingCount;
  final DateTime? lastFetchedAt;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final String lastError;

  static Future<EpgCacheDiagnostics> load(
    XtreamCredentials credentials, {
    CatalogStore? store,
  }) async {
    final database = store ?? CatalogStore.instance;
    final scope = Store.profileScope(credentials);
    final settings = await EpgSettings.load(credentials);
    final sources = await database.epgSourceStates(scope);
    final counts = await database.epgCacheCounts(scope);
    final mappings = await database.epgChannelMappings(scope);
    DateTime? earliest;
    DateTime? latest;
    String lastError = '';
    for (final source in sources) {
      final from = source.validFrom;
      final until = source.validUntil;
      if (from != null && (earliest == null || from.isBefore(earliest))) {
        earliest = from;
      }
      if (until != null && (latest == null || until.isAfter(latest))) {
        latest = until;
      }
      if (lastError.isEmpty && source.lastError.trim().isNotEmpty) {
        lastError = source.lastError.trim();
      }
    }
    return EpgCacheDiagnostics(
      manualSourceConfigured: settings.manualUrl.isNotEmpty,
      offsetMinutes: settings.offsetMinutes,
      sourceCount: sources.length,
      channelCount: counts.channels,
      programmeCount: counts.programmes,
      readySourceCount: sources
          .where((source) => source.status == 'ready')
          .length,
      manualMappingCount: mappings.length,
      lastFetchedAt: sources.isEmpty ? null : sources.first.fetchedAt,
      validFrom: earliest,
      validUntil: latest,
      lastError: lastError,
    );
  }
}
