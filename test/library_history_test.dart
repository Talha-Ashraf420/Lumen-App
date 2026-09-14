import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Library.instance.activate(null);
  });

  test('continue watching keeps unfinished VOD and drops completed VOD', () {
    const unfinished = Progress(
      key: 'movie:1',
      title: 'Unfinished film',
      poster: '',
      url: 'https://stream.example/movie/1.mp4',
      ext: 'mp4',
      position: 600,
      duration: 3600,
      updatedAt: 10,
    );
    const completed = Progress(
      key: 'ep:2',
      title: 'Completed episode',
      poster: '',
      url: 'https://stream.example/series/2.mp4',
      ext: 'mp4',
      position: 3590,
      duration: 3600,
      updatedAt: 20,
    );

    Library.instance.saveProgress(unfinished);
    Library.instance.saveProgress(completed);

    expect(Library.instance.continueWatching().map((item) => item.key), [
      'movie:1',
    ]);
    expect(Library.instance.isWatched('ep:2'), isTrue);

    Library.instance.markWatched('movie:1');
    expect(Library.instance.continueWatching(), isEmpty);
    expect(Library.instance.isWatched('movie:1'), isTrue);

    Library.instance.clearProgress('movie:1');
    expect(Library.instance.isWatched('movie:1'), isFalse);
  });

  test('recent history accepts live channels only and supports removal', () {
    const channel = MediaRef(
      kind: 'live',
      id: 7,
      name: 'News',
      url: 'https://stream.example/live/7.ts',
    );
    const movie = MediaRef(
      kind: 'movie',
      id: 8,
      name: 'Movie',
      url: 'https://stream.example/movie/8.mp4',
    );

    Library.instance.addRecent(movie);
    Library.instance.addRecent(channel);
    expect(Library.instance.recent, [channel]);

    Library.instance.removeRecent(channel.key);
    expect(Library.instance.recent, isEmpty);
  });
}
