import 'dart:async';

import 'package:flutter/material.dart';

import '../data/attachment_store.dart';
import '../data/achievement_repository.dart';
import '../data/note_repository.dart';
import '../data/todo_repository.dart';
import '../models/achievement.dart';
import '../models/note.dart';
import '../models/todo.dart';
import '../services/ai_service.dart';
import '../services/todo_reminder_service.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.repository,
    required this.attachmentStore,
    this.todoReminderService,
    AiSettingsStore? aiSettingsStore,
  }) : aiSettingsStore = aiSettingsStore ?? AiSettingsStore();

  final NoteRepository repository;
  final AttachmentStore attachmentStore;
  final TodoReminderService? todoReminderService;
  final AiSettingsStore aiSettingsStore;
  StreamSubscription<void>? _subscription;

  bool initialized = false;
  Object? initializationError;
  bool loading = true;
  List<Note> notes = const [];
  List<Note> trashedNotes = const [];
  List<Todo> todos = const [];
  List<Todo> trashedTodos = const [];
  List<String> tags = const [];
  List<Achievement> achievements = const [];
  AiConfig aiConfig = const AiConfig();
  final List<Achievement> _pendingAchievements = [];

  Future<void> initialize() async {
    try {
      await repository.initialize();
      aiConfig = await aiSettingsStore.load();
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
    await todoReminderService?.syncReminders(todos);
    tags = await repository.getTags();
    achievements = await _achievementRepository?.getAchievements() ?? const [];
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

  AchievementRepository? get _achievementRepository =>
      repository is AchievementRepository
      ? repository as AchievementRepository
      : null;

  Future<bool> requestTodoReminderPermission() async =>
      await todoReminderService?.requestPermission() ?? false;

  Future<bool> requestTodoNotificationPermission() async =>
      await todoReminderService?.requestNotificationPermission() ?? false;

  Future<bool> openTodoReminderSettings() async =>
      await todoReminderService?.openNotificationSettings() ?? false;

  Future<bool> showTodoTestReminder() async =>
      await todoReminderService?.showTestReminder() ?? false;

  Future<void> saveTodo(Todo todo) async {
    await _todos?.saveTodo(todo);
    if (!todo.reminderEnabled) await todoReminderService?.cancel(todo.id);
  }

  Future<void> completeTodo(
    String id,
    bool completed, {
    DateTime? nextDueAt,
  }) async {
    final source = findTodo(id) ?? findTodo(id, deleted: true);
    await _todos?.setTodoCompleted(id, completed, nextDueAt: nextDueAt);
    if (completed) {
      await todoReminderService?.cancel(id);
      if (source != null && !source.isCompleted) {
        await _registerAchievement(
          _achievementRepository?.recordTodoCompleted(id),
        );
      }
    }
  }

  Future<void> trashTodos(Iterable<String> ids) async {
    final values = ids.toList();
    await _todos?.moveTodosToTrash(values);
    for (final id in values) {
      await todoReminderService?.cancel(id);
    }
  }

  Future<void> restoreTodos(Iterable<String> ids) async =>
      _todos?.restoreTodos(ids);

  Future<void> deleteTodosForever(Iterable<String> ids) async {
    final values = ids.toList();
    await _todos?.permanentlyDeleteTodos(values);
    for (final id in values) {
      await todoReminderService?.cancel(id);
    }
  }

  Future<void> save(Note note, {bool? isNew}) async {
    final shouldCountAsNew =
        isNew ??
        (findNote(note.id) == null && findNote(note.id, deleted: true) == null);
    await repository.saveNote(note);
    if (shouldCountAsNew) {
      await _registerAchievement(
        _achievementRepository?.recordNoteCreated(note.id),
      );
    }
  }

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

  Future<void> saveAiConfig(AiConfig config) async {
    final normalized = AiConfig(
      baseUrl: config.baseUrl.trim(),
      model: config.model.trim(),
      apiKey: config.apiKey.trim(),
    );
    await aiSettingsStore.save(normalized);
    aiConfig = normalized;
    notifyListeners();
  }

  Achievement? takePendingAchievement() =>
      _pendingAchievements.isEmpty ? null : _pendingAchievements.removeAt(0);

  Future<void> _registerAchievement(
    Future<Achievement?>? achievementFuture,
  ) async {
    final achievement = await achievementFuture;
    if (achievement == null) return;
    achievements =
        await _achievementRepository?.getAchievements() ??
        [achievement, ...achievements];
    _pendingAchievements.add(achievement);
    notifyListeners();
  }

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
