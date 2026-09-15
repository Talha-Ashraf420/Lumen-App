import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/catalog_organization.dart';
import 'package:lumen_tv/models.dart';

void main() {
  const scopeOne = 'source-one';
  const scopeTwo = 'source-two';
  final categories = [
    Category(
      'one::1',
      'News · one.example',
      sourceScope: scopeOne,
      sourceLabel: 'one.example',
    ),
    Category(
      'one::2',
      'Sport · one.example',
      sourceScope: scopeOne,
      sourceLabel: 'one.example',
    ),
    Category(
      'two::1',
      'News · two.example',
      sourceScope: scopeTwo,
      sourceLabel: 'two.example',
    ),
  ];

  test('rename hide and source filter remain local display transforms', () {
    final organization = CatalogOrganization()
      ..rename('live', 'one::1', 'Local news')
      ..setHidden('live', 'one::2', true);

    final result = organization.apply(
      'live',
      categories,
      sourceScope: scopeOne,
    );

    expect(result.map((value) => value.name), ['Local news']);
    expect(result.single.id, 'one::1');
    expect(categories.first.name, 'News · one.example');
  });

  test('reordering retains unknown provider categories after saved order', () {
    final organization = CatalogOrganization()
      ..setOrder('live', ['two::1', 'one::1']);

    final result = organization.apply('live', categories);

    expect(result.map((value) => value.id), ['two::1', 'one::1', 'one::2']);
  });

  test('combined categories expose members and retain source labels', () {
    final organization = CatalogOrganization()
      ..merge('live', ['one::1', 'two::1'], 'World news');

    final result = organization.apply('live', categories);
    final combined = result.first;

    expect(combined.name, 'World news');
    expect(combined.sourceLabel, 'Multiple services');
    expect(combined.memberIds, containsAll(['one::1', 'two::1']));
    expect(result.map((value) => value.id), contains('one::2'));
  });

  test('organization JSON round trips every preference', () {
    final original = CatalogOrganization()
      ..rename('movie', 'one::1', 'Cinema')
      ..setHidden('series', 'two::1', true)
      ..setOrder('movie', ['one::2', 'one::1'])
      ..merge('live', ['one::1', 'two::1'], 'Combined');

    final restored = CatalogOrganization.fromJson(original.toJson());

    expect(restored.names, original.names);
    expect(restored.hidden, original.hidden);
    expect(restored.orders, original.orders);
    expect(restored.categoryGroups, original.categoryGroups);
    expect(restored.groupNames, original.groupNames);
  });
}
