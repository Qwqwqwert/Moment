class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.text,
    this.isChecked = false,
  });

  final String id;
  final String text;
  final bool isChecked;

  ChecklistItem copyWith({String? text, bool? isChecked}) => ChecklistItem(
    id: id,
    text: text ?? this.text,
    isChecked: isChecked ?? this.isChecked,
  );
}

class Note {
  const Note({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.imagePaths = const [],
    this.tags = const [],
    this.checklist = const [],
    this.isFavorite = false,
    this.deletedAt,
  });

  final String id;
  final String title;
  final String content;
  final List<String> imagePaths;
  final List<String> tags;
  final List<ChecklistItem> checklist;
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
    List<String>? tags,
    List<ChecklistItem>? checklist,
    DateTime? updatedAt,
    bool? isFavorite,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) => Note(
    id: id,
    title: title ?? this.title,
    content: content ?? this.content,
    imagePaths: imagePaths ?? this.imagePaths,
    tags: tags ?? this.tags,
    checklist: checklist ?? this.checklist,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isFavorite: isFavorite ?? this.isFavorite,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
  );
}

String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);
