import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'epg.dart';
import 'models.dart';

/// A page read from Lumen's durable catalog index.
class CatalogPage<T> {
  const CatalogPage({
    required this.items,
    required this.offset,
    required this.limit,
    required this.hasMore,
  });

  final List<T> items;
  final int offset;
  final int limit;
  final bool hasMore;
}

/// Account-scoped SQLite catalog.
///
/// Provider responses can contain tens of thousands of entries. Persisting
/// normalized rows lets screens paint the last good catalog immediately and
/// query small pages instead of rebuilding a huge in-memory library at launch.
///
/// Credentials and tokenized stream URLs are deliberately excluded. The
/// database contains browse metadata only and is partitioned by Store's
/// non-secret profile scope.
class CatalogStore {
  CatalogStore._();

  static final CatalogStore instance = CatalogStore._();
  static const defaultPageSize = 48;

  DatabaseFactory? _factoryOverride;
  String? _pathOverride;
  Future<Database>? _opening;
  bool _disabledForWidgetTests = false;

  Future<Database> _database() => _opening ??= _open();

  Future<Database> _open() async {
    final override = _factoryOverride;
    if (override != null) {
      return override.openDatabase(
        _pathOverride ?? inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: _create,
          onUpgrade: _upgrade,
        ),
      );
    }

