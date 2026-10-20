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

    final dir = await _resolveDataDirectory();

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final dbPath = '${dir.path}${Platform.pathSeparator}mininotes.db';
    _bindings.initDb(dbPath);
    _isInitialized = true;
  }

  /// Resolves the directory the database is stored in.
  ///
  /// On Linux (Ubuntu Touch / eLinux) the `path_provider` plugin is not
  /// available, so the XDG data directory is resolved directly.  Confined
  /// click applications may only write below `$XDG_DATA_HOME`, which the
  /// launch wrapper points at `$HOME/.local/share/<package>`.
  static Future<Directory> _resolveDataDirectory() async {
    if (Platform.isLinux) {
      final xdgData = Platform.environment['XDG_DATA_HOME'];
      if (xdgData != null && xdgData.isNotEmpty) {
        return Directory(xdgData);
      }

      final home = Platform.environment['HOME'] ?? '';
      if (home.isNotEmpty) {
        return Directory('$home${Platform.pathSeparator}.local'
            '${Platform.pathSeparator}share${Platform.pathSeparator}mininotes');
      }

      return Directory(Directory.systemTemp.path);
    }

    return getApplicationDocumentsDirectory();
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
