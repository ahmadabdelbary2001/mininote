import 'package:flutter/material.dart';
import '../models/note.dart';
import '../services/note_service.dart';

class NotesProvider extends ChangeNotifier {
  final NoteService _service = NoteService();

  List<Note> _notes = [];
  bool _isLoading = true;
  String? _errorMessage;

  List<Note> get notes => List.unmodifiable(_notes);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadNotes() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _notes = await _service.getNotes();
    } catch (e, st) {
      _errorMessage = e.toString();
      debugPrint('Error loading notes: $e\n$st');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addNote(String title, String content) async {
    await _service.createNote(title, content);
    await loadNotes();
  }

  Future<void> updateNote(int id, String title, String content) async {
    await _service.updateNote(id, title, content);
    await loadNotes();
  }

  Future<void> deleteNote(int id) async {
    await _service.deleteNote(id);
    await loadNotes();
  }
}
