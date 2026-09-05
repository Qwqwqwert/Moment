import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moment/data/note_repository.dart';
import 'package:moment/data/todo_repository.dart';
import 'package:moment/main.dart';
import 'package:moment/models/note.dart';
import 'package:moment/models/todo.dart';

void main() {
  testWidgets('starts with the notes empty state', (tester) async {
    final repository = FakeNoteRepository();
    await tester.pumpWidget(MomentApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('Moment'), findsOneWidget);
    expect(find.text('开始记录你的想法'), findsOneWidget);
    expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
  });

  testWidgets('opens a new note editor', (tester) async {
    final repository = FakeNoteRepository();
    await tester.pumpWidget(MomentApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pumpAndSettle();

    expect(find.text('新笔记'), findsOneWidget);
    expect(find.text('无标题笔记'), findsOneWidget);
    expect(find.text('清单'), findsOneWidget);

    final toolbarBottomBefore = tester.getBottomLeft(find.text('清单')).dy;
    tester.view.viewInsets = FakeViewPadding(
      bottom: 200 * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.reset);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final toolbarBottomAfter = tester.getBottomLeft(find.text('清单')).dy;
    expect(toolbarBottomAfter, lessThan(toolbarBottomBefore - 150));
  });

  testWidgets('creates a todo from the Flutter todo flow', (tester) async {
    final repository = FakeNoteRepository();
    await tester.pumpWidget(MomentApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-tab-todos')));
    await tester.pumpAndSettle();
    expect(find.text('暂无待办'), findsOneWidget);

    await tester.tap(find.byTooltip('新建待办'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '要完成什么？'), '购买牛奶');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('购买牛奶'), findsOneWidget);
  });

  testWidgets('switches between Markdown source and preview', (tester) async {
    final repository = FakeNoteRepository();
    await tester.pumpWidget(MomentApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pumpAndSettle();

    const source = '# 一级标题\n\n**粗体内容**\n\n- 列表项';
    await tester.enterText(
      find.byKey(const Key('markdown-source-editor')),
      source,
    );
    await tester.tap(find.byTooltip('预览 Markdown'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('markdown-source-editor')), findsNothing);
    expect(find.byKey(const Key('markdown-preview')), findsOneWidget);
    expect(find.byKey(const Key('markdown-selection-area')), findsOneWidget);
    expect(find.text('清单'), findsNothing);

    await tester.tap(find.byTooltip('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('markdown-source-editor')), findsOneWidget);
    expect(find.byKey(const Key('markdown-preview')), findsNothing);
  });

  testWidgets('opens the redesigned home dropdown menu', (tester) async {
    await tester.binding.setSurfaceSize(const Size(411, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeNoteRepository();
    await tester.pumpWidget(MomentApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.menu), findsNothing);
    final trigger = find.byTooltip('管理与设置');
    final triggerRect = tester.getRect(trigger);
    expect(find.byTooltip('收藏夹'), findsOneWidget);
    await tester.tap(trigger);
    await tester.pumpAndSettle();

    final menuRect = tester.getRect(find.byKey(const Key('home-menu-panel')));
    expect(menuRect.center.dx, greaterThan(411 * .55));
    expect((menuRect.right - triggerRect.right).abs(), lessThan(24));

    expect(find.text('整理与管理'), findsNothing);
    expect(find.text('最近修改'), findsOneWidget);
    expect(find.text('收藏夹'), findsNothing);
    expect(find.text('标签管理'), findsOneWidget);
    expect(find.text('回收站'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('selects multiple tags from the filter dialog', (tester) async {
    await tester.binding.setSurfaceSize(const Size(411, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeNoteRepository();
    await tester.pumpWidget(MomentApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('全部'), findsOneWidget);
    expect(find.text('筛选'), findsOneWidget);
    expect(find.text('工作'), findsNothing);
    expect(find.text('重要'), findsNothing);

    await tester.tap(find.byTooltip('筛选标签'));
    await tester.pumpAndSettle();

    expect(find.text('筛选标签'), findsOneWidget);
    expect(find.text('工作'), findsOneWidget);
    expect(find.text('重要'), findsOneWidget);
    expect(find.text('随笔'), findsOneWidget);
    await tester.tap(find.text('重要'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('随笔'));
    await tester.pumpAndSettle();

    final importantChip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, '重要'),
    );
    final casualChip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, '随笔'),
    );
    expect(importantChip.selected, isTrue);
    expect(casualChip.selected, isTrue);

    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('筛选标签（已选 2 个）'), findsOneWidget);
  });

  testWidgets('shows the redesigned tag management screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(411, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeNoteRepository();
    await tester.pumpWidget(MomentApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('管理与设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('标签管理'));
    await tester.pumpAndSettle();

    expect(find.text('创建新标签'), findsOneWidget);
    expect(find.text('输入标签名称'), findsOneWidget);
    expect(find.text('0/20'), findsOneWidget);
    expect(find.text('全部标签'), findsOneWidget);
    expect(find.text('5 个'), findsOneWidget);
    expect(find.text('暂未使用'), findsNWidgets(5));

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.testTextInput.hasAnyClients, isTrue);
    await tester.tap(find.text('全部标签'));
    await tester.pump();
    expect(tester.testTextInput.hasAnyClients, isFalse);

    await tester.enterText(find.byType(TextField), '123456789012345678901');
    await tester.pump();
    final tagField = tester.widget<TextField>(find.byType(TextField));
    expect(tagField.controller!.text, '12345678901234567890');
    expect(find.text('20/20'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '工作');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('标签已存在'), findsOneWidget);

    await tester.tap(find.text('创建新标签'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('标签已存在'), findsNothing);
  });
}

class FakeNoteRepository implements NoteRepository, TodoRepository {
  final _changes = StreamController<void>.broadcast();
  final _notes = <Note>[];
  final _tags = <String>['工作', '学习', '生活', '重要', '随笔'];
  final _todos = <Todo>[];

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<Note>> getNotes({
    bool deleted = false,
    bool favorites = false,
  }) async => _notes
      .where(
        (note) => note.isDeleted == deleted && (!favorites || note.isFavorite),
      )
      .toList();

  @override
  Future<Note?> getNote(String id, {bool includeDeleted = false}) async {
    for (final note in _notes) {
      if (note.id == id && (includeDeleted || !note.isDeleted)) return note;
    }
    return null;
  }

  @override
  Future<void> saveNote(Note note) async {
    _notes.removeWhere((item) => item.id == note.id);
    _notes.add(note);
    _changes.add(null);
  }

  @override
  Future<void> moveToTrash(Iterable<String> ids) async {
    final selected = ids.toSet();
    for (var i = 0; i < _notes.length; i++) {
      if (selected.contains(_notes[i].id)) {
        _notes[i] = _notes[i].copyWith(deletedAt: DateTime.now());
      }
    }
    _changes.add(null);
  }

  @override
  Future<void> restore(Iterable<String> ids) async {
    final selected = ids.toSet();
    for (var i = 0; i < _notes.length; i++) {
      if (selected.contains(_notes[i].id)) {
        _notes[i] = _notes[i].copyWith(clearDeletedAt: true);
      }
    }
    _changes.add(null);
  }

  @override
  Future<List<String>> permanentlyDelete(Iterable<String> ids) async {
    final selected = ids.toSet();
    final paths = _notes
        .where((note) => selected.contains(note.id))
        .expand((note) => note.imagePaths)
        .toList();
    _notes.removeWhere((note) => selected.contains(note.id));
    _changes.add(null);
    return paths;
  }

  @override
  Future<void> setFavorite(String id, bool value) async {
    final index = _notes.indexWhere((note) => note.id == id);
    if (index >= 0) _notes[index] = _notes[index].copyWith(isFavorite: value);
    _changes.add(null);
  }

  @override
  Future<List<String>> getTags() async => [..._tags];

  @override
  Future<void> addTag(String tag) async {
    if (!_tags.contains(tag)) _tags.add(tag);
    _changes.add(null);
  }

  @override
  Future<void> deleteTag(String tag) async {
    _tags.remove(tag);
    _changes.add(null);
  }

  @override
  Future<List<Todo>> getTodos({bool deleted = false, bool? completed}) async =>
      _todos
          .where(
            (todo) =>
                todo.isDeleted == deleted &&
                (completed == null || todo.isCompleted == completed),
          )
          .toList();

  @override
  Future<Todo?> getTodo(String id, {bool includeDeleted = false}) async {
    for (final todo in _todos) {
      if (todo.id == id && (includeDeleted || !todo.isDeleted)) return todo;
    }
    return null;
  }

  @override
  Future<void> saveTodo(Todo todo) async {
    _todos.removeWhere((item) => item.id == todo.id);
    _todos.add(todo);
    _changes.add(null);
  }

  @override
  Future<void> setTodoCompleted(
    String id,
    bool completed, {
    DateTime? nextDueAt,
  }) async {
    final index = _todos.indexWhere((todo) => todo.id == id);
    if (index >= 0) {
      final todo = _todos[index];
      _todos[index] = todo.copyWith(isCompleted: completed);
      if (completed) {
        final next = todo.nextOccurrence(dueAtOverride: nextDueAt);
        if (next != null) _todos.add(next);
      }
    }
    _changes.add(null);
  }

  @override
  Future<void> moveTodosToTrash(Iterable<String> ids) async {
    final selected = ids.toSet();
    for (var index = 0; index < _todos.length; index++) {
      if (selected.contains(_todos[index].id)) {
        _todos[index] = _todos[index].copyWith(deletedAt: DateTime.now());
      }
    }
    _changes.add(null);
  }

  @override
  Future<void> restoreTodos(Iterable<String> ids) async {
    final selected = ids.toSet();
    for (var index = 0; index < _todos.length; index++) {
      if (selected.contains(_todos[index].id)) {
        _todos[index] = _todos[index].copyWith(clearDeletedAt: true);
      }
    }
    _changes.add(null);
  }

  @override
  Future<void> permanentlyDeleteTodos(Iterable<String> ids) async {
    final selected = ids.toSet();
    _todos.removeWhere((todo) => selected.contains(todo.id));
    _changes.add(null);
  }

  @override
  Future<void> close() => _changes.close();
}
