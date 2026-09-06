import 'dart:math';

import 'package:flutter/material.dart';

import '../models/achievement.dart';
import '../models/note.dart';
import '../state/app_controller.dart';
import '../widgets/note_card.dart';
import 'note_editor_screen.dart';
import 'notes_home_screen.dart';
import 'todos_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _historyTodayChancePercent = 6;

  var _index = 0;
  bool _historyTodayChecked = false;
  bool _achievementDialogActive = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    _scheduleAchievementDialog(app);
    if (_historyTodayChecked || app.loading) return;
    _historyTodayChecked = true;

    final now = DateTime.now();
    final memories = app.notes.where((note) {
      final created = note.createdAt;
      return created.year < now.year &&
          created.month == now.month &&
          created.day == now.day;
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (memories.isEmpty ||
        Random.secure().nextInt(100) >= _historyTodayChancePercent) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showHistoryToday(memories, now);
    });
  }

  void _scheduleAchievementDialog(AppController app) {
    if (_achievementDialogActive) return;
    final achievement = app.takePendingAchievement();
    if (achievement == null) return;
    _achievementDialogActive = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            _AchievementUnlockedDialog(achievement: achievement),
      );
      _achievementDialogActive = false;
      if (mounted) _scheduleAchievementDialog(AppScope.read(context));
    });
  }

  Future<void> _showHistoryToday(List<Note> notes, DateTime now) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _HistoryTodayDialog(notes: notes, today: now),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      fit: StackFit.expand,
      children: [
        _PageFade(visible: _index == 0, child: const NotesHomeScreen()),
        _PageFade(visible: _index == 1, child: const TodosScreen()),
      ],
    ),
    bottomNavigationBar: Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70,
          child: Row(
            children: [
              _HomeDestination(
                key: const ValueKey('home-tab-notes'),
                icon: Icons.note_alt_outlined,
                selectedIcon: Icons.note_alt_rounded,
                label: '笔记',
                selected: _index == 0,
                onTap: () => setState(() => _index = 0),
              ),
              _HomeDestination(
                key: const ValueKey('home-tab-todos'),
                icon: Icons.check_circle_outline_rounded,
                selectedIcon: Icons.check_circle_rounded,
                label: '待办',
                selected: _index == 1,
                onTap: () => setState(() => _index = 1),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AchievementUnlockedDialog extends StatelessWidget {
  const _AchievementUnlockedDialog({required this.achievement});

  final Achievement achievement;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          achievement.kind == AchievementKind.notesCreated
              ? Icons.auto_stories_rounded
              : Icons.emoji_events_rounded,
          size: 38,
          color: colors.primary,
        ),
      ),
      title: const Text('成就达成'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            achievement.title,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            achievement.description,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '每一步记录，都值得被纪念。',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: colors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.celebration_rounded),
          label: const Text('收下成就'),
        ),
      ],
    );
  }
}

class _HistoryTodayDialog extends StatelessWidget {
  const _HistoryTodayDialog({required this.notes, required this.today});

  final List<Note> notes;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final maxContentHeight = min(
      MediaQuery.sizeOf(context).height * .45,
      380.0,
    );
    return AlertDialog(
      icon: Icon(
        Icons.auto_stories_rounded,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: const Text('历史的今天'),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxContentHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '往年的今天，你曾留下 ${notes.length} 段记录。时间向前走着，那些当时的想法仍在这里等你。',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: notes.length,
                  itemBuilder: (context, index) {
                    final note = notes[index];
                    final yearsAgo = today.year - note.createdAt.year;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                          child: Text(
                            '${note.createdAt.year} 年 · $yearsAgo 年前',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        NoteCard(
                          note: note,
                          onTap: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => NoteEditorScreen(
                                noteId: note.id,
                                readOnly: true,
                                historyPreview: true,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _PageFade extends StatelessWidget {
  const _PageFade({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      child: child,
    ),
  );
}

class _HomeDestination extends StatelessWidget {
  const _HomeDestination({
    super.key,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Transform.translate(
            offset: const Offset(0, 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 32,
                  decoration: BoxDecoration(
                    color: selected
                        ? colors.secondaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    selected ? selectedIcon : icon,
                    size: 24,
                    color: selected
                        ? colors.onSecondaryContainer
                        : colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    height: 1,
                    color: selected
                        ? colors.onSurface
                        : colors.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
