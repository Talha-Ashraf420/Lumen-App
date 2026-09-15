import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;

import 'models.dart';
import 'store.dart';

/// Local, viewer-owned category layout for one collection of IPTV services.
///
/// Provider category names and ordering are never written back. Lumen stores
/// only display preferences, keyed by the non-secret profile scope.
class CatalogOrganization {
  CatalogOrganization({
    Map<String, String>? names,
    Set<String>? hidden,
    Map<String, List<String>>? orders,
    Map<String, String>? categoryGroups,
    Map<String, String>? groupNames,
  }) : names = names ?? <String, String>{},
       hidden = hidden ?? <String>{},
       orders = orders ?? <String, List<String>>{},
       categoryGroups = categoryGroups ?? <String, String>{},
       groupNames = groupNames ?? <String, String>{};

  final Map<String, String> names;
  final Set<String> hidden;
  final Map<String, List<String>> orders;
  final Map<String, String> categoryGroups;
  final Map<String, String> groupNames;

  String _key(String section, String categoryId) => '$section\u0000$categoryId';

  String displayName(String section, Category category) =>
      names[_key(section, category.id)]?.trim().isNotEmpty == true
      ? names[_key(section, category.id)]!.trim()
      : category.name;

  bool isHidden(String section, String categoryId) =>
      hidden.contains(_key(section, categoryId));

  String? groupFor(String section, String categoryId) =>
      categoryGroups[_key(section, categoryId)];

  List<Category> apply(
    String section,
    Iterable<Category> categories, {
    String sourceScope = 'all',
  }) {
    final raw = categories
        .where(
          (category) =>
              sourceScope == 'all' || category.sourceScope == sourceScope,
        )
        .where((category) => !isHidden(section, category.id))
        .toList(growable: false);
    final rank = <String, int>{
      for (final entry in (orders[section] ?? const <String>[]).indexed)
        entry.$2: entry.$1,
    };
    final sorted = raw.indexed.toList(growable: false)
      ..sort((a, b) {
        final ar = rank[a.$2.id] ?? (rank.length + a.$1);
        final br = rank[b.$2.id] ?? (rank.length + b.$1);
        return ar.compareTo(br);
      });

    final result = <Category>[];
    final groups = <String, List<Category>>{};
    final groupPositions = <String, int>{};
    for (final entry in sorted) {
      final category = entry.$2;
      final group = groupFor(section, category.id);
      if (group == null || group.isEmpty) {
        result.add(
          Category(
            category.id,
            displayName(section, category),
            sourceScope: category.sourceScope,
            sourceLabel: category.sourceLabel,
            memberIds: category.effectiveMemberIds,
          ),
        );
        continue;
      }
      groups.putIfAbsent(group, () => <Category>[]).add(category);
      groupPositions.putIfAbsent(group, () => result.length);
      if (groups[group]!.length == 1) {
        result.add(Category('lumen-merge::$group', ''));
      }
    }

    for (final group in groups.entries) {
      final members = group.value;
      final labels = members
          .map((category) => category.sourceLabel)
          .where((label) => label.isNotEmpty)
          .toSet();
      result[groupPositions[group.key]!] = Category(
        'lumen-merge::${group.key}',
        groupNames[group.key]?.trim().isNotEmpty == true
            ? groupNames[group.key]!.trim()
            : 'Combined category',
        sourceScope: labels.length == 1 ? members.first.sourceScope : '',
        sourceLabel: labels.length == 1 ? labels.first : 'Multiple services',
        memberIds: [for (final member in members) member.id],
      );
    }
    return result;
  }

  void rename(String section, String categoryId, String value) {
    final key = _key(section, categoryId);
    final clean = value.trim();
    if (clean.isEmpty) {
      names.remove(key);
    } else {
      names[key] = clean;
    }
  }

  void setHidden(String section, String categoryId, bool value) {
    final key = _key(section, categoryId);
    value ? hidden.add(key) : hidden.remove(key);
  }

  void setOrder(String section, Iterable<String> categoryIds) {
    orders[section] = categoryIds.toList(growable: false);
  }

