import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'store.dart';

/// People using this device, not IPTV provider/service accounts.
class ViewingProfile {
  const ViewingProfile({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, String> toJson() => {'id': id, 'name': name};
}

class ViewingProfiles extends ChangeNotifier {
  ViewingProfiles._();
  static final ViewingProfiles instance = ViewingProfiles._();

  static const defaultId = 'default';
  static const _profilesKey = 'lumen_viewing_profiles_v1';
  static const _activeKey = 'lumen_active_viewing_profile_v1';
  static const _maxProfiles = 6;

  List<ViewingProfile> _profiles = const [
    ViewingProfile(id: defaultId, name: 'You'),
  ];
  String _activeId = defaultId;

  List<ViewingProfile> get profiles => List.unmodifiable(_profiles);
  String get activeId => _activeId;
  ViewingProfile get active => _profiles.firstWhere(
    (profile) => profile.id == _activeId,
    orElse: () => _profiles.first,
  );
  bool get canAdd => _profiles.length < _maxProfiles;

  Future<void> load() async {
    final raw = await Store.readPrivate(_profilesKey);
    final active = await Store.readPrivate(_activeKey);
    final parsed = <ViewingProfile>[];
    if (raw != null) {
      try {
        for (final item in jsonDecode(raw) as List) {
          if (item is! Map) continue;
          final id = '${item['id'] ?? ''}';
          final name = '${item['name'] ?? ''}'.trim();
          if ((id == defaultId || RegExp(r'^[a-f0-9-]{36}$').hasMatch(id)) &&
              name.isNotEmpty &&
              name.length <= 32 &&
              !parsed.any((profile) => profile.id == id)) {
            parsed.add(ViewingProfile(id: id, name: name));
          }
          if (parsed.length == _maxProfiles) break;
        }
      } catch (_) {}
    }
    if (!parsed.any((profile) => profile.id == defaultId)) {
      if (parsed.length == _maxProfiles) parsed.removeLast();
      parsed.insert(0, const ViewingProfile(id: defaultId, name: 'You'));
    }
    _profiles = parsed;
    _activeId = parsed.any((profile) => profile.id == active)
        ? active!
        : defaultId;
    notifyListeners();
  }

  Future<ViewingProfile> add(String name) async {
    final clean = _validName(name);
    if (!canAdd) throw StateError('You can have up to $_maxProfiles viewers.');
    final profile = ViewingProfile(id: const Uuid().v4(), name: clean);
    _profiles = [..._profiles, profile];
    await _persist();
    notifyListeners();
    return profile;
  }

  Future<void> rename(String id, String name) async {
    final clean = _validName(name);
    if (!_profiles.any((profile) => profile.id == id)) {
      throw StateError('Viewer not found.');
    }
    _profiles = [
      for (final profile in _profiles)
        if (profile.id == id) ViewingProfile(id: id, name: clean) else profile,
    ];
    await _persist();
    notifyListeners();
  }

  Future<void> select(String id) async {
    if (!_profiles.any((profile) => profile.id == id)) {
      throw StateError('Viewer not found.');
    }
    if (_activeId == id) return;
    await Store.writePrivate(_activeKey, id);
    _activeId = id;
    notifyListeners();
  }

  Future<void> remove(String id) async {
    if (id == defaultId) {
      throw StateError('The original viewer cannot be removed.');
    }
    if (!_profiles.any((profile) => profile.id == id)) return;
    if (_activeId == id) await select(defaultId);
    _profiles = _profiles.where((profile) => profile.id != id).toList();
    await _persist();
    await Store.deleteViewingProfileState(id);
    notifyListeners();
  }

  Future<void> _persist() => Store.writePrivate(
    _profilesKey,
    jsonEncode(_profiles.map((profile) => profile.toJson()).toList()),
  );

  String _validName(String name) {
    final clean = name.trim();
    if (clean.isEmpty || clean.length > 32) {
      throw ArgumentError('Enter a name between 1 and 32 characters.');
    }
    return clean;
  }
}
