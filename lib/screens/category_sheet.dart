import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// A searchable category picker shown as a bottom sheet.
/// Returns the chosen category id, 'all', or null if dismissed.
Future<String?> showCategorySheet(
  BuildContext context, {
  required List<Category> categories,
  required String? selected,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _CategorySheet(categories: categories, selected: selected),
  );
}

class _CategorySheet extends StatefulWidget {
  final List<Category> categories;
  final String? selected;
  const _CategorySheet({required this.categories, required this.selected});
  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.categories
        : widget.categories.where((c) => c.name.toLowerCase().contains(q)).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scroll) {
        return Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: line)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: subtle, borderRadius: BorderRadius.circular(2))),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Categories', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                ),
              ),
              // search categories (unified field — single border)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: SearchField(hint: 'Search categories…', onChanged: (v) => setState(() => _q = v)),
              ),
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  children: [
                    _row('all', 'All categories'),
                    for (final c in filtered) _row(c.id, c.name),
                    if (filtered.isEmpty)
                      Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('No matches', style: TextStyle(color: subtle)))),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(String id, String name) {
    final sel = (widget.selected ?? 'all') == id;
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(id),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: sel ? accent : surfaceHi.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Expanded(child: Text(name, style: TextStyle(fontWeight: FontWeight.w700, color: sel ? Colors.white : cream))),
          if (sel) const Icon(Icons.check_rounded, color: Colors.white, size: 18),
        ]),
      ),
    );
  }
}
