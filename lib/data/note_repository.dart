import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/note.dart';
import '../models/todo.dart';
import 'todo_repository.dart';

abstract interface class NoteRepository {
  Future<void> initialize();
  Stream<void> get changes;
  Future<List<Note>> getNotes({bool deleted = false, bool favorites = false});
  Future<Note?> getNote(String id, {bool includeDeleted = false});
  Future<void> saveNote(Note note);
  Future<void> moveToTrash(Iterable<String> ids);
  Future<void> restore(Iterable<String> ids);
  Future<List<String>> permanentlyDelete(Iterable<String> ids);
  Future<void> setFavorite(String id, bool value);
  Future<List<String>> getTags();
  Future<void> addTag(String tag);
  Future<void> deleteTag(String tag);
  Future<void> close();
}

class SqliteNoteRepository implements NoteRepository, TodoRepository {
  Database? _database;
  final _changes = StreamController<void>.broadcast();

  Database get _db => _database!;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> initialize() async {
    final root = await getDatabasesPath();
    _database = await openDatabase(
      p.join(root, 'moment.sqlite'),
      version: 3,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE notes (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            favorite INTEGER NOT NULL DEFAULT 0,
            deleted_at INTEGER
          )
        ''');
        await db.execute(
          'CREATE INDEX notes_deleted_updated ON notes(deleted_at, updated_at DESC)',
        );
        await db.execute('CREATE TABLE tags (name TEXT PRIMARY KEY)');
        await db.execute('''
          CREATE TABLE note_tags (
            note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
            tag_name TEXT NOT NULL REFERENCES tags(name) ON DELETE CASCADE,
            PRIMARY KEY(note_id, tag_name)
          )
        ''');
        await db.execute('''
          CREATE TABLE attachments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
            path TEXT NOT NULL,
            sort_order INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE checklist_items (
            id TEXT PRIMARY KEY,
            note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
            text TEXT NOT NULL,
            checked INTEGER NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL
          )
        ''');
        await _createTodosTable(db);
        for (final tag in const ['工作', '学习', '生活', '重要', '随笔']) {
          await db.insert('tags', {'name': tag});
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createTodosTable(db);
        } else if (oldVersion < 3) {
          await db.execute('ALTER TABLE todos ADD COLUMN repeat_day INTEGER');
          await db.execute(
            'ALTER TABLE todos ADD COLUMN repeat_month INTEGER',
          );
        }
      },
    );
  }

  Future<void> _createTodosTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE todos (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        due_at INTEGER NOT NULL,
        repeat_type TEXT NOT NULL DEFAULT 'none',
        repeat_day INTEGER,
        repeat_month INTEGER,
        completed INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX todos_state_due ON todos(deleted_at, completed, due_at)',
    );
  }

  Todo _todoFromRow(Map<String, Object?> row) => Todo(
    id: row['id']! as String,
    title: row['title']! as String,
    description: row['description']! as String,
    dueAt: DateTime.fromMillisecondsSinceEpoch(row['due_at']! as int),
    repeat: TodoRepeat.values.firstWhere(
      (value) => value.name == row['repeat_type'],
      orElse: () => TodoRepeat.none,
    ),
    repeatDayOfMonth: row['repeat_day'] as int?,
    repeatMonth: row['repeat_month'] as int?,
    isCompleted: row['completed'] == 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
    deletedAt: row['deleted_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['deleted_at']! as int),
  );

  Future<Note> _hydrate(Map<String, Object?> row) async {
    final id = row['id']! as String;
    final tagRows = await _db.query(
      'note_tags',
      columns: ['tag_name'],
      where: 'note_id = ?',
      whereArgs: [id],
      orderBy: 'tag_name COLLATE NOCASE',
    );
    final imageRows = await _db.query(
      'attachments',
      columns: ['path'],
      where: 'note_id = ?',
      whereArgs: [id],
      orderBy: 'sort_order',
    );
    final checklistRows = await _db.query(
      'checklist_items',
      where: 'note_id = ?',
      whereArgs: [id],
      orderBy: 'sort_order',
    );
    return Note(
      id: id,
      title: row['title']! as String,
      content: row['content']! as String,
      imagePaths: imageRows.map((e) => e['path']! as String).toList(),
      tags: tagRows.map((e) => e['tag_name']! as String).toList(),
      checklist: checklistRows
          .map(
            (e) => ChecklistItem(
              id: e['id']! as String,
              text: e['text']! as String,
              isChecked: e['checked'] == 1,
            ),
          )
          .toList(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
      isFavorite: row['favorite'] == 1,
      deletedAt: row['deleted_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['deleted_at']! as int),
    );
  }

  @override
  Future<List<Note>> getNotes({
    bool deleted = false,
    bool favorites = false,
  }) async {
    final where = <String>[
      deleted ? 'deleted_at IS NOT NULL' : 'deleted_at IS NULL',
    ];
    if (favorites) where.add('favorite = 1');
    final rows = await _db.query(
      'notes',
      where: where.join(' AND '),
      orderBy: deleted ? 'deleted_at DESC' : 'updated_at DESC',
    );
    return Future.wait(rows.map(_hydrate));
  }

  @override
  Future<Note?> getNote(String id, {bool includeDeleted = false}) async {
    final rows = await _db.query(
      'notes',
      where: includeDeleted ? 'id = ?' : 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _hydrate(rows.single);
  }

  @override
  Future<void> saveNote(Note note) async {
    await _db.transaction((txn) async {
      await txn.insert('notes', {
        'id': note.id,
        'title': note.title,
        'content': note.content,
        'created_at': note.createdAt.millisecondsSinceEpoch,
        'updated_at': note.updatedAt.millisecondsSinceEpoch,
        'favorite': note.isFavorite ? 1 : 0,
        'deleted_at': note.deletedAt?.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.delete('note_tags', where: 'note_id = ?', whereArgs: [note.id]);
      for (final tag in note.tags) {
        await txn.insert('tags', {
          'name': tag,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        await txn.insert('note_tags', {'note_id': note.id, 'tag_name': tag});
      }
      await txn.delete(
        'attachments',
        where: 'note_id = ?',
        whereArgs: [note.id],
      );
      for (var i = 0; i < note.imagePaths.length; i++) {
        await txn.insert('attachments', {
          'note_id': note.id,
          'path': note.imagePaths[i],
          'sort_order': i,
        });
      }
      await txn.delete(
        'checklist_items',
        where: 'note_id = ?',
        whereArgs: [note.id],
      );
      for (var i = 0; i < note.checklist.length; i++) {
        final item = note.checklist[i];
        await txn.insert('checklist_items', {
          'id': item.id,
          'note_id': note.id,
          'text': item.text,
          'checked': item.isChecked ? 1 : 0,
          'sort_order': i,
        });
      }
    });
    _changes.add(null);
  }

  @override
  Future<void> moveToTrash(Iterable<String> ids) async {
    final values = ids.toList();
    if (values.isEmpty) return;
    final marks = List.filled(values.length, '?').join(',');
    await _db.rawUpdate(
      'UPDATE notes SET deleted_at = ?, updated_at = ? WHERE id IN ($marks)',
      [
        DateTime.now().millisecondsSinceEpoch,
        DateTime.now().millisecondsSinceEpoch,
        ...values,
      ],
    );
    _changes.add(null);
  }

  @override
  Future<void> restore(Iterable<String> ids) async {
    final values = ids.toList();
    if (values.isEmpty) return;
    final marks = List.filled(values.length, '?').join(',');
    await _db.rawUpdate(
      'UPDATE notes SET deleted_at = NULL WHERE id IN ($marks)',
      values,
    );
    _changes.add(null);
  }

  @override
  Future<List<String>> permanentlyDelete(Iterable<String> ids) async {
    final values = ids.toList();
    if (values.isEmpty) return [];
    final marks = List.filled(values.length, '?').join(',');
    final images = await _db.rawQuery(
      'SELECT path FROM attachments WHERE note_id IN ($marks)',
      values,
    );
    await _db.rawDelete('DELETE FROM notes WHERE id IN ($marks)', values);
    _changes.add(null);
    return images.map((e) => e['path']! as String).toList();
  }

  @override
  Future<void> setFavorite(String id, bool value) async {
    await _db.update(
      'notes',
      {
        'favorite': value ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _changes.add(null);
  }

  @override
  Future<List<String>> getTags() async {
    final rows = await _db.query('tags', orderBy: 'name COLLATE NOCASE');
    return rows.map((e) => e['name']! as String).toList();
  }

  @override
  Future<void> addTag(String tag) async {
    await _db.insert('tags', {
      'name': tag,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    _changes.add(null);
  }

  @override
  Future<void> deleteTag(String tag) async {
    await _db.delete('tags', where: 'name = ?', whereArgs: [tag]);
    _changes.add(null);
  }

  @override
  Future<List<Todo>> getTodos({bool deleted = false, bool? completed}) async {
    final where = <String>[
      deleted ? 'deleted_at IS NOT NULL' : 'deleted_at IS NULL',
    ];
    if (completed != null) where.add('completed = ${completed ? 1 : 0}');
    final rows = await _db.query(
      'todos',
      where: where.join(' AND '),
      orderBy: deleted ? 'deleted_at DESC' : 'due_at ASC',
    );
    return rows.map(_todoFromRow).toList();
  }

  @override
  Future<Todo?> getTodo(String id, {bool includeDeleted = false}) async {
    final rows = await _db.query(
      'todos',
      where: includeDeleted ? 'id = ?' : 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _todoFromRow(rows.single);
  }

  Map<String, Object?> _todoRow(Todo todo) => {
    'id': todo.id,
    'title': todo.title,
    'description': todo.description,
    'due_at': todo.dueAt.millisecondsSinceEpoch,
    'repeat_type': todo.repeat.name,
    'repeat_day': todo.repeatDayOfMonth,
    'repeat_month': todo.repeatMonth,
    'completed': todo.isCompleted ? 1 : 0,
    'created_at': todo.createdAt.millisecondsSinceEpoch,
    'updated_at': todo.updatedAt.millisecondsSinceEpoch,
    'deleted_at': todo.deletedAt?.millisecondsSinceEpoch,
  };

  @override
  Future<void> saveTodo(Todo todo) async {
    await _db.insert(
      'todos',
      _todoRow(todo),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _changes.add(null);
  }

  @override
  Future<void> setTodoCompleted(
    String id,
    bool completed, {
    DateTime? nextDueAt,
  }) async {
    await _db.transaction((txn) async {
      final rows = await txn.query('todos', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) return;
      final todo = _todoFromRow(rows.single);
      if (todo.isCompleted == completed) return;
      await txn.update(
        'todos',
        {
          'completed': completed ? 1 : 0,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (completed) {
        final next = todo.nextOccurrence(dueAtOverride: nextDueAt);
        if (next != null) await txn.insert('todos', _todoRow(next));
      }
    });
    _changes.add(null);
  }

  Future<void> _updateTodoIds(
    Iterable<String> ids,
    Map<String, Object?> values,
  ) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    final marks = List.filled(list.length, '?').join(',');
    await _db.update('todos', values, where: 'id IN ($marks)', whereArgs: list);
    _changes.add(null);
  }

  @override
  Future<void> moveTodosToTrash(Iterable<String> ids) => _updateTodoIds(ids, {
    'deleted_at': DateTime.now().millisecondsSinceEpoch,
    'updated_at': DateTime.now().millisecondsSinceEpoch,
  });

  @override
  Future<void> restoreTodos(Iterable<String> ids) =>
      _updateTodoIds(ids, {'deleted_at': null});

  @override
  Future<void> permanentlyDeleteTodos(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    final marks = List.filled(list.length, '?').join(',');
    await _db.delete('todos', where: 'id IN ($marks)', whereArgs: list);
    _changes.add(null);
  }

  @override
  Future<void> close() async {
    await _changes.close();
    await _database?.close();
  }
}
