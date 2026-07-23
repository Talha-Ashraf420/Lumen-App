import 'dart:convert';
import 'dart:io';

String _dataUri(File file) =>
    'data:image/png;base64,${base64Encode(file.readAsBytesSync())}';

String _phoneSvg({
  required String titleTop,
  required String titleBottom,
  required String subtitle,
  required String screenshot,
  required String glow,
}) =>
    '''
<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1920" viewBox="0 0 1920 1920">
  <defs>
    <radialGradient id="halo" cx="82%" cy="7%" r="76%">
      <stop offset="0" stop-color="$glow" stop-opacity=".38"/>
      <stop offset=".55" stop-color="$glow" stop-opacity=".09"/>
      <stop offset="1" stop-color="#080A0B" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="floor" x1="0" y1="0" x2="1" y2="1">
      <stop stop-color="#0A0D0C"/>
      <stop offset="1" stop-color="#111913"/>
    </linearGradient>
    <pattern id="grid" width="64" height="64" patternUnits="userSpaceOnUse">
      <path d="M64 0H0V64" fill="none" stroke="#C7F36B" stroke-opacity=".035"/>
    </pattern>
    <filter id="shadow" x="-40%" y="-30%" width="180%" height="190%">
      <feGaussianBlur stdDeviation="30"/>
    </filter>
    <clipPath id="screen">
      <rect x="215" y="450" width="650" height="1407" rx="60"/>
    </clipPath>
  </defs>

  <rect width="1080" height="1920" fill="url(#floor)"/>
  <rect width="1080" height="1920" fill="url(#halo)"/>
  <rect width="1080" height="1920" fill="url(#grid)"/>
  <circle cx="960" cy="245" r="170" fill="$glow" opacity=".08"/>
  <circle cx="58" cy="1500" r="240" fill="$glow" opacity=".045"/>

  <g transform="translate(72 56)">
    <rect x="0" y="4" width="32" height="52" rx="14" fill="#F4F1E8"/>
    <path d="M14 16v28l28-14z" fill="#C7F36B"/>
    <rect x="42" y="12" width="28" height="8" rx="4" fill="#C7F36B"/>
    <rect x="42" y="27" width="40" height="8" rx="4" fill="#C7F36B"/>
    <rect x="42" y="42" width="28" height="8" rx="4" fill="#C7F36B"/>
    <text x="102" y="47" fill="#F4F1E8" font-family="Arial, Helvetica, sans-serif"
      font-size="45" font-weight="800" letter-spacing="4">LUMEN</text>
  </g>
  <rect x="788" y="72" width="218" height="52" rx="26" fill="#C7F36B" fill-opacity=".12"
    stroke="#C7F36B" stroke-opacity=".34"/>
  <text x="897" y="106" text-anchor="middle" fill="#C7F36B"
    font-family="Arial, Helvetica, sans-serif" font-size="20" font-weight="700"
    letter-spacing="3">ANDROID</text>

  <text x="72" y="208" fill="#F4F1E8" font-family="Arial, Helvetica, sans-serif"
    font-size="88" font-weight="800" letter-spacing="-4">$titleTop</text>
  <text x="72" y="298" fill="#C7F36B" font-family="Arial, Helvetica, sans-serif"
    font-size="88" font-weight="800" letter-spacing="-4">$titleBottom</text>
  <text x="76" y="354" fill="#A7B0AC" font-family="Arial, Helvetica, sans-serif"
    font-size="27" font-weight="500">$subtitle</text>

  <rect x="202" y="438" width="676" height="1433" rx="80" fill="#000" opacity=".8"
    filter="url(#shadow)"/>
  <rect x="180" y="415" width="720" height="1477" rx="92" fill="#090B0C"
    stroke="#3A443F" stroke-width="5"/>
  <rect x="203" y="438" width="674" height="1431" rx="70" fill="#101413"
    stroke="#18201C" stroke-width="4"/>
  <image href="$screenshot" x="215" y="450" width="650" height="1407"
    preserveAspectRatio="none" clip-path="url(#screen)"/>
  <rect x="452" y="430" width="176" height="20" rx="10" fill="#050606"/>
  <circle cx="650" cy="440" r="6" fill="#242B28"/>

</svg>
''';

