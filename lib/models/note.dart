class Note {
  const Note({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.imagePaths = const [],
    this.videoPaths = const [],
    this.audioPaths = const [],
    this.tags = const [],
    this.isFavorite = false,
    this.deletedAt,
  });

  final String id;
  final String title;
  final String content;
  final List<String> imagePaths;
  final List<String> videoPaths;
  final List<String> audioPaths;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isFavorite;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;
  bool get isBlank => title.trim().isEmpty && content.trim().isEmpty;

  Note copyWith({
    String? title,
    String? content,
    List<String>? imagePaths,
    List<String>? videoPaths,
    List<String>? audioPaths,
    List<String>? tags,
    DateTime? updatedAt,
    bool? isFavorite,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) => Note(
    id: id,
    title: title ?? this.title,
    content: content ?? this.content,
    imagePaths: imagePaths ?? this.imagePaths,
    videoPaths: videoPaths ?? this.videoPaths,
    audioPaths: audioPaths ?? this.audioPaths,
    tags: tags ?? this.tags,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isFavorite: isFavorite ?? this.isFavorite,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
  );
}

String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);
