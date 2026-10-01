import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../models/note.dart';

typedef _CStringFn = Pointer<Utf8> Function();
typedef _CString = Pointer<Utf8> Function();
typedef _FreeStringFn = Void Function(Pointer<Utf8>);
typedef _FreeString = void Function(Pointer<Utf8>);
typedef _InitDbFn = Int32 Function(Pointer<Utf8>);
typedef _InitDb = int Function(Pointer<Utf8>);
typedef _AddNoteFn = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _AddNote = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _EditNoteFn = Int32 Function(Int64, Pointer<Utf8>, Pointer<Utf8>);
typedef _EditNote = int Function(int, Pointer<Utf8>, Pointer<Utf8>);
typedef _RemoveNoteFn = Int32 Function(Int64);
typedef _RemoveNote = int Function(int);

class NativeCoreBindings {
  NativeCoreBindings._()
      : _initDb = _dylib.lookupFunction<_InitDbFn, _InitDb>('c_init_db'),
        _fetchNotesJson =
            _dylib.lookupFunction<_CStringFn, _CString>('c_fetch_notes_json'),
        _addNoteJson =
            _dylib.lookupFunction<_AddNoteFn, _AddNote>('c_add_note_json'),
        _editNote =
            _dylib.lookupFunction<_EditNoteFn, _EditNote>('c_edit_note'),
        _removeNote =
            _dylib.lookupFunction<_RemoveNoteFn, _RemoveNote>('c_remove_note'),
        _lastError =
            _dylib.lookupFunction<_CStringFn, _CString>('c_last_error_message'),
        _freeString =
            _dylib.lookupFunction<_FreeStringFn, _FreeString>('c_free_string');

  static final NativeCoreBindings instance = NativeCoreBindings._();
  static final DynamicLibrary _dylib = _openLibrary();

  final _InitDb _initDb;
  final _CString _fetchNotesJson;
  final _AddNote _addNoteJson;
  final _EditNote _editNote;
  final _RemoveNote _removeNote;
  final _CString _lastError;
  final _FreeString _freeString;

  static DynamicLibrary _openLibrary() {
    if (Platform.isIOS) {
      return DynamicLibrary.process();
    }
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libnative_core.so');
    }

    final executableDir = File(Platform.resolvedExecutable).parent.path;
    if (Platform.isWindows) {
      final dllPath = '$executableDir${Platform.pathSeparator}native_core.dll';
      if (File(dllPath).existsSync()) {
        return DynamicLibrary.open(dllPath);
      }
      return DynamicLibrary.open('native_core.dll');
    }
    if (Platform.isLinux) {
      final bundledLib = '$executableDir${Platform.pathSeparator}lib${Platform.pathSeparator}libnative_core.so';
      if (File(bundledLib).existsSync()) {
        return DynamicLibrary.open(bundledLib);
      }
      final rootLib = '$executableDir${Platform.pathSeparator}libnative_core.so';
      if (File(rootLib).existsSync()) {
        return DynamicLibrary.open(rootLib);
      }
      return DynamicLibrary.open('libnative_core.so');
    }
    if (Platform.isMacOS) {
      final dylibPath = '$executableDir${Platform.pathSeparator}libnative_core.dylib';
      if (File(dylibPath).existsSync()) {
        return DynamicLibrary.open(dylibPath);
      }
      return DynamicLibrary.open('libnative_core.dylib');
    }
    throw UnsupportedError('Unsupported platform for native_core');
  }

  String _takeLastError() {
    final errorPointer = _lastError();
    if (errorPointer.address == 0) {
      return 'Unknown native error';
    }

    try {
      final error = errorPointer.toDartString();
      return error.isEmpty ? 'Unknown native error' : error;
    } finally {
      _freeString(errorPointer);
    }
  }

  Never _throwLastError() {
    throw StateError(_takeLastError());
  }

  String _takeOwnedString(Pointer<Utf8> pointer) {
    try {
      return pointer.toDartString();
    } finally {
      _freeString(pointer);
    }
  }

  void initDb(String path) {
    final pathPointer = path.toNativeUtf8();
    try {
      final result = _initDb(pathPointer);
      if (result != 0) {
        _throwLastError();
      }
    } finally {
      calloc.free(pathPointer);
    }
  }

  List<Note> fetchNotes() {
    final responsePointer = _fetchNotesJson();
    if (responsePointer.address == 0) {
      _throwLastError();
    }

    final rawJson = _takeOwnedString(responsePointer);
    final decoded = jsonDecode(rawJson) as List<dynamic>;
    return decoded
        .map((item) => Note.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Note addNote(String title, String content) {
    final titlePointer = title.toNativeUtf8();
    final contentPointer = content.toNativeUtf8();

    try {
      final responsePointer = _addNoteJson(titlePointer, contentPointer);
      if (responsePointer.address == 0) {
        _throwLastError();
      }

      final rawJson = _takeOwnedString(responsePointer);
      return Note.fromJson(jsonDecode(rawJson) as Map<String, dynamic>);
    } finally {
      calloc.free(titlePointer);
      calloc.free(contentPointer);
    }
  }

  void updateNote(int id, String title, String content) {
    final titlePointer = title.toNativeUtf8();
    final contentPointer = content.toNativeUtf8();

    try {
      final result = _editNote(id, titlePointer, contentPointer);
      if (result != 0) {
        _throwLastError();
      }
    } finally {
      calloc.free(titlePointer);
      calloc.free(contentPointer);
    }
  }

  void deleteNote(int id) {
    final result = _removeNote(id);
    if (result != 0) {
      _throwLastError();
    }
  }
}
