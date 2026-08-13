import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('interactive screens do not introduce touch-only gesture controls', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    final violations = <String>[];
    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      final hasRawGesture =
          source.contains('GestureDetector(') ||
          source.contains('InkWell(') ||
          source.contains('InkResponse(');
      if (!hasRawGesture) continue;

      // widgets.dart owns the two audited remote wrappers. player_host.dart
      // owns four touch gesture surfaces; every one has an equivalent remote
      // key handler or visible RemoteTap action.
      final allowed =
          file.path.endsWith('lib/widgets.dart') ||
          file.path.endsWith('lib/screens/player_host.dart');
      if (!allowed) violations.add(file.path);
    }
    expect(violations, isEmpty);
  });

  test('every editable text field uses the TV navigation wrapper', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    final violations = <String>[];
    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      final fields = RegExp(r'\bTextField\s*\(').allMatches(source).length;
      final wrapped = RegExp(
        r'RemoteTextInput\s*\(\s*child:\s*TextField\s*\(',
        multiLine: true,
      ).allMatches(source).length;
      if (fields != wrapped) {
        violations.add('${file.path}: $fields fields, $wrapped wrapped');
      }
    }
    expect(violations, isEmpty);
  });

  test('screens do not override the TV traversal policy', () {
    final screens = Directory('lib/screens')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final violations = <String>[];
    for (final file in screens) {
      if (file.readAsStringSync().contains('ReadingOrderTraversalPolicy()')) {
        violations.add(file.path);
      }
    }
    expect(violations, isEmpty);
  });
}
