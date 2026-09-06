import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/note.dart';
import '../models/todo.dart';
import '../models/achievement.dart';
import 'achievement_repository.dart';
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

class SqliteNoteRepository
    implements NoteRepository, TodoRepository, AchievementRepository {
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
      version: 8,
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
          CREATE TABLE video_attachments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
            path TEXT NOT NULL,
            sort_order INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE audio_attachments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
            path TEXT NOT NULL,
            sort_order INTEGER NOT NULL
          )
        ''');
        await _createTodosTable(db);
        await _createAchievementTables(db, seedExisting: false);
        for (final tag in const ['工作', '学习', '生活', '重要', '随笔']) {
          await db.insert('tags', {'name': tag});
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createTodosTable(db);
        } else {
          if (oldVersion < 3) {
            await db.execute('ALTER TABLE todos ADD COLUMN repeat_day INTEGER');
            await db.execute(
              'ALTER TABLE todos ADD COLUMN repeat_month INTEGER',
            );
          }
          if (oldVersion < 4) {
            await db.execute(
              "ALTER TABLE todos ADD COLUMN priority TEXT NOT NULL DEFAULT 'p1'",
            );
          }
          if (oldVersion < 5) {
            await db.execute(
              'ALTER TABLE todos ADD COLUMN reminder_enabled INTEGER NOT NULL DEFAULT 0',
            );
          }
        }
        if (oldVersion < 6) {
          await db.execute('DROP TABLE IF EXISTS checklist_items');
          await db.execute('''
            CREATE TABLE video_attachments (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
              path TEXT NOT NULL,
              sort_order INTEGER NOT NULL
            )
          ''');
        }
        if (oldVersion < 7) {
          await db.execute('''
            CREATE TABLE audio_attachments (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
              path TEXT NOT NULL,
              sort_order INTEGER NOT NULL
            )
          ''');
        }
        if (oldVersion < 8) {
          await _createAchievementTables(db, seedExisting: true);
        }
      },
    );
  }

  static const _achievementMilestones = [10, 100, 250, 1000];

  Future<void> _createAchievementTables(
    DatabaseExecutor db, {
    required bool seedExisting,
  }) async {
    await db.execute('''
      CREATE TABLE achievements (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        milestone INTEGER NOT NULL,
        unlocked_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE achievement_progress (
        kind TEXT PRIMARY KEY,
        count INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE achievement_counted_notes (
        note_id TEXT PRIMARY KEY
      )
    ''');
    await db.execute('''
      CREATE TABLE achievement_counted_todos (
        todo_id TEXT PRIMARY KEY
      )
    ''');

    var noteCount = 0;
    var todoCount = 0;
    if (seedExisting) {
      await db.execute(
        'INSERT INTO achievement_counted_notes(note_id) SELECT id FROM notes',
      );
      await db.execute(
        'INSERT INTO achievement_counted_todos(todo_id) '
        'SELECT id FROM todos WHERE completed = 1',
      );
      noteCount =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM achievement_counted_notes'),
          ) ??
          0;
      todoCount =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM achievement_counted_todos'),
          ) ??
          0;
    }
    await db.insert('achievement_progress', {
      'kind': AchievementKind.notesCreated.name,
      'count': noteCount,
    });
    await db.insert('achievement_progress', {
      'kind': AchievementKind.todosCompleted.name,
      'count': todoCount,
    });

    final now = DateTime.now().millisecondsSinceEpoch;
    for (final milestone in _achievementMilestones) {
      if (noteCount >= milestone) {
        await _insertAchievement(
          db,
          AchievementKind.notesCreated,
          milestone,
          now,
        );
      }
      if (todoCount >= milestone) {
        await _insertAchievement(
          db,
          AchievementKind.todosCompleted,
          milestone,
          now,
        );
      }
    }
  }

  Future<void> _createTodosTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE todos (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        due_at INTEGER NOT NULL,
        priority TEXT NOT NULL DEFAULT 'p1',
        reminder_enabled INTEGER NOT NULL DEFAULT 0,
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

  @override
  Future<List<Achievement>> getAchievements() async {
    final rows = await _db.query('achievements', orderBy: 'unlocked_at DESC');
    return rows.map(_achievementFromRow).toList();
  }

  @override
  Future<Achievement?> recordNoteCreated(String noteId) =>
      _recordAchievementProgress(
        kind: AchievementKind.notesCreated,
        countedTable: 'achievement_counted_notes',
        idColumn: 'note_id',
        sourceId: noteId,
      );

  @override
  Future<Achievement?> recordTodoCompleted(String todoId) =>
      _recordAchievementProgress(
        kind: AchievementKind.todosCompleted,
        countedTable: 'achievement_counted_todos',
        idColumn: 'todo_id',
        sourceId: todoId,
      );

  Future<Achievement?> _recordAchievementProgress({
    required AchievementKind kind,
    required String countedTable,
    required String idColumn,
    required String sourceId,
  }) async {
    return _db.transaction((txn) async {
      final counted = await txn.query(
        countedTable,
        where: '$idColumn = ?',
        whereArgs: [sourceId],
        limit: 1,
      );
      if (counted.isNotEmpty) return null;

      await txn.insert(countedTable, {idColumn: sourceId});
      final progress = await txn.query(
        'achievement_progress',
        columns: ['count'],
        where: 'kind = ?',
        whereArgs: [kind.name],
        limit: 1,
      );
      final count = (progress.single['count']! as int) + 1;
      await txn.update(
        'achievement_progress',
        {'count': count},
        where: 'kind = ?',
        whereArgs: [kind.name],
      );
      if (!_achievementMilestones.contains(count)) return null;

      final unlockedAt = DateTime.now();
      await _insertAchievement(
        txn,
        kind,
        count,
        unlockedAt.millisecondsSinceEpoch,
      );
      return Achievement(
        id: '${kind.name}_$count',
        kind: kind,
        milestone: count,
        unlockedAt: unlockedAt,
      );
    });
  }

  static Future<void> _insertAchievement(
    DatabaseExecutor db,
    AchievementKind kind,
    int milestone,
    int unlockedAt,
  ) async {
    await db.insert('achievements', {
      'id': '${kind.name}_$milestone',
      'kind': kind.name,
      'milestone': milestone,
      'unlocked_at': unlockedAt,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Achievement _achievementFromRow(Map<String, Object?> row) => Achievement(
    id: row['id']! as String,
    kind: AchievementKind.values.firstWhere((kind) => kind.name == row['kind']),
    milestone: row['milestone']! as int,
    unlockedAt: DateTime.fromMillisecondsSinceEpoch(row['unlocked_at']! as int),
  );

  Todo _todoFromRow(Map<String, Object?> row) => Todo(
    id: row['id']! as String,
    title: row['title']! as String,
    description: row['description']! as String,
    dueAt: DateTime.fromMillisecondsSinceEpoch(row['due_at']! as int),
    priority: TodoPriority.values.firstWhere(
      (value) => value.name == row['priority'],
      orElse: () => TodoPriority.p1,
    ),
    reminderEnabled: row['reminder_enabled'] == 1,
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
    final videoRows = await _db.query(
      'video_attachments',
      columns: ['path'],
      where: 'note_id = ?',
      whereArgs: [id],
      orderBy: 'sort_order',
    );
    final audioRows = await _db.query(
      'audio_attachments',
      columns: ['path'],
      where: 'note_id = ?',
      whereArgs: [id],
      orderBy: 'sort_order',
    );
    return Note(
      id: id,
      title: row['title']! as String,
      content: row['content']! as String,
      imagePaths: imageRows.map((e) => e['path']! as String).toList(),
      videoPaths: videoRows.map((e) => e['path']! as String).toList(),
      audioPaths: audioRows.map((e) => e['path']! as String).toList(),
      tags: tagRows.map((e) => e['tag_name']! as String).toList(),
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
        'video_attachments',
        where: 'note_id = ?',
        whereArgs: [note.id],
      );
      for (var i = 0; i < note.videoPaths.length; i++) {
        await txn.insert('video_attachments', {
          'note_id': note.id,
          'path': note.videoPaths[i],
          'sort_order': i,
        });
      }
      await txn.delete(
        'audio_attachments',
        where: 'note_id = ?',
        whereArgs: [note.id],
      );
      for (var i = 0; i < note.audioPaths.length; i++) {
        await txn.insert('audio_attachments', {
          'note_id': note.id,
          'path': note.audioPaths[i],
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
    final attachments = await _db.rawQuery(
      '''
      SELECT path FROM attachments WHERE note_id IN ($marks)
      UNION ALL
      SELECT path FROM video_attachments WHERE note_id IN ($marks)
      UNION ALL
      SELECT path FROM audio_attachments WHERE note_id IN ($marks)
    ''',
      [...values, ...values, ...values],
    );
    await _db.rawDelete('DELETE FROM notes WHERE id IN ($marks)', values);
    _changes.add(null);
    return attachments.map((e) => e['path']! as String).toList();
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
      orderBy: deleted
          ? 'deleted_at DESC'
          : 'due_at ASC, priority ASC, created_at ASC',
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
    'priority': todo.priority.name,
    'reminder_enabled': todo.reminderEnabled ? 1 : 0,
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
