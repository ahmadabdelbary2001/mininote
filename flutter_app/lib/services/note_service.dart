import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../ffi/native_core_bindings.dart';
import '../models/note.dart';

class NoteService {
  static bool _isInitialized = false;
  static final NativeCoreBindings _bindings = NativeCoreBindings.instance;

  static Future<void> init() async {
    if (_isInitialized) return;
    if (kIsWeb) {
      throw UnsupportedError('MiniNote FFI is not supported on web.');
    }

    final dir = await getApplicationDocumentsDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final dbPath = '${dir.path}${Platform.pathSeparator}mininotes.db';
    _bindings.initDb(dbPath);
    _isInitialized = true;
  }

  Future<List<Note>> getNotes() async {
    return _bindings.fetchNotes();
  }

  Future<Note> createNote(String title, String content) async {
    return _bindings.addNote(title, content);
  }

  Future<void> updateNote(int id, String title, String content) async {
    _bindings.updateNote(id, title, content);
  }

  Future<void> deleteNote(int id) async {
    _bindings.deleteNote(id);
  }
}