    late final DatabaseFactory factory;
    if (!Platform.isAndroid && !Platform.isIOS) {
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
    } else {
      factory = mobile.databaseFactory;
    }
    Directory support;
    try {
      support = await getApplicationSupportDirectory();
    } catch (_) {
      // Flutter widget tests do not register path_provider. An isolated
      // temporary directory keeps the real SQLite path exercised without
      // leaking rows between test processes.
      support = await Directory.systemTemp.createTemp('lumen_catalog_');
    }
    final databases = Directory('${support.path}/catalog');
    await databases.create(recursive: true);
    return factory.openDatabase(
      '${databases.path}/lumen_catalog.sqlite',
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: _create,
        onUpgrade: _upgrade,
      ),
    );
  }

  Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE catalog_categories (
        profile_scope TEXT NOT NULL,
        media_kind TEXT NOT NULL,
        item_id TEXT NOT NULL,
        name TEXT NOT NULL,
        sort_name TEXT NOT NULL,
        generation INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (profile_scope, media_kind, item_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE catalog_items (
        profile_scope TEXT NOT NULL,
        media_kind TEXT NOT NULL,
        bucket TEXT NOT NULL,
        item_id TEXT NOT NULL,
        category_id TEXT NOT NULL,
        name TEXT NOT NULL,
        sort_name TEXT NOT NULL,
        image TEXT NOT NULL,
        payload TEXT NOT NULL,
        rating_value REAL NOT NULL,
        recent_value INTEGER NOT NULL,
        year_value INTEGER NOT NULL,
        source_position INTEGER NOT NULL,
        generation INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (profile_scope, media_kind, bucket, item_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE catalog_generations (
        profile_scope TEXT NOT NULL,
        media_kind TEXT NOT NULL,
        bucket TEXT NOT NULL,
        generation INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (profile_scope, media_kind, bucket)
      )
    ''');
    await _createProfileGenerations(db);
    await db.execute('''
      CREATE INDEX catalog_category_name
      ON catalog_categories(profile_scope, media_kind, sort_name)
    ''');
    await db.execute('''
      CREATE INDEX catalog_item_page
      ON catalog_items(profile_scope, media_kind, bucket, sort_name, item_id)
    ''');
    await db.execute('''
      CREATE INDEX catalog_item_search
      ON catalog_items(profile_scope, media_kind, sort_name)
    ''');
    await _createOrderIndex(db);
    await _createEpgTables(db);
  }

  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _createProfileGenerations(db);
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE catalog_items '
        'ADD COLUMN rating_value REAL NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE catalog_items '
        'ADD COLUMN recent_value INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE catalog_items '
        'ADD COLUMN year_value INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE catalog_items '
        'ADD COLUMN source_position INTEGER NOT NULL DEFAULT 0',
      );
      await _createOrderIndex(db);
    }
    if (oldVersion < 4) await _createEpgTables(db);
  }

  Future<void> _createEpgTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS epg_programmes (
        profile_scope TEXT NOT NULL,
        source_key TEXT NOT NULL,
        generation INTEGER NOT NULL,
        channel_key TEXT NOT NULL,
        start_utc INTEGER NOT NULL,
        stop_utc INTEGER NOT NULL,
        title TEXT NOT NULL,
        subtitle TEXT NOT NULL,
        description TEXT NOT NULL,
        categories_json TEXT NOT NULL,
        icon TEXT NOT NULL,
        has_archive INTEGER NOT NULL,
        catchup_id TEXT NOT NULL,
        stop_inferred INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (
          profile_scope,
          source_key,
          generation,
          channel_key,
          start_utc,
          title
        )
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS epg_programme_window
      ON epg_programmes(
        profile_scope,
        source_key,
        generation,
        channel_key,
        start_utc,
        stop_utc
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS epg_channels (
        profile_scope TEXT NOT NULL,
        source_key TEXT NOT NULL,
        generation INTEGER NOT NULL,
        channel_key TEXT NOT NULL,
        display_names_json TEXT NOT NULL,
        icon TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (
          profile_scope,
          source_key,
          generation,
          channel_key
        )
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS epg_sources (
        profile_scope TEXT NOT NULL,
        source_key TEXT NOT NULL,
        active_generation INTEGER NOT NULL,
        etag TEXT NOT NULL,
        last_modified TEXT NOT NULL,
        fetched_at INTEGER NOT NULL,
        valid_from INTEGER,
        valid_until INTEGER,
        status TEXT NOT NULL,
        last_error TEXT NOT NULL,
        next_retry_at INTEGER,
        PRIMARY KEY (profile_scope, source_key)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS epg_channel_map (
        profile_scope TEXT NOT NULL,
        live_stream_id INTEGER NOT NULL,
        source_key TEXT NOT NULL,
        epg_channel_key TEXT NOT NULL,
        match_method TEXT NOT NULL,
        confidence REAL NOT NULL,
        user_override INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (profile_scope, live_stream_id, source_key)
      )
    ''');
  }

  Future<void> _createProfileGenerations(Database db) => db.execute('''
    CREATE TABLE IF NOT EXISTS catalog_profile_generations (
      profile_scope TEXT NOT NULL PRIMARY KEY,
      generation INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');

  Future<void> _createOrderIndex(Database db) => db.execute('''
    CREATE INDEX IF NOT EXISTS catalog_item_order
    ON catalog_items(
      profile_scope,
      media_kind,
      bucket,
      source_position,
      item_id
    )
  ''');

  static String _sortName(String value) => value.trim().toLowerCase();

  static int _yearValue(String value) =>
      int.tryParse(RegExp(r'(19|20)\d{2}').firstMatch(value)?.group(0) ?? '') ??
      0;

  Future<List<Category>> categories(String scope, String kind) async {
    if (_disabledForWidgetTests) return const [];
    try {
      final db = await _database();
      final rows = await db.query(
        'catalog_categories',
        columns: ['item_id', 'name'],
        where: 'profile_scope = ? AND media_kind = ?',
        whereArgs: [scope, kind],
        orderBy: 'sort_name ASC',
      );
      return [
        for (final row in rows)
          Category(row['item_id'] as String, row['name'] as String),
      ];
    } catch (_) {
      // Persistence must never prevent a provider request from working.
      return const [];
    }
  }

  Future<bool> replaceCategories(
    String scope,
    String kind,
    List<Category> categories, {
    required int generation,
  }) async {
    if (_disabledForWidgetTests) return true;
    try {
      final db = await _database();
      return db.transaction((txn) async {
        if (!await _acceptGeneration(txn, scope, kind, '', generation)) {
          return false;
        }
        await txn.delete(
          'catalog_categories',
          where: 'profile_scope = ? AND media_kind = ?',
          whereArgs: [scope, kind],
        );
        final batch = txn.batch();
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final category in categories) {
          batch.insert('catalog_categories', {
            'profile_scope': scope,
            'media_kind': kind,
            'item_id': category.id,
            'name': category.name,
            'sort_name': _sortName(category.name),
            'generation': generation,
            'updated_at': now,
          });
        }
        await batch.commit(noResult: true);
        return true;
      });
    } catch (_) {
      return false;
    }
  }

  Future<CatalogPage<VodStream>> vodPage(
    String scope, {
    String bucket = '*',
    int offset = 0,
    int limit = defaultPageSize,
    String query = '',
    String sort = 'default',
  }) => _page(
    scope,
    'movie',
    bucket: bucket,
    offset: offset,
    limit: limit,
    query: query,
    sort: sort,
    decode: _decodeVod,
  );

  Future<CatalogPage<Series>> seriesPage(
    String scope, {
    String bucket = '*',
    int offset = 0,
    int limit = defaultPageSize,
    String query = '',
    String sort = 'default',
  }) => _page(
    scope,
    'series',
    bucket: bucket,
    offset: offset,
    limit: limit,
    query: query,
    sort: sort,
    decode: _decodeSeries,
  );

  Future<CatalogPage<LiveStream>> livePage(
    String scope, {
    String bucket = '*',
    int offset = 0,
    int limit = defaultPageSize,
    String query = '',
    String sort = 'default',
  }) => _page(
    scope,
    'live',
    bucket: bucket,
    offset: offset,
    limit: limit,
    query: query,
    sort: sort,
    decode: _decodeLive,
  );

  /// Whether the local index already contains browse data. A null [bucket]
  /// checks every cached category. Search uses this to distinguish “no match”
  /// from “catalog has never been loaded” without starting a provider-wide
  /// import for every unsuccessful query.
  Future<bool> hasItems(String scope, String kind, {String? bucket}) async {
    if (_disabledForWidgetTests) return false;
    try {
      final db = await _database();
      final rows = await db.query(
        'catalog_items',
        columns: ['item_id'],
        where:
            'profile_scope = ? AND media_kind = ?'
            '${bucket == null ? '' : ' AND bucket = ?'}',
        whereArgs: [scope, kind, ?bucket],
        limit: 1,
      );
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<CatalogPage<T>> _page<T>(
    String scope,
    String kind, {
    required String bucket,
    required int offset,
    required int limit,
    required String query,
    required String sort,
    required T Function(Map<String, dynamic>) decode,
  }) async {
    if (_disabledForWidgetTests) {
      return CatalogPage<T>(
        items: const [],
        offset: offset,
        limit: limit,
        hasMore: false,
      );
    }
    try {
      final db = await _database();
      final normalized = _sortName(query);
      // The '*' surface means “all categories”. Query every indexed bucket so
      // Search can immediately reuse pages warmed by Home/Movies/Series/Live.
      // Grouping by item id prevents duplicates when both a category bucket
      // and a complete '*' bucket contain the same media item.
      final acrossBuckets = bucket == '*';
      final rows = await db.query(
        'catalog_items',
        columns: ['payload', 'item_id'],
        where:
            'profile_scope = ? AND media_kind = ?'
            '${acrossBuckets ? '' : ' AND bucket = ?'}'
            '${normalized.isEmpty ? '' : ' AND instr(sort_name, ?) > 0'}',
        whereArgs: [
          scope,
          kind,
          if (!acrossBuckets) bucket,
          if (normalized.isNotEmpty) normalized,
        ],
        groupBy: acrossBuckets ? 'item_id' : null,
        orderBy: switch (sort) {
          'az' => 'sort_name ASC, item_id ASC',
          'za' => 'sort_name DESC, item_id DESC',
          'rating' => 'rating_value DESC, sort_name ASC, item_id ASC',
          'recent' => 'recent_value DESC, sort_name ASC, item_id ASC',
          'year' => 'year_value DESC, sort_name ASC, item_id ASC',
          _ => 'source_position ASC, item_id ASC',
        },
        limit: limit + 1,
        offset: offset,
      );
      final hasMore = rows.length > limit;
      final visible = hasMore ? rows.take(limit) : rows;
      return CatalogPage<T>(
        items: [
          for (final row in visible)
            decode(
              (jsonDecode(row['payload'] as String) as Map)
                  .cast<String, dynamic>(),
            ),
        ],
        offset: offset,
        limit: limit,
        hasMore: hasMore,
      );
    } catch (_) {
      return CatalogPage<T>(
        items: const [],
        offset: offset,
        limit: limit,
        hasMore: false,
      );
    }
  }

  Future<bool> replaceVod(
    String scope,
    String bucket,
    List<VodStream> items, {
    required int generation,
  }) => _replaceItems(
    scope,
    'movie',
    bucket,
    items,
    generation: generation,
    id: (item) => item.streamId.toString(),
    category: (item) => item.categoryId,
    name: (item) => item.name,
    image: (item) => item.icon,
    rating: (item) => item.rating,
    recent: (item) => mediaAddedValue(item.added),
    year: (item) => _yearValue(item.name),
    encode: _encodeVod,
  );

  Future<bool> replaceSeries(
    String scope,
    String bucket,
    List<Series> items, {
    required int generation,
  }) => _replaceItems(
    scope,
    'series',
    bucket,
    items,
    generation: generation,
    id: (item) => item.seriesId.toString(),
    category: (item) => item.categoryId,
    name: (item) => item.name,
    image: (item) => item.cover,
    rating: (item) => item.rating,
    recent: (item) =>
        _yearValue(item.releaseDate.isEmpty ? item.name : item.releaseDate),
    year: (item) =>
        _yearValue(item.releaseDate.isEmpty ? item.name : item.releaseDate),
    encode: _encodeSeries,
  );

  Future<bool> replaceLive(
    String scope,
    String bucket,
    List<LiveStream> items, {
    required int generation,
  }) => _replaceItems(
    scope,
    'live',
    bucket,
    items,
    generation: generation,
    id: (item) => item.streamId.toString(),
    category: (item) => item.categoryId,
    name: (item) => item.name,
    image: (item) => item.icon,
    rating: (_) => 0,
    recent: (_) => 0,
    year: (_) => 0,
    encode: _encodeLive,
  );

  Future<bool> _replaceItems<T>(
    String scope,
    String kind,
    String bucket,
    List<T> items, {
    required int generation,
    required String Function(T) id,
    required String Function(T) category,
    required String Function(T) name,
    required String Function(T) image,
    required double Function(T) rating,
    required int Function(T) recent,
    required int Function(T) year,
    required Map<String, dynamic> Function(T) encode,
  }) async {
    if (_disabledForWidgetTests) return true;
    try {
      final db = await _database();
      return db.transaction((txn) async {
        if (!await _acceptGeneration(txn, scope, kind, bucket, generation)) {
          return false;
        }
        await txn.delete(
          'catalog_items',
          where: 'profile_scope = ? AND media_kind = ? AND bucket = ?',
          whereArgs: [scope, kind, bucket],
        );
        final batch = txn.batch();
        final now = DateTime.now().millisecondsSinceEpoch;
        for (var position = 0; position < items.length; position++) {
          final item = items[position];
          final title = name(item);
          batch.insert('catalog_items', {
            'profile_scope': scope,
            'media_kind': kind,
            'bucket': bucket,
            'item_id': id(item),
            'category_id': category(item),
            'name': title,
            'sort_name': _sortName(title),
            'image': image(item),
            'payload': jsonEncode(encode(item)),
            'rating_value': rating(item),
            'recent_value': recent(item),
            'year_value': year(item),
            'source_position': position,
            'generation': generation,
            'updated_at': now,
          });
        }
        await batch.commit(noResult: true);
        return true;
      });
    } catch (_) {
      return false;
    }
  }

  Future<bool> _acceptGeneration(
    Transaction txn,
    String scope,
    String kind,
    String bucket,
    int generation,
  ) async {
    final floors = await txn.query(
      'catalog_profile_generations',
      columns: ['generation'],
      where: 'profile_scope = ?',
      whereArgs: [scope],
      limit: 1,
    );
    final floor = floors.isEmpty ? -1 : floors.first['generation'] as int;
    if (generation < floor) return false;

    final rows = await txn.query(
      'catalog_generations',
      columns: ['generation'],
      where: 'profile_scope = ? AND media_kind = ? AND bucket = ?',
      whereArgs: [scope, kind, bucket],
      limit: 1,
    );
    final current = rows.isEmpty ? -1 : rows.first['generation'] as int;
    if (generation < current) return false;
    await txn.insert('catalog_generations', {
      'profile_scope': scope,
      'media_kind': kind,
      'bucket': bucket,
      'generation': generation,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  /// Prepare a new EPG generation without touching the active guide.
  ///
  /// The new rows become visible only after [completeEpgImport]. If parsing or
  /// downloading fails, [abortEpgImport] removes the staged generation and the
  /// last successful guide remains active.
  Future<void> beginEpgImport(
    String scope,
    String sourceKey,
    int generation,
  ) async {
    if (_disabledForWidgetTests) return;
    final db = await _database();
    await db.transaction((txn) async {
      final sources = await txn.query(
        'epg_sources',
        columns: ['active_generation'],
        where: 'profile_scope = ? AND source_key = ?',
        whereArgs: [scope, sourceKey],
        limit: 1,
      );
      final activeGeneration = sources.isEmpty
          ? null
          : sources.first['active_generation'] as int;
      if (activeGeneration == generation) {
        throw ArgumentError.value(
          generation,
          'generation',
          'A new EPG import needs a new generation.',
        );
      }
      for (final table in ['epg_programmes', 'epg_channels']) {
        if (activeGeneration == null) {
          await txn.delete(
            table,
            where: 'profile_scope = ? AND source_key = ?',
            whereArgs: [scope, sourceKey],
          );
        } else {
          await txn.delete(
            table,
            where: 'profile_scope = ? AND source_key = ? AND generation <> ?',
            whereArgs: [scope, sourceKey, activeGeneration],
          );
        }
      }
    });
  }

  Future<void> appendEpgChannels(
    String scope,
    String sourceKey,
    int generation,
    List<EpgChannel> channels,
  ) async {
    if (_disabledForWidgetTests || channels.isEmpty) return;
    final db = await _database();
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final channel in channels) {
      batch.insert('epg_channels', {
        'profile_scope': scope,
        'source_key': sourceKey,
        'generation': generation,
        'channel_key': channel.channelKey,
        'display_names_json': jsonEncode(channel.displayNames),
        'icon': channel.icon,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> appendEpgProgrammes(
    String scope,
    String sourceKey,
    int generation,
    List<EpgProgramme> programmes,
  ) async {
    if (_disabledForWidgetTests || programmes.isEmpty) return;
    final db = await _database();
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final programme in programmes) {
      batch.insert('epg_programmes', {
        'profile_scope': scope,
        'source_key': sourceKey,
        'generation': generation,
        'channel_key': programme.channelKey,
        'start_utc': programme.startUtc.millisecondsSinceEpoch,
        'stop_utc': programme.stopUtc.millisecondsSinceEpoch,
        'title': programme.title,
        'subtitle': programme.subtitle,
        'description': programme.description,
        'categories_json': jsonEncode(programme.categories),
        'icon': programme.icon,
        'has_archive': programme.hasArchive ? 1 : 0,
        'catchup_id': programme.catchupId,
        'stop_inferred': programme.stopInferred ? 1 : 0,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> completeEpgImport(
    String scope,
    String sourceKey,
    int generation, {
    String etag = '',
    String lastModified = '',
    DateTime? fetchedAt,
    DateTime? validFrom,
    DateTime? validUntil,
  }) async {
    if (_disabledForWidgetTests) return;
    final db = await _database();
    final completedAt = fetchedAt ?? DateTime.now().toUtc();
    await db.transaction((txn) async {
      final floors = await txn.query(
        'catalog_profile_generations',
        columns: ['generation'],
        where: 'profile_scope = ?',
        whereArgs: [scope],
        limit: 1,
      );
      final floor = floors.isEmpty ? -1 : floors.first['generation'] as int;
      if (generation < floor) {
        for (final table in ['epg_programmes', 'epg_channels']) {
          await txn.delete(
            table,
            where: 'profile_scope = ? AND source_key = ? AND generation = ?',
            whereArgs: [scope, sourceKey, generation],
          );
        }
        throw StateError('The EPG account is no longer active.');
      }
      await txn.insert('epg_sources', {
        'profile_scope': scope,
        'source_key': sourceKey,
        'active_generation': generation,
        'etag': etag,
        'last_modified': lastModified,
        'fetched_at': completedAt.millisecondsSinceEpoch,
        'valid_from': validFrom?.millisecondsSinceEpoch,
        'valid_until': validUntil?.millisecondsSinceEpoch,
        'status': 'ready',
        'last_error': '',
        'next_retry_at': null,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      for (final table in ['epg_programmes', 'epg_channels']) {
        await txn.delete(
          table,
          where: 'profile_scope = ? AND source_key = ? AND generation <> ?',
          whereArgs: [scope, sourceKey, generation],
        );
      }
    });
  }

  Future<void> abortEpgImport(
    String scope,
    String sourceKey,
    int generation, {
    String sanitizedError = '',
    DateTime? nextRetryAt,
  }) async {
    if (_disabledForWidgetTests) return;
    final db = await _database();
    await db.transaction((txn) async {
      for (final table in ['epg_programmes', 'epg_channels']) {
        await txn.delete(
          table,
          where: 'profile_scope = ? AND source_key = ? AND generation = ?',
          whereArgs: [scope, sourceKey, generation],
        );
      }
      await txn.update(
        'epg_sources',
        {
          'status': 'stale',
          'last_error': sanitizedError,
          'next_retry_at': nextRetryAt?.millisecondsSinceEpoch,
        },
        where: 'profile_scope = ? AND source_key = ?',
        whereArgs: [scope, sourceKey],
      );
    });
  }

  Future<EpgSourceState?> epgSourceState(String scope, String sourceKey) async {
    if (_disabledForWidgetTests) return null;
    final db = await _database();
    final rows = await db.query(
      'epg_sources',
      where: 'profile_scope = ? AND source_key = ?',
      whereArgs: [scope, sourceKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    DateTime? optionalTime(Object? value) => value is int
        ? DateTime.fromMillisecondsSinceEpoch(value, isUtc: true)
        : null;
    return EpgSourceState(
      sourceKey: sourceKey,
      activeGeneration: row['active_generation'] as int,
      etag: row['etag'] as String,
      lastModified: row['last_modified'] as String,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(
        row['fetched_at'] as int,
        isUtc: true,
      ),
      validFrom: optionalTime(row['valid_from']),
      validUntil: optionalTime(row['valid_until']),
      status: row['status'] as String,
      lastError: row['last_error'] as String,
      nextRetryAt: optionalTime(row['next_retry_at']),
    );
  }

  Future<void> markEpgNotModified(
    String scope,
    String sourceKey, {
    DateTime? fetchedAt,
    String? etag,
    String? lastModified,
  }) async {
    if (_disabledForWidgetTests) return;
    final db = await _database();
    final values = <String, Object?>{
      'fetched_at':
          (fetchedAt ?? DateTime.now().toUtc()).millisecondsSinceEpoch,
      'status': 'ready',
      'last_error': '',
      'next_retry_at': null,
      if (etag != null && etag.isNotEmpty) 'etag': etag,
      if (lastModified != null && lastModified.isNotEmpty)
        'last_modified': lastModified,
    };
    final updated = await db.update(
      'epg_sources',
      values,
      where: 'profile_scope = ? AND source_key = ?',
      whereArgs: [scope, sourceKey],
    );
    if (updated == 0) {
      throw StateError('Cannot validate an EPG source with no cached guide.');
    }
  }

  Future<List<EpgProgramme>> epgWindow(
    String scope,
    String sourceKey, {
    required List<String> channelKeys,
    required DateTime startUtc,
    required DateTime endUtc,
  }) async {
    if (_disabledForWidgetTests ||
        channelKeys.isEmpty ||
        !startUtc.isBefore(endUtc)) {
      return const [];
    }
    final source = await epgSourceState(scope, sourceKey);
    if (source == null) return const [];
    final db = await _database();
    final placeholders = List.filled(channelKeys.length, '?').join(',');
    final rows = await db.query(
      'epg_programmes',
      where:
          'profile_scope = ? AND source_key = ? AND generation = ? '
          'AND channel_key IN ($placeholders) '
          'AND start_utc < ? AND stop_utc > ?',
      whereArgs: [
        scope,
        sourceKey,
        source.activeGeneration,
        ...channelKeys,
        endUtc.millisecondsSinceEpoch,
        startUtc.millisecondsSinceEpoch,
      ],
      orderBy: 'channel_key ASC, start_utc ASC',
    );
    return [for (final row in rows) _decodeEpgProgramme(row)];
  }

  Future<List<EpgChannel>> epgChannels(String scope, String sourceKey) async {
    if (_disabledForWidgetTests) return const [];
    final source = await epgSourceState(scope, sourceKey);
    if (source == null) return const [];
    final db = await _database();
    final rows = await db.query(
      'epg_channels',
      where: 'profile_scope = ? AND source_key = ? AND generation = ?',
      whereArgs: [scope, sourceKey, source.activeGeneration],
      orderBy: 'channel_key ASC',
    );
    return [
      for (final row in rows)
        EpgChannel(
          channelKey: row['channel_key'] as String,
          displayNames:
              (jsonDecode(row['display_names_json'] as String) as List)
                  .map((value) => '$value')
                  .toList(growable: false),
          icon: row['icon'] as String,
        ),
    ];
  }

  /// Replace the small rolling guide window for one Xtream channel.
  ///
  /// Short EPG is fetched independently for visible channels, so it cannot use
  /// the all-or-nothing XMLTV generation swap. Generation zero is reserved for
  /// these bounded per-channel updates. The transaction keeps readers from
  /// observing a channel between delete and insert.
  Future<void> replaceShortEpgChannel(
    String scope,
    String sourceKey,
    String channelKey,
    List<EpgProgramme> programmes, {
    DateTime? fetchedAt,
  }) async {
    if (_disabledForWidgetTests) return;
    final db = await _database();
    final completedAt = (fetchedAt ?? DateTime.now()).toUtc();
    await db.transaction((txn) async {
      await txn.delete(
        'epg_programmes',
        where:
            'profile_scope = ? AND source_key = ? AND generation = 0 '
            'AND channel_key = ?',
        whereArgs: [scope, sourceKey, channelKey],
      );
      final batch = txn.batch();
      for (final programme in programmes) {
        batch.insert('epg_programmes', {
          'profile_scope': scope,
          'source_key': sourceKey,
          'generation': 0,
          'channel_key': channelKey,
          'start_utc': programme.startUtc.millisecondsSinceEpoch,
          'stop_utc': programme.stopUtc.millisecondsSinceEpoch,
          'title': programme.title,
          'subtitle': programme.subtitle,
          'description': programme.description,
          'categories_json': jsonEncode(programme.categories),
          'icon': programme.icon,
          'has_archive': programme.hasArchive ? 1 : 0,
          'catchup_id': programme.catchupId,
          'stop_inferred': programme.stopInferred ? 1 : 0,
          'updated_at': completedAt.millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
      await txn.insert('epg_sources', {
        'profile_scope': scope,
        'source_key': sourceKey,
        'active_generation': 0,
        'etag': '',
        'last_modified': '',
        'fetched_at': completedAt.millisecondsSinceEpoch,
        'valid_from': programmes.isEmpty
            ? null
            : programmes
                  .map((programme) => programme.startUtc.millisecondsSinceEpoch)
                  .reduce(math.min),
        'valid_until': programmes.isEmpty
            ? null
            : programmes
                  .map((programme) => programme.stopUtc.millisecondsSinceEpoch)
                  .reduce(math.max),
        'status': 'ready',
        'last_error': '',
        'next_retry_at': null,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  static EpgProgramme _decodeEpgProgramme(Map<String, Object?> row) =>
      EpgProgramme(
        channelKey: row['channel_key'] as String,
        startUtc: DateTime.fromMillisecondsSinceEpoch(
          row['start_utc'] as int,
          isUtc: true,
        ),
        stopUtc: DateTime.fromMillisecondsSinceEpoch(
          row['stop_utc'] as int,
          isUtc: true,
        ),
        title: row['title'] as String,
        subtitle: row['subtitle'] as String,
        description: row['description'] as String,
        categories: (jsonDecode(row['categories_json'] as String) as List)
            .map((value) => '$value')
            .toList(growable: false),
        icon: row['icon'] as String,
        hasArchive: row['has_archive'] == 1,
        catchupId: row['catchup_id'] as String,
        stopInferred: row['stop_inferred'] == 1,
      );

  Future<void> deleteProfile(String scope) async {
    if (_disabledForWidgetTests) return;
    try {
      final db = await _database();
      await db.transaction((txn) async {
        // Keep a durable generation floor. A provider request that started
        // before account deletion may complete afterwards; its rows must not
        // resurrect the profile's old library.
        final now = DateTime.now();
        await txn.insert(
          'catalog_profile_generations',
          {
            'profile_scope': scope,
            'generation': now.microsecondsSinceEpoch,
            'updated_at': now.millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        for (final table in [
          'catalog_categories',
          'catalog_items',
          'catalog_generations',
          'epg_programmes',
          'epg_channels',
          'epg_sources',
          'epg_channel_map',
        ]) {
          await txn.delete(
            table,
            where: 'profile_scope = ?',
            whereArgs: [scope],
          );
        }
      });
    } catch (_) {}
  }

  /// Installs an isolated database for unit tests.
  Future<void> useInMemoryForTests() async {
    await close();
    _disabledForWidgetTests = false;
    sqfliteFfiInit();
    _factoryOverride = databaseFactoryFfi;
    _pathOverride = inMemoryDatabasePath;
  }

  /// Widget tests use Flutter's fake clock, which is incompatible with
  /// sqflite_common's transaction lock timer. Persistence has its own focused
  /// tests; UI suites can disable it to test request and rendering behavior
  /// without leaving fake timers behind.
  Future<void> disableForWidgetTests() async {
    await close();
    _disabledForWidgetTests = true;
  }

  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) {
      try {
        await (await opening).close();
      } catch (_) {}
    }
  }

  static Map<String, dynamic> _encodeVod(VodStream item) => {
    'stream_id': item.streamId,
    'name': item.name,
    'stream_icon': item.icon,
    'category_id': item.categoryId,
    'container_extension': item.containerExtension,
    'rating': item.rating,
    'added': item.added,
  };

  static VodStream _decodeVod(Map<String, dynamic> value) =>
      VodStream.fromJson(value);

  static Map<String, dynamic> _encodeSeries(Series item) => {
    'series_id': item.seriesId,
    'name': item.name,
    'cover': item.cover,
    'plot': item.plot,
    'genre': item.genre,
    'rating': item.rating,
    'releaseDate': item.releaseDate,
    'category_id': item.categoryId,
  };

  static Series _decodeSeries(Map<String, dynamic> value) =>
      Series.fromJson(value);

  static Map<String, dynamic> _encodeLive(LiveStream item) => {
    'stream_id': item.streamId,
    'name': item.name,
    'stream_icon': item.icon,
    'category_id': item.categoryId,
    if (item.epgId.isNotEmpty) 'epg_channel_id': item.epgId,
    if (item.epgName.isNotEmpty) 'tvg_name': item.epgName,
    if (item.countryCode.isNotEmpty) 'country_code': item.countryCode,
    if (item.fallbackIcon.isNotEmpty) '_lumen_fallback_icon': item.fallbackIcon,
    if (item.logoSource.isNotEmpty) '_lumen_logo_source': item.logoSource,
  };

  static LiveStream _decodeLive(Map<String, dynamic> value) =>
      LiveStream.fromJson(value);
}
