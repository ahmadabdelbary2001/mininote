# MiniNote Flutter App

واجهة `MiniNote` الجديدة مبنية بـ `Flutter`، وتتصل بالنواة المحلية المكتوبة بـ `Rust`
عبر `dart:ffi`.

## Structure

```text
flutter_app/
├─ lib/
│  ├─ ffi/native_core_bindings.dart
│  ├─ models/note.dart
│  ├─ providers/notes_provider.dart
│  ├─ screens/
│  ├─ services/note_service.dart
│  └─ main.dart
```

## Native Core

طبقة Rust موجودة في:

```text
../native_core
```

وتصدر دوال C ABI التالية:

```text
c_init_db
c_fetch_notes_json
c_add_note_json
c_edit_note
c_remove_note
c_last_error_message
c_free_string
```

## Environment

- Flutter `3.41.7`
- Dart `3.11.5`
- Rust `1.93.1`
- Cargo `1.93.1`
- OS: Windows

## Notes

- قاعدة البيانات محلية SQLite داخل مجلد مستندات التطبيق.
- هذا المسار الجديد منفصل عن واجهة Qt/QML القديمة الموجودة في جذر المستودع.
