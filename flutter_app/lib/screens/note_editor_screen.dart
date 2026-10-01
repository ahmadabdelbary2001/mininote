import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/note.dart';
import '../providers/notes_provider.dart';

class NoteEditorScreen extends StatefulWidget {
  /// Pass an existing [note] to edit; leave null to create a new note.
  final Note? note;

  const NoteEditorScreen({super.key, this.note});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  static const _accent = Color(0xFF77216F);
  static const _headerBg = Color(0xFF2C001E);

  late final TextEditingController _titleController;
  late final TextEditingController _contentController;

  bool _isSaving = false;
  bool _attempted = false;
  String? _titleError;
  String? _contentError;
  String? _saveError;

  bool get _isEditing => widget.note != null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController =
        TextEditingController(text: widget.note?.content ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  bool _validate() {
    String? te;
    String? ce;
    if (_titleController.text.trim().isEmpty) {
      te = 'Title is required';
    }
    if (_contentController.text.trim().isEmpty) {
      ce = 'Content is required';
    }
    setState(() {
      _titleError = te;
      _contentError = ce;
    });
    return te == null && ce == null;
  }

  Future<void> _save() async {
    setState(() => _attempted = true);
    if (!_validate()) return;

    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    try {
      final provider = context.read<NotesProvider>();
      if (_isEditing) {
        await provider.updateNote(
          widget.note!.id!,
          _titleController.text.trim(),
          _contentController.text.trim(),
        );
      } else {
        await provider.addNote(
          _titleController.text.trim(),
          _contentController.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _isSaving = false;
        _saveError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            Container(
              width: double.infinity,
              color: _headerBg,
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    color: Colors.white,
                    tooltip: 'Back',
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.maybePop(context),
                  ),
                  Expanded(
                    child: Text(
                      _isEditing ? 'Edit Note' : 'New Note',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_isSaving)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Form ────────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Title field
                    Text(
                      'Title',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF6F676D),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _StyledTextField(
                      controller: _titleController,
                      hintText: 'Note title',
                      maxLines: 1,
                      textInputAction: TextInputAction.next,
                      errorText: _attempted ? _titleError : null,
                      onChanged: (_) {
                        if (_attempted) _validate();
                      },
                    ),
                    const SizedBox(height: 20),

                    // Content field
                    Text(
                      'Content',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF6F676D),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _StyledTextField(
                      controller: _contentController,
                      hintText: 'Write your note…',
                      maxLines: null,
                      minLines: 8,
                      textInputAction: TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                      errorText: _attempted ? _contentError : null,
                      onChanged: (_) {
                        if (_attempted) _validate();
                      },
                    ),
                    const SizedBox(height: 16),

                    // Save-error banner
                    if (_saveError != null)
                      Container(
                        padding: const EdgeInsets.all(14),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDECEA),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0xFFE7C2C0)),
                        ),
                        child: Text(
                          _saveError!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFFC1001E),
                          ),
                        ),
                      ),

                    const SizedBox(height: 8),

                    // Save button
                    SizedBox(
                      height: 56,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: _isSaving ? null : _save,
                        child: Text(
                          _isSaving
                              ? 'Saving…'
                              : (_isEditing ? 'Save changes' : 'Save'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A consistent styled text field matching the QML NoteEditorForm design.
class _StyledTextField extends StatelessWidget {
  const _StyledTextField({
    required this.controller,
    required this.hintText,
    this.maxLines = 1,
    this.minLines,
    this.textInputAction,
    this.keyboardType,
    this.errorText,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final int? maxLines;
  final int? minLines;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  static const _accent = Color(0xFF77216F);

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      minLines: minLines,
      textInputAction: textInputAction,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: const TextStyle(
        fontSize: 18,
        color: Color(0xFF2D252B),
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: Color(0xFFAAAAAA)),
        errorText: errorText,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFC9C9C9)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFC9C9C9)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFC1001E)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFC1001E), width: 2),
        ),
      ),
    );
  }
}
