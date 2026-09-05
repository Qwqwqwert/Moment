import 'package:flutter_test/flutter_test.dart';
import 'package:moment/models/note.dart';

void main() {
  test('note blank state ignores metadata but respects content', () {
    final now = DateTime(2026, 8, 18);
    final blank = Note(
      id: '1',
      title: '  ',
      content: '\n',
      createdAt: now,
      updatedAt: now,
    );
    expect(blank.isBlank, isTrue);
    expect(blank.copyWith(content: '正文').isBlank, isFalse);
  });

  test('clearing deletedAt restores a note', () {
    final now = DateTime(2026, 8, 18);
    final deleted = Note(
      id: '1',
      title: '标题',
      content: '',
      createdAt: now,
      updatedAt: now,
      deletedAt: now,
    );
    expect(deleted.isDeleted, isTrue);
    expect(deleted.copyWith(clearDeletedAt: true).isDeleted, isFalse);
  });
}