  void merge(String section, Iterable<String> categoryIds, String name) {
    final ids = categoryIds.toSet();
    if (ids.length < 2) return;
    final existingGroups = ids
        .map((id) => groupFor(section, id))
        .whereType<String>()
        .toSet();
    final group = existingGroups.isNotEmpty
        ? existingGroups.first
        : _groupId(section, ids);
    for (final entry in categoryGroups.entries.toList(growable: false)) {
      if (existingGroups.contains(entry.value)) {
        categoryGroups[entry.key] = group;
      }
    }
    for (final id in ids) {
      categoryGroups[_key(section, id)] = group;
    }
    for (final old in existingGroups.where((value) => value != group)) {
      groupNames.remove(old);
    }
    groupNames[group] = name.trim().isEmpty ? 'Combined category' : name.trim();
  }

  void unmerge(String section, String categoryId) {
    final group = categoryGroups.remove(_key(section, categoryId));
    if (group == null) return;
    if (categoryGroups.values.where((value) => value == group).length < 2) {
      categoryGroups.removeWhere((_, value) => value == group);
      groupNames.remove(group);
    }
  }

  void resetSection(String section) {
    names.removeWhere((key, _) => key.startsWith('$section\u0000'));
    hidden.removeWhere((key) => key.startsWith('$section\u0000'));
    orders.remove(section);
    final removedGroups = <String>{};
    categoryGroups.removeWhere((key, value) {
      final remove = key.startsWith('$section\u0000');
      if (remove) removedGroups.add(value);
      return remove;
    });
    for (final group in removedGroups) {
      groupNames.remove(group);
    }
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'names': names,
    'hidden': hidden.toList(growable: false),
    'orders': orders,
    'categoryGroups': categoryGroups,
    'groupNames': groupNames,
  };

  factory CatalogOrganization.fromJson(Map<String, dynamic> json) {
    Map<String, String> stringMap(Object? value) => value is Map
        ? value.map((key, value) => MapEntry('$key', '$value'))
        : <String, String>{};
    Map<String, List<String>> listMap(Object? value) => value is Map
        ? value.map(
            (key, value) => MapEntry(
              '$key',
              value is List
                  ? value.map((item) => '$item').toList(growable: false)
                  : <String>[],
            ),
          )
        : <String, List<String>>{};
    return CatalogOrganization(
      names: stringMap(json['names']),
      hidden: json['hidden'] is List
          ? (json['hidden'] as List).map((value) => '$value').toSet()
          : <String>{},
      orders: listMap(json['orders']),
      categoryGroups: stringMap(json['categoryGroups']),
      groupNames: stringMap(json['groupNames']),
    );
  }

  static String _groupId(String section, Iterable<String> ids) {
    var hash = 0x811c9dc5;
    final text = '$section|${(ids.toList()..sort()).join('|')}';
    for (final byte in utf8.encode(text)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

class CatalogOrganizationStore {
  CatalogOrganizationStore._();

  static final instance = CatalogOrganizationStore._();
  static const _baseKey = 'lumen_catalog_organization_v1';

  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  final Map<String, CatalogOrganization> _cache = {};

  Future<CatalogOrganization> load(XtreamCredentials credentials) async {
    final scope = Store.profileScope(credentials);
    final cached = _cache[scope];
    if (cached != null) return cached;
    final raw = await Store.readPrivate(Store.scopedKey(_baseKey, credentials));
    CatalogOrganization value;
    try {
      value = raw == null
          ? CatalogOrganization()
          : CatalogOrganization.fromJson(jsonDecode(raw));
    } catch (_) {
      value = CatalogOrganization();
    }
    return _cache[scope] = value;
  }

  Future<void> save(
    XtreamCredentials credentials,
    CatalogOrganization organization,
  ) async {
    _cache[Store.profileScope(credentials)] = organization;
    await Store.writePrivate(
      Store.scopedKey(_baseKey, credentials),
      jsonEncode(organization.toJson()),
    );
    revision.value++;
  }

  @visibleForTesting
  void clearMemory() => _cache.clear();
}
