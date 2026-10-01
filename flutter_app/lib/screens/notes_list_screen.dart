import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/notes_provider.dart';
import '../models/note.dart';
import 'note_editor_screen.dart';

class NotesListScreen extends StatelessWidget {
  const NotesListScreen({super.key});

  static const _headerBg = Color(0xFF2C001E);
  static const _accent = Color(0xFF77216F);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            _Header(),
            const Expanded(child: _NotesList()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        elevation: 4,
        onPressed: () => _openEditor(context, null),
        tooltip: 'New Note',
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }

  static void _openEditor(BuildContext context, Note? note) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(note: note),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final count = context.select<NotesProvider, int>((p) => p.notes.length);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      color: NotesListScreen._headerBg,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: Row(
        children: [
          Text(
            'MiniNote',
            style: textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          if (count > 0)
            Text(
              count == 1 ? '1 note' : '$count notes',
              style: textTheme.bodyMedium?.copyWith(
                color: const Color(0xFFE6DDE4),
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}

class _NotesList extends StatelessWidget {
  const _NotesList();

  @override
  Widget build(BuildContext context) {
    return Consumer<NotesProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Center(
            child: CircularProgressIndicator(
              color: NotesListScreen._accent,
            ),
          );
        }

        if (provider.errorMessage != null) {
          return _ErrorState(message: provider.errorMessage!);
        }

        if (provider.notes.isEmpty) {
          return const _EmptyState();
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: provider.notes.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final note = provider.notes[index];
            return _NoteCard(
              note: note,
              onEdit: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NoteEditorScreen(note: note),
                ),
              ),
              onDelete: () => _confirmDelete(context, provider, note),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    NotesProvider provider,
    Note note,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note'),
        content: Text('Delete "${note.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && note.id != null) {
      await provider.deleteNote(note.id!);
    }
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.onEdit,
    required this.onDelete,
  });

  final Note note;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 1,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD8D3D7), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF2D252B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (note.content.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        note.content,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF6F676D),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (note.updatedAt.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _formatDate(note.updatedAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF9E9E9E),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                color: const Color(0xFFC62828),
                tooltip: 'Delete',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inDays == 0) {
        return 'Today ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } else if (diff.inDays == 1) {
        return 'Yesterday';
      } else {
        return '${dt.day}/${dt.month}/${dt.year}';
      }
    } catch (_) {
      return iso;
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.note_outlined,
              size: 80,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 20),
            Text(
              'No notes yet',
              style: theme.textTheme.titleLarge?.copyWith(
                color: const Color(0xFF2D252B),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the + button to create your first note.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF6F676D),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.read<NotesProvider>().loadNotes(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: NotesListScreen._accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
