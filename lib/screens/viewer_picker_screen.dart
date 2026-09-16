import 'package:flutter/material.dart';

import '../viewing_profiles.dart';
import '../widgets.dart';

/// Local household viewers share IPTV services but not viewing activity.
class ViewerPickerScreen extends StatelessWidget {
  const ViewerPickerScreen({
    super.key,
    required this.onSelect,
    this.embedded = false,
  });

  final Future<void> Function(String id) onSelect;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final content = AnimatedBuilder(
      animation: ViewingProfiles.instance,
      builder: (context, _) {
        final controller = ViewingProfiles.instance;
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Who’s watching?',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Each viewer has their own My List, history, and Continue Watching.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (
                    var index = 0;
                    index < controller.profiles.length;
                    index++
                  )
                    _viewerTile(context, controller.profiles[index], index),
                  if (controller.canAdd)
                    OutlinedButton.icon(
                      onPressed: () => _editName(context),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add viewer'),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (embedded) return content;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _viewerTile(BuildContext context, ViewingProfile profile, int index) {
    final controller = ViewingProfiles.instance;
    final selected = controller.activeId == profile.id;
    final width = MediaQuery.sizeOf(context).width < 520 ? 145.0 : 180.0;
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            TextButton(
              autofocus: index == 0,
              onPressed: () => onSelect(profile.id),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                padding: EdgeInsets.zero,
                shape: const RoundedRectangleBorder(),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      child: Text(
                        profile.name.characters.first.toUpperCase(),
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      selected ? 'Current viewer' : 'Switch viewer',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Rename ${profile.name}',
                  onPressed: () => _editName(context, profile: profile),
                  icon: const Icon(Icons.edit_outlined, size: 19),
                ),
                if (profile.id != ViewingProfiles.defaultId && !selected)
                  IconButton(
                    tooltip: 'Remove ${profile.name}',
                    onPressed: () => _remove(context, profile),
                    icon: const Icon(Icons.delete_outline_rounded, size: 19),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editName(
    BuildContext context, {
    ViewingProfile? profile,
  }) async {
    final input = TextEditingController(text: profile?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(profile == null ? 'Add viewer' : 'Rename viewer'),
        content: RemoteTextInput(
          child: TextField(
            controller: input,
            autofocus: true,
            maxLength: 32,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Viewer name'),
            onSubmitted: (value) => Navigator.pop(dialogContext, value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, input.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    input.dispose();
    if (name == null || !context.mounted) return;
    try {
      if (profile == null) {
        await ViewingProfiles.instance.add(name);
      } else {
        await ViewingProfiles.instance.rename(profile.id, name);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _remove(BuildContext context, ViewingProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${profile.name}?'),
        content: const Text(
          'Their My List, watch history, and Home layout on this device will be deleted. Connected services and downloads stay available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) await ViewingProfiles.instance.remove(profile.id);
  }
}