String _tvSvg({required String screenshot}) =>
    '''
<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1920" viewBox="0 0 1920 1920">
  <defs>
    <radialGradient id="halo" cx="80%" cy="5%" r="90%">
      <stop stop-color="#C7F36B" stop-opacity=".24"/>
      <stop offset=".55" stop-color="#C7F36B" stop-opacity=".05"/>
      <stop offset="1" stop-color="#080A0B" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="base" x1="0" y1="0" x2="1" y2="1">
      <stop stop-color="#070909"/>
      <stop offset="1" stop-color="#111812"/>
    </linearGradient>
    <pattern id="grid" width="80" height="80" patternUnits="userSpaceOnUse">
      <path d="M80 0H0V80" fill="none" stroke="#C7F36B" stroke-opacity=".035"/>
    </pattern>
    <filter id="shadow" x="-30%" y="-30%" width="160%" height="180%">
      <feGaussianBlur stdDeviation="28"/>
    </filter>
    <clipPath id="screen">
      <rect x="280" y="265" width="1360" height="765" rx="18"/>
    </clipPath>
  </defs>
  <rect width="1920" height="1080" fill="url(#base)"/>
  <rect width="1920" height="1080" fill="url(#halo)"/>
  <rect width="1920" height="1080" fill="url(#grid)"/>

  <g transform="translate(100 62)">
    <rect x="0" y="4" width="32" height="52" rx="14" fill="#F4F1E8"/>
    <path d="M14 16v28l28-14z" fill="#C7F36B"/>
    <rect x="42" y="12" width="28" height="8" rx="4" fill="#C7F36B"/>
    <rect x="42" y="27" width="40" height="8" rx="4" fill="#C7F36B"/>
    <rect x="42" y="42" width="28" height="8" rx="4" fill="#C7F36B"/>
    <text x="102" y="47" fill="#F4F1E8" font-family="Arial, Helvetica, sans-serif"
      font-size="45" font-weight="800" letter-spacing="4">LUMEN</text>
  </g>
  <text x="960" y="106" text-anchor="middle" fill="#F4F1E8"
    font-family="Arial, Helvetica, sans-serif" font-size="64" font-weight="800"
    letter-spacing="-2">BUILT FOR THE BIG SCREEN.</text>
  <text x="960" y="163" text-anchor="middle" fill="#A7B0AC"
    font-family="Arial, Helvetica, sans-serif" font-size="27">
    Full remote and D-pad navigation for Android TV and Google TV
  </text>

  <rect x="260" y="245" width="1400" height="805" rx="42" fill="#000" opacity=".82"
    filter="url(#shadow)"/>
  <rect x="245" y="225" width="1430" height="835" rx="44" fill="#080A0B"
    stroke="#3D4842" stroke-width="6"/>
  <rect x="267" y="247" width="1386" height="791" rx="26" fill="#020303"
    stroke="#171D1A" stroke-width="4"/>
  <image href="$screenshot" x="280" y="265" width="1360" height="765"
    preserveAspectRatio="none" clip-path="url(#screen)"/>
  <circle cx="960" cy="1048" r="5" fill="#C7F36B"/>
</svg>
''';

Future<void> _render({
  required File svg,
  required File output,
  required int width,
  required int height,
}) async {
  final tempDirectory = svg.parent;
  final thumbnail = File('${svg.path}.png');
  if (thumbnail.existsSync()) thumbnail.deleteSync();

  final quickLook = await Process.run('qlmanage', [
    '-t',
    '-s',
    '${width > height ? width : height}',
    '-o',
    tempDirectory.path,
    svg.path,
  ]);
  if (quickLook.exitCode != 0 || !thumbnail.existsSync()) {
    stderr.write(quickLook.stderr);
    throw StateError('Quick Look could not render ${svg.path}.');
  }

  output.parent.createSync(recursive: true);
  final ffmpeg = await Process.run('ffmpeg', [
    '-y',
    '-loglevel',
    'error',
    '-i',
    thumbnail.path,
    '-vf',
    'crop=$width:$height:0:0,format=rgb24',
    '-pix_fmt',
    'rgb24',
    output.path,
  ]);
  thumbnail.deleteSync();
  if (ffmpeg.exitCode != 0) {
    stderr.write(ffmpeg.stderr);
    throw StateError('ffmpeg could not create ${output.path}.');
  }
}

Future<void> main() async {
  final script = File.fromUri(Platform.script);
  final repository = script.parent.parent;
  final sources = Directory(
    '${repository.path}/docs/play-store/source-screenshots',
  );
  final output = Directory(
    '${repository.path}/fastlane/metadata/android/en-US/images',
  );
  final temporary = Directory('${repository.path}/build/store-mockups')
    ..createSync(recursive: true);

  final welcome = _dataUri(File('${sources.path}/phone/01-welcome.png'));
  final privacy = _dataUri(File('${sources.path}/phone/02-privacy.png'));
  final television = _dataUri(File('${sources.path}/tv/01-tv-welcome.png'));

  final phoneWelcomeSvg = File('${temporary.path}/01-your-media.svg')
    ..writeAsStringSync(
      _phoneSvg(
        titleTop: 'YOUR MEDIA.',
        titleBottom: 'ONE PLAYER.',
        subtitle: 'Phone, tablet and TV — shaped around your own library.',
        screenshot: welcome,
        glow: '#C7F36B',
      ),
    );
  final phonePrivacySvg = File('${temporary.path}/02-private.svg')
    ..writeAsStringSync(
      _phoneSvg(
        titleTop: 'PRIVATE BY',
        titleBottom: 'DEFAULT.',
        subtitle: 'Encrypted profiles. No advertising or analytics SDKs.',
        screenshot: privacy,
        glow: '#61E0B5',
      ),
    );
  final tvSvg = File('${temporary.path}/01-big-screen.svg')
    ..writeAsStringSync(_tvSvg(screenshot: television));

  await _render(
    svg: phoneWelcomeSvg,
    output: File('${output.path}/phoneScreenshots/01-your-media.png'),
    width: 1080,
    height: 1920,
  );
  await _render(
    svg: phonePrivacySvg,
    output: File('${output.path}/phoneScreenshots/02-private.png'),
    width: 1080,
    height: 1920,
  );
  await _render(
    svg: tvSvg,
    output: File('${output.path}/tvScreenshots/01-big-screen.png'),
    width: 1920,
    height: 1080,
  );

  stdout.writeln('Generated Play Store mockups in ${output.path}.');
}
