import 'package:flutter/material.dart';

import '../catalog_cache.dart';
import '../catalog_organization.dart';
import '../models.dart';
import '../responsive.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';

enum _CategoryAction { rename, moveUp, moveDown, merge, unmerge }

class CatalogOrganizationScreen extends StatefulWidget {
  const CatalogOrganizationScreen({super.key, required this.client});

  final XtreamClient client;

  @override
  State<CatalogOrganizationScreen> createState() =>
      _CatalogOrganizationScreenState();
}

class _CatalogOrganizationScreenState extends State<CatalogOrganizationScreen> {
  static const _sections = <(String, String, IconData)>[
    ('movie', 'Movies', Icons.movie_outlined),
    ('series', 'Series', Icons.video_library_outlined),
    ('live', 'Live TV', Icons.live_tv_outlined),
  ];

  String _section = 'movie';
  String _sourceScope = 'all';
  CatalogOrganization? _organization;
  Map<String, List<Category>> _categories = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<List<Category>>([
      CatalogCache.instance.vod(widget.client, priority: true),
      CatalogCache.instance.series(widget.client, priority: true),
      CatalogCache.instance.live(widget.client, priority: true),
    ]);
    final organization = await CatalogOrganizationStore.instance.load(
      widget.client.creds,
    );
    if (!mounted) return;
    setState(() {
      _categories = {
        'movie': results[0],
        'series': results[1],
        'live': results[2],
      };
      _organization = organization;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final organization = _organization;
    if (organization == null) return;
    await CatalogOrganizationStore.instance.save(
      widget.client.creds,
      organization,
    );
    if (mounted) setState(() {});
  }

  List<Category> get _allOrdered {
    final values = [...?_categories[_section]];
    final order = _organization?.orders[_section] ?? const <String>[];
    final rank = {for (final entry in order.indexed) entry.$2: entry.$1};
    final original = {
      for (final entry in values.indexed) entry.$2.id: entry.$1,
    };
    values.sort((a, b) {
      final ar = rank[a.id] ?? (rank.length + (original[a.id] ?? 0));
      final br = rank[b.id] ?? (rank.length + (original[b.id] ?? 0));
      return ar.compareTo(br);
    });
    return values;
  }

  List<Category> get _visibleEditorCategories => _allOrdered
      .where(
        (category) =>
            _sourceScope == 'all' || category.sourceScope == _sourceScope,
      )
      .toList(growable: false);

  List<(String, String)> get _sources {
    final sources = <String, String>{};
    for (final category in _categories[_section] ?? const <Category>[]) {
      if (category.sourceScope.isNotEmpty) {
        sources[category.sourceScope] = category.sourceLabel.isEmpty
            ? 'IPTV service'
            : category.sourceLabel;
      }
    }
    return sources.entries.map((entry) => (entry.key, entry.value)).toList()
      ..sort((a, b) => a.$2.toLowerCase().compareTo(b.$2.toLowerCase()));
  }

  void _changeSection(String value) {
    if (_section == value) return;
    setState(() {
      _section = value;
      _sourceScope = 'all';
    });
  }

  Future<void> _rename(Category category) async {
    final controller = TextEditingController(
      text: _organization!.displayName(_section, category),
    );
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surface,
        title: const Text('Rename category'),
        content: RemoteTextInput(
          child: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.pop(dialogContext, value),
            decoration: InputDecoration(
              labelText: 'Display name',
              helperText: 'The provider name stays unchanged.',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    _organization!.rename(_section, category.id, value);
    await _save();
  }

  Future<void> _merge(Category category) async {
    final candidates = _visibleEditorCategories
        .where((value) => value.id != category.id)
        .toList(growable: false);
    if (candidates.isEmpty) return;
    var selected = candidates.first.id;
    final name = TextEditingController(
      text: _organization!.displayName(_section, category),
    );
    final result = await showDialog<({String categoryId, String name})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: surface,
          title: const Text('Combine categories'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Combine ${_organization!.displayName(_section, category)} with:',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final candidate in candidates)
                      DropdownMenuItem(
                        value: candidate.id,
                        child: Text(
                          _organization!.displayName(_section, candidate),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => selected = value);
                  },
                ),
                const SizedBox(height: 14),
                RemoteTextInput(
                  child: TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Combined name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, (
                categoryId: selected,
                name: name.text,
              )),
              child: const Text('Combine'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    if (result == null) return;
    _organization!.merge(_section, [
      category.id,
      result.categoryId,
    ], result.name);
    await _save();
  }

  Future<void> _move(Category category, int delta) async {
    final ordered = _allOrdered;
    final visible = _visibleEditorCategories;
    final index = visible.indexWhere((value) => value.id == category.id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= visible.length) return;
    final a = ordered.indexWhere((value) => value.id == category.id);
    final b = ordered.indexWhere((value) => value.id == visible[target].id);
    final moved = ordered.removeAt(a);
    ordered.insert(b, moved);
    _organization!.setOrder(_section, ordered.map((value) => value.id));
    await _save();
  }

  Future<void> _act(Category category, _CategoryAction action) async {
    switch (action) {
      case _CategoryAction.rename:
        await _rename(category);
      case _CategoryAction.moveUp:
        await _move(category, -1);
      case _CategoryAction.moveDown:
        await _move(category, 1);
      case _CategoryAction.merge:
        await _merge(category);
      case _CategoryAction.unmerge:
        _organization!.unmerge(_section, category.id);
        await _save();
    }
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surface,
        title: Text('Reset ${_sectionLabel.toLowerCase()}?'),
        content: const Text(
          'Names, visibility, order, and combined groups return to the provider defaults.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _organization!.resetSection(_section);
    await _save();
  }

  String get _sectionLabel =>
      _sections.firstWhere((value) => value.$1 == _section).$2;

  @override
  Widget build(BuildContext context) {
    final compact = !isWide(context);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        title: const Text(
          'Organize library',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          TextButton.icon(
            onPressed: _loading ? null : _reset,
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: Text(compact ? 'Reset' : 'Reset section'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? Center(child: CircularProgressIndicator(color: accentInk))
            : Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 16 : 24,
                      8,
                      compact ? 16 : 24,
                      12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Shape the guide without changing your IPTV services.',
                          style: TextStyle(color: muted, fontSize: 13),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final section in _sections)
                              ChoiceChip(
                                avatar: Icon(section.$3, size: 17),
                                label: Text(section.$2),
                                selected: _section == section.$1,
                                onSelected: (_) => _changeSection(section.$1),
                              ),
                          ],
                        ),
                        if (_sources.length > 1) ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _sourceScope,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Service',
                              prefixIcon: Icon(Icons.dns_outlined),
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: 'all',
                                child: Text('All included services'),
                              ),
                              for (final source in _sources)
                                DropdownMenuItem(
                                  value: source.$1,
                                  child: Text(source.$2),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => _sourceScope = value ?? 'all'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(child: _categoryList(compact)),
                ],
              ),
      ),
    );
  }

  Widget _categoryList(bool compact) {
    final categories = _visibleEditorCategories;
    if (categories.isEmpty) {
      return Center(
        child: Text(
          'No $_sectionLabel categories found.',
          style: TextStyle(color: muted),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 24,
        0,
        compact ? 12 : 24,
        100,
      ),
      itemCount: categories.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _categoryRow(
        categories[index],
        index: index,
        count: categories.length,
        compact: compact,
      ),
    );
  }

  Widget _categoryRow(
    Category category, {
    required int index,
    required int count,
    required bool compact,
  }) {
    final hidden = _organization!.isHidden(_section, category.id);
    final group = _organization!.groupFor(_section, category.id);
    final renamed =
        _organization!.displayName(_section, category) != category.name;
    return Glass(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          IconButton(
            tooltip: hidden ? 'Show category' : 'Hide category',
            onPressed: () async {
              _organization!.setHidden(_section, category.id, !hidden);
              await _save();
            },
            icon: Icon(
              hidden
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: hidden ? muted : accentInk,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _organization!.displayName(_section, category),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: hidden ? muted : textHi,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (category.sourceLabel.isNotEmpty) category.sourceLabel,
                    if (renamed) 'Renamed',
                    if (group != null) 'Combined group',
                    if (hidden) 'Hidden',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: subtle, fontSize: 11.5),
                ),
              ],
            ),
          ),
          if (!compact) ...[
            IconButton(
              tooltip: 'Move up',
              onPressed: index == 0 ? null : () => _move(category, -1),
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
            IconButton(
              tooltip: 'Move down',
              onPressed: index == count - 1 ? null : () => _move(category, 1),
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
            IconButton(
              tooltip: 'Rename',
              onPressed: () => _rename(category),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
          PopupMenuButton<_CategoryAction>(
            tooltip: 'Category actions',
            onSelected: (action) => _act(category, action),
            itemBuilder: (_) => [
              if (compact)
                const PopupMenuItem(
                  value: _CategoryAction.rename,
                  child: Text('Rename'),
                ),
              if (compact && index > 0)
                const PopupMenuItem(
                  value: _CategoryAction.moveUp,
                  child: Text('Move up'),
                ),
              if (compact && index < count - 1)
                const PopupMenuItem(
                  value: _CategoryAction.moveDown,
                  child: Text('Move down'),
                ),
              const PopupMenuItem(
                value: _CategoryAction.merge,
                child: Text('Combine with…'),
              ),
              if (group != null)
                const PopupMenuItem(
                  value: _CategoryAction.unmerge,
                  child: Text('Remove from combined group'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
