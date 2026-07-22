import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/downloads.dart';

void main() {
  test('duplicate titles receive distinct download paths', () {
    final first = Downloads.relativePathFor(
      id: 'movie:10',
      title: 'The Movie',
      kind: 'movie',
      ext: 'mp4',
    );
    final second = Downloads.relativePathFor(
      id: 'movie:20',
      title: 'The Movie',
      kind: 'movie',
      ext: 'mp4',
    );
    expect(first, isNot(second));
    expect(first, endsWith('movie_10.mp4'));
  });

  test('episodes are organized under their series', () {
    final path = Downloads.relativePathFor(
      id: 'ep:42',
      title: 'Show · S01E02 · The Episode',
      kind: 'episode',
      ext: '.mkv',
    );
    expect(path, startsWith('Series/Show/'));
    expect(path, endsWith('ep_42.mkv'));
  });

  test('failed state and safe error survive persistence', () {
    final item = DownloadItem(
      id: 'movie:10',
      title: 'Movie',
      poster: '',
      kind: 'movie',
      remoteUrl: 'https://example.test/movie',
      fileName: 'Movies/Movie-movie_10.mp4',
      progressKey: 'movie:10',
      status: DlStatus.failed,
      errorMessage: 'Connection interrupted.',
    );
    final restored = DownloadItem.fromJson(item.toJson());
    expect(restored.status, DlStatus.failed);
    expect(restored.errorMessage, 'Connection interrupted.');
  });
}
