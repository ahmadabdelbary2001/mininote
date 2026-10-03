import 'package:flutter_test/flutter_test.dart';
import 'package:mininote/models/note.dart';

void main() {
  group('Note Model Tests', () {
    test('Note.fromJson parses valid JSON properly', () {
      final json = {
        'id': 1,
        'title': 'Test Note',
        'content': 'Hello from Flutter',
        'created_at': '2026-10-03T00:00:00Z',
        'updated_at': '2026-10-03T01:00:00Z',
      };
      final note = Note.fromJson(json);
      expect(note.id, 1);
      expect(note.title, 'Test Note');
      expect(note.content, 'Hello from Flutter');
      expect(note.createdAt, '2026-10-03T00:00:00Z');
      expect(note.updatedAt, '2026-10-03T01:00:00Z');
    });

    test('Note.copyWith updates fields correctly', () {
      final note = const Note(
        id: 1,
        title: 'Old Title',
        content: 'Old Content',
        createdAt: '2026-10-03T00:00:00Z',
        updatedAt: '2026-10-03T00:00:00Z',
      );
      final updated = note.copyWith(title: 'New Title');
      expect(updated.id, 1);
      expect(updated.title, 'New Title');
      expect(updated.content, 'Old Content');
    });
  });
}
