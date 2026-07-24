import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// A deliberately fictional, provider-free library used for onboarding,
/// screenshots and store review.
///
/// Nothing in this catalog is fetched from the network. Names, artwork and
/// programme descriptions are original Lumen demo material.
class DemoCatalog {
  DemoCatalog._();

  static const _assetPrefix = 'asset://assets/demo';
  static const aerial = '$_assetPrefix/aerial_night.jpg';
  static const harbor = '$_assetPrefix/glass_harbor.jpg';
  static const meridian = '$_assetPrefix/meridian.jpg';
  static const afterlight = '$_assetPrefix/afterlight.jpg';
  static const _previewAsset = 'assets/demo/lumen_demo_preview.mp4';

  static String _playbackPath = '';

  /// Copies the bundled preview to a normal file path understood by libmpv.
  /// Failure is non-fatal: the catalog remains fully browsable.
  static Future<void> preparePlayback() async {
    try {
      final bytes = await rootBundle.load(_previewAsset);
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/lumen_demo_preview.mp4');
      if (!await file.exists() || await file.length() != bytes.lengthInBytes) {
        await file.writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          flush: true,
        );
      }
      _playbackPath = file.path;
    } catch (_) {
      _playbackPath = '';
    }
  }

  static String get playbackPath => _playbackPath;

  static List<Category> get movieCategories => [
    Category('demo_featured', 'Featured stories'),
    Category('demo_scifi', 'Science fiction'),
    Category('demo_drama', 'Drama'),
  ];

  static List<Category> get seriesCategories => [
    Category('demo_mystery', 'Mystery'),
    Category('demo_drama', 'Drama'),
    Category('demo_scifi', 'Science fiction'),
  ];

  static List<Category> get liveCategories => [
    Category('demo_live', 'Lumen Live'),
    Category('demo_culture', 'Culture'),
    Category('demo_nature', 'Nature'),
  ];

  static final List<VodStream> _movies = [
    VodStream(
      9001,
      'Aerial Night (2023)',
      aerial,
      'demo_scifi',
      'mp4',
      7.8,
      '2023',
    ),
    VodStream(
      9002,
      'Meridian (2024)',
      meridian,
      'demo_scifi',
      'mp4',
      8.1,
      '2024',
    ),
    VodStream(
      9003,
      'Afterlight (2022)',
      afterlight,
      'demo_drama',
      'mp4',
      7.4,
      '2022',
    ),
    VodStream(
      9004,
      'Glass Harbor (2023)',
      harbor,
      'demo_drama',
      'mp4',
      8.3,
      '2023',
    ),
    VodStream(
      9005,
      'Northbound (2021)',
      aerial,
      'demo_featured',
      'mp4',
      7.2,
      '2021',
    ),
    VodStream(
      9006,
      'Signal Lost (2024)',
      meridian,
      'demo_featured',
      'mp4',
      7.7,
      '2024',
    ),
    VodStream(
      9007,
      'The Long Horizon (2020)',
      afterlight,
      'demo_drama',
      'mp4',
      6.9,
      '2020',
    ),
    VodStream(
      9008,
      'Undertow (2023)',
      harbor,
      'demo_featured',
      'mp4',
      7.5,
      '2023',
    ),
  ];

  static List<VodStream> movies(String? categoryId) {
    if (categoryId == null || categoryId == 'demo_featured') {
      return List<VodStream>.of(_movies);
    }
    return _movies
        .where((movie) => movie.categoryId == categoryId)
        .toList(growable: false);
  }

  static VodInfo movieInfo(int id) {
    final movie = _movies.firstWhere(
      (item) => item.streamId == id,
      orElse: () => _movies.first,
    );
    final details = switch (movie.streamId) {
      9001 => (
        'A rescue pilot crosses a silent city after a routine night flight '
            'reveals a signal no one else can hear.',
        'Science fiction, Drama',
        aerial,
      ),
      9002 => (
        'An explorer follows a shifting line of light toward the boundary '
            'between memory and space.',
        'Science fiction, Mystery',
        meridian,
      ),
      9003 => (
        'Two estranged friends return to a mountain observatory as the storm '
            'that separated them finally clears.',
        'Drama',
        afterlight,
      ),
      _ => (
        'A journalist returns to a windswept harbor and uncovers the story '
            'hidden beneath its calm surface.',
        'Mystery, Drama',
        harbor,
      ),
    };
    return VodInfo(
      plot: details.$1,
      cast: 'Original Lumen demo cast',
      director: 'Lumen Studio',
      genre: details.$2,
      releaseDate: movie.added,
      rating: movie.rating,
      duration: '00:12',
      image: details.$3,
      backdrop: details.$3,
      containerExtension: 'mp4',
    );
  }

  static final List<Series> _series = [
    Series(
      9201,
      'Glass Harbor',
      harbor,
      'A journalist returns home to investigate a signal from the old pier.',
      'Mystery, Drama',
      8.3,
      '2023',
      'demo_mystery',
    ),
    Series(
      9202,
      'Meridian Station',
      meridian,
      'A remote research crew maps an impossible horizon.',
      'Science fiction',
      8.0,
      '2024',
      'demo_scifi',
    ),
    Series(
      9203,
      'Afterlight',
      afterlight,
      'Small choices reshape a community after a season of storms.',
      'Drama',
      7.6,
      '2022',
      'demo_drama',
    ),
  ];

  static List<Series> series(String? categoryId) {
    if (categoryId == null) return List<Series>.of(_series);
    return _series
        .where((item) => item.categoryId == categoryId)
        .toList(growable: false);
  }

  static SeriesInfo seriesInfo(int id) {
    final item = _series.firstWhere(
      (series) => series.seriesId == id,
      orElse: () => _series.first,
    );
    final artwork = item.seriesId == 9202
        ? meridian
        : item.seriesId == 9203
        ? afterlight
        : harbor;
    final titles = item.seriesId == 9201
        ? const [
            'The Arrival',
            'Low Tide',
            'Signal Lost',
            'The Watcher',
            'North Pier',
            'Undertow',
          ]
        : const [
            'First Light',
            'The Boundary',
            'Quiet Orbit',
            'Echo Point',
            'Night Shift',
            'Home Signal',
          ];
    return SeriesInfo(
      cover: artwork,
      backdrop: artwork,
      plot: item.plot,
      genre: item.genre,
      rating: item.rating,
      releaseDate: item.releaseDate,
      episodes: {
        1: [
          for (var index = 0; index < titles.length; index++)
            Episode(
              '${item.seriesId}${index + 1}',
              index + 1,
              titles[index],
              'mp4',
              1,
              artwork,
            ),
        ],
        2: [
          for (var index = 0; index < 4; index++)
            Episode(
              '${item.seriesId}2${index + 1}',
              index + 1,
              'Chapter ${index + 7}',
              'mp4',
              2,
              artwork,
            ),
        ],
      },
    );
  }

  static final List<LiveStream> _channels = [
    LiveStream(9401, 'Lumen One', aerial, 'demo_live', 'demo-one'),
    LiveStream(9402, 'Horizon News', meridian, 'demo_live', 'demo-news'),
    LiveStream(9403, 'Cinema Vault', harbor, 'demo_culture', 'demo-cinema'),
    LiveStream(9404, 'Wild Earth', afterlight, 'demo_nature', 'demo-earth'),
    LiveStream(9405, 'Nightline', meridian, 'demo_culture', 'demo-night'),
    LiveStream(9406, 'Coast & Sky', harbor, 'demo_nature', 'demo-coast'),
  ];

  static List<LiveStream> channels(String? categoryId) {
    if (categoryId == null) return List<LiveStream>.of(_channels);
    return _channels
        .where((channel) => channel.categoryId == categoryId)
        .toList(growable: false);
  }

  static List<EpgEntry> epg(int streamId, {int limit = 8}) {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute < 30 ? 0 : 30,
    );
    const titles = [
      'Now in focus',
      'Signal stories',
      'The long view',
      'Night archive',
      'After hours',
      'Quiet cinema',
      'New horizons',
      'Morning light',
    ];
    return [
      for (var index = 0; index < limit; index++)
        EpgEntry(
          titles[index % titles.length],
          'Fictional programming from Lumen’s offline demonstration library.',
          start.add(Duration(minutes: 30 * index)),
          start.add(Duration(minutes: 30 * (index + 1))),
        ),
    ];
  }
}
