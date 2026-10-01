class Note {
  const Note({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Database row id – always present for persisted notes.
  final int? id;
  final String title;
  final String content;
  final String createdAt;
  final String updatedAt;

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: (json['id'] as num?)?.toInt(),
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }

  Note copyWith({
    int? id,
    String? title,
    String? content,
    String? createdAt,
    String? updatedAt,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'Note(id: $id, title: $title, updatedAt: $updatedAt)';
}
