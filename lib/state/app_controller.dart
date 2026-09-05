import 'dart:async';

import 'package:flutter/material.dart';

import '../data/attachment_store.dart';
import '../data/note_repository.dart';
import '../data/todo_repository.dart';
import '../models/note.dart';
import '../models/todo.dart';

class AppController extends ChangeNotifier {
  AppController({required this.repository, required this.attachmentStore});

  final NoteRepository repository;
  final AttachmentStore attachmentStore;
  StreamSubscription<void>? _subscription;

  bool initialized = false;
  Object? initializationError;
  bool loading = true;
  List<Note> notes = const [];
  List<Note> trashedNotes = const [];
  List<Todo> todos = const [];
  List<Todo> trashedTodos = const [];
  List<String> tags = const [];

  Future<void> initialize() async {
    try {
      await repository.initialize();
      _subscription = repository.changes.listen((_) => reload());
      initialized = true;
      await reload();
    } catch (error) {
      initializationError = error;
      notifyListeners();
    }
  }

  Future<void> reload() async {
    loading = true;
    notifyListeners();
    notes = await repository.getNotes();
    trashedNotes = await repository.getNotes(deleted: true);
    final todoRepository = repository is TodoRepository
        ? repository as TodoRepository
        : null;
    todos = await todoRepository?.getTodos() ?? const [];
    trashedTodos = await todoRepository?.getTodos(deleted: true) ?? const [];
    tags = await repository.getTags();
    loading = false;
    notifyListeners();
  }

  Note? findNote(String id, {bool deleted = false}) {
    final source = deleted ? trashedNotes : notes;
    for (final note in source) {
      if (note.id == id) return note;
    }
    return null;
  }

  Todo? findTodo(String id, {bool deleted = false}) {
    final source = deleted ? trashedTodos : todos;
    for (final todo in source) {
      if (todo.id == id) return todo;
    }
    return null;
  }

  TodoRepository? get _todos =>
      repository is TodoRepository ? repository as TodoRepository : null;

  Future<void> saveTodo(Todo todo) async => _todos?.saveTodo(todo);
  Future<void> completeTodo(
    String id,
    bool completed, {
    DateTime? nextDueAt,
  }) async => _todos?.setTodoCompleted(
    id,
    completed,
    nextDueAt: nextDueAt,
  );
  Future<void> trashTodos(Iterable<String> ids) async =>
      _todos?.moveTodosToTrash(ids);
  Future<void> restoreTodos(Iterable<String> ids) async =>
      _todos?.restoreTodos(ids);
  Future<void> deleteTodosForever(Iterable<String> ids) async =>
      _todos?.permanentlyDeleteTodos(ids);

  Future<void> save(Note note) => repository.saveNote(note);
  Future<void> trash(Iterable<String> ids) => repository.moveToTrash(ids);
  Future<void> restore(Iterable<String> ids) => repository.restore(ids);

  Future<void> deleteForever(Iterable<String> ids) async {
    final paths = await repository.permanentlyDelete(ids);
    await attachmentStore.deleteFiles(paths);
  }

  Future<void> favorite(String id, bool value) =>
      repository.setFavorite(id, value);
  Future<void> addTag(String tag) => repository.addTag(tag);
  Future<void> deleteTag(String tag) => repository.deleteTag(tag);

  @override
  void dispose() {
    _subscription?.cancel();
    repository.close();
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing');
    return scope!.notifier!;
  }

  static AppController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing');
    return scope!.notifier!;
  }
}
