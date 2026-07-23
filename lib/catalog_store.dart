import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
          version: 3,
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
        version: 3,
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
      final rows = await db.query(
        'catalog_items',
        columns: ['payload'],
        where:
            'profile_scope = ? AND media_kind = ? AND bucket = ?'
            '${normalized.isEmpty ? '' : ' AND instr(sort_name, ?) > 0'}',
        whereArgs: [scope, kind, bucket, if (normalized.isNotEmpty) normalized],
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
    recent: (item) => int.tryParse(item.added) ?? 0,
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
    'epg_channel_id': item.epgChannelId,
    'tv_archive': item.tvArchive,
    'tv_archive_duration': item.tvArchiveDuration,
  };

  static LiveStream _decodeLive(Map<String, dynamic> value) =>
      LiveStream.fromJson(value);
}
