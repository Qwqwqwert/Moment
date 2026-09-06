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
import '../services/pending_work_coordinator.dart';

class AppController extends ChangeNotifier with WidgetsBindingObserver {
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
  final pendingWork = PendingWorkCoordinator();
  StreamSubscription<void>? _subscription;
  Future<void>? _initializationOperation;
  bool _closed = false;
  int _activeReloads = 0;

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

  Future<void> initialize() => _initializationOperation ??= _initialize();

  Future<void> _initialize() async {
    try {
      await repository.initialize();
      todoReminderService?.bindRepository(repository);
      WidgetsBinding.instance.addObserver(this);
      aiConfig = await aiSettingsStore.load();
      _subscription = repository.changes.listen((_) => reload());
      initialized = true;
      await reload();
    } catch (error) {
      initializationError = error;
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final reminderService = todoReminderService;
      if (reminderService != null) unawaited(reminderService.resume(todos));
    }
  }

  Future<void> reload() async {
    _activeReloads++;
    try {
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
      achievements =
          await _achievementRepository?.getAchievements() ?? const [];
      loading = false;
      notifyListeners();
    } finally {
      _activeReloads--;
    }
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
    final operation = _todos?.saveTodo(todo);
    if (operation != null) await pendingWork.track(operation);
    if (!todo.reminderEnabled) await todoReminderService?.cancel(todo.id);
  }

  Future<void> completeTodo(
    String id,
    bool completed, {
    DateTime? nextDueAt,
  }) async {
    final source = findTodo(id) ?? findTodo(id, deleted: true);
    final operation = _todos?.setTodoCompleted(
      id,
      completed,
      nextDueAt: nextDueAt,
    );
    if (operation != null) await pendingWork.track(operation);
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
    final operation = _todos?.moveTodosToTrash(values);
    if (operation != null) await pendingWork.track(operation);
    for (final id in values) {
      await todoReminderService?.cancel(id);
    }
  }

  Future<void> restoreTodos(Iterable<String> ids) async {
    final operation = _todos?.restoreTodos(ids);
    if (operation != null) await pendingWork.track(operation);
  }

  Future<void> deleteTodosForever(Iterable<String> ids) async {
    final values = ids.toList();
    final operation = _todos?.permanentlyDeleteTodos(values);
    if (operation != null) await pendingWork.track(operation);
    for (final id in values) {
      await todoReminderService?.cancel(id);
    }
  }

  Future<void> save(Note note, {bool? isNew}) async {
    final shouldCountAsNew =
        isNew ??
        (findNote(note.id) == null && findNote(note.id, deleted: true) == null);
    await pendingWork.track(repository.saveNote(note));
    if (shouldCountAsNew) {
      await _registerAchievement(
        _achievementRepository?.recordNoteCreated(note.id),
      );
    }
  }

  Future<void> trash(Iterable<String> ids) =>
      pendingWork.track(repository.moveToTrash(ids));
  Future<void> restore(Iterable<String> ids) =>
      pendingWork.track(repository.restore(ids));

  Future<void> deleteForever(Iterable<String> ids) async {
    final paths = await pendingWork.track(repository.permanentlyDelete(ids));
    await pendingWork.track(attachmentStore.deleteFiles(paths));
  }

  Future<void> favorite(String id, bool value) =>
      pendingWork.track(repository.setFavorite(id, value));
  Future<void> addTag(String tag) => pendingWork.track(repository.addTag(tag));
  Future<void> deleteTag(String tag) =>
      pendingWork.track(repository.deleteTag(tag));

  Future<void> saveAiConfig(AiConfig config) async {
    final normalized = AiConfig(
      baseUrl: config.baseUrl.trim(),
      model: config.model.trim(),
      apiKey: config.apiKey.trim(),
    );
    await pendingWork.track(aiSettingsStore.save(normalized));
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
    WidgetsBinding.instance.removeObserver(this);
    unawaited(shutdown());
    super.dispose();
  }

  Future<void> shutdown() async {
    if (_closed) return;
    _closed = true;
    await _initializationOperation;
    await _subscription?.cancel();
    while (_activeReloads > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await pendingWork.flush();
    await todoReminderService?.dispose();
    await repository.close();
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
