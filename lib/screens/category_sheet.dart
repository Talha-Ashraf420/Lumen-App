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
        : widget.categories
              .where((c) => c.name.toLowerCase().contains(q))
              .toList();
    final options = <(String, String)>[
      ('all', 'All categories'),
      for (final category in filtered) (category.id, category.name),
    ];

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
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: subtle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.category_outlined,
                        color: accent,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Choose a collection',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Focus the catalog around what you want now.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: surfaceHi,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${widget.categories.length}',
                        style: TextStyle(
                          color: muted,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // search categories (unified field — single border)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: SearchField(
                  hint: 'Search categories…',
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
              Expanded(
                child: filtered.isEmpty && q.isNotEmpty
                    ? const LumenEmptyState(
                        icon: Icons.search_off_rounded,
                        eyebrow: 'No match',
                        title: 'Try another category name',
                        message:
                            'The current provider has no collection matching that search.',
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth >= 700) {
                            return GridView.builder(
                              controller: scroll,
                              padding: const EdgeInsets.fromLTRB(14, 2, 14, 24),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 300,
                                    mainAxisExtent: 60,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                  ),
                              itemCount: options.length,
                              itemBuilder: (_, index) =>
                                  _row(options[index].$1, options[index].$2),
                            );
                          }
                          return ListView.builder(
                            controller: scroll,
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                            itemCount: options.length,
                            itemBuilder: (_, index) =>
                                _row(options[index].$1, options[index].$2),
                          );
                        },
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
    return RemoteTap(
      autofocus: id == 'all',
      onTap: () => Navigator.of(context).pop(id),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: sel
              ? accent.withValues(alpha: 0.15)
              : surfaceHi.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: sel ? accent.withValues(alpha: 0.48) : line,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: sel ? accent : surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                id == 'all' ? Icons.apps_rounded : Icons.folder_outlined,
                color: sel ? onAccent : muted,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: sel ? textHi : cream,
                ),
              ),
            ),
            if (sel) Icon(Icons.check_rounded, color: accent, size: 18),
          ],
        ),
      ),
    );
  }
}
