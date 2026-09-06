import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/achievement.dart';
import '../models/note.dart';
import '../state/app_controller.dart';
import '../theme/desktop_environment.dart';
import '../services/moment_platform.dart';
import '../widgets/note_card.dart';
import 'note_editor_screen.dart';
import 'note_library_screens.dart';
import 'notes_home_screen.dart';
import 'todos_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell>
    with SingleTickerProviderStateMixin {
  static const _historyTodayChancePercent = 6;
  static const _pageTransitionDuration = Duration(milliseconds: 220);

  var _index = 0;
  late final AnimationController _pageController;
  bool _notesOffstage = false;
  bool _todosOffstage = true;
  bool _historyTodayChecked = false;
  bool _achievementDialogActive = false;

  @override
  void initState() {
    super.initState();
    _pageController = AnimationController(
      vsync: this,
      duration: _pageTransitionDuration,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

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

  void _createCurrentItem() {
    final page = _index == 0
        ? const NoteEditorScreen()
        : TodoEditorScreen(initialDate: DateUtils.dateOnly(DateTime.now()));
    Navigator.push<void>(context, MaterialPageRoute(builder: (_) => page));
  }

  void _openSearch() {
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const SearchNotesScreen()),
    );
  }

  void _handleEscape() {
    FocusManager.instance.primaryFocus?.unfocus();
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.maybePop();
  }

  Future<void> _selectPage(int index) async {
    if (index == _index) return;
    setState(() {
      _index = index;
      if (index == 0) {
        _notesOffstage = false;
      } else {
        _todosOffstage = false;
      }
    });
    await _pageController.animateTo(
      index.toDouble(),
      duration: _pageTransitionDuration,
      curve: Curves.easeInOut,
    );
    if (!mounted || _index != index) return;
    setState(() {
      _notesOffstage = index != 0;
      _todosOffstage = index != 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (MomentPlatform.isDesktop) {
      return const _DesktopHomeShell();
    }
    return DesktopEnvironment.mobile(
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              _createCurrentItem,
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _openSearch,
          const SingleActivator(LogicalKeyboardKey.digit1, control: true): () {
            _selectPage(0);
          },
          const SingleActivator(LogicalKeyboardKey.digit2, control: true): () {
            _selectPage(1);
          },
          const SingleActivator(LogicalKeyboardKey.escape): _handleEscape,
        },
        child: Scaffold(
          body: AnimatedBuilder(
            animation: _pageController,
            builder: (context, _) => Stack(
              fit: StackFit.expand,
              children: [
                _PageFade(
                  opacity: 1 - _pageController.value,
                  offstage: _notesOffstage,
                  interactive: _index == 0,
                  child: const NotesHomeScreen(),
                ),
                _PageFade(
                  opacity: _pageController.value,
                  offstage: _todosOffstage,
                  interactive: _index == 1,
                  child: const TodosScreen(),
                ),
              ],
            ),
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
                      onTap: () => _selectPage(0),
                    ),
                    _HomeDestination(
                      key: const ValueKey('home-tab-todos'),
                      icon: Icons.check_circle_outline_rounded,
                      selectedIcon: Icons.check_circle_rounded,
                      label: '待办',
                      selected: _index == 1,
                      onTap: () => _selectPage(1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopHomeShell extends StatefulWidget {
  const _DesktopHomeShell();

  @override
  State<_DesktopHomeShell> createState() => _DesktopHomeShellState();
}

class _DesktopHomeShellState extends State<_DesktopHomeShell> {
  final _notesNavigator = GlobalKey<NavigatorState>();
  final _todosNavigator = GlobalKey<NavigatorState>();
  DesktopModule _module = DesktopModule.notes;
  bool _settingsOpen = false;

  GlobalKey<NavigatorState> get _activeNavigator =>
      _module == DesktopModule.notes ? _notesNavigator : _todosNavigator;

  void _switchModule(DesktopModule module) {
    if (_module == module) return;
    if (_settingsOpen) _activeNavigator.currentState?.pop();
    setState(() {
      _settingsOpen = false;
      _module = module;
    });
  }

  void _openInWorkspace(Widget page) {
    _activeNavigator.currentState?.push<void>(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  void _createCurrent() {
    if (_module == DesktopModule.notes) {
      _openInWorkspace(const NoteEditorScreen());
      return;
    }
    final navigatorContext = _activeNavigator.currentContext;
    if (navigatorContext == null) return;
    showDialog<void>(
      context: navigatorContext,
      builder: (_) => TodoEditorScreen(
        initialDate: DateUtils.dateOnly(DateTime.now()),
        desktopDialog: true,
      ),
    );
  }

  void _openSearch() {
    _switchModule(DesktopModule.notes);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notesNavigator.currentState?.push<void>(
        MaterialPageRoute(builder: (_) => const SearchNotesScreen()),
      );
    });
  }

  Future<void> _openSettings() async {
    if (_settingsOpen) return;
    setState(() => _settingsOpen = true);
    await _activeNavigator.currentState?.push<void>(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (mounted) setState(() => _settingsOpen = false);
  }

  void _escape() {
    FocusManager.instance.primaryFocus?.unfocus();
    _activeNavigator.currentState?.maybePop();
  }

  @override
  Widget build(BuildContext context) => DesktopEnvironment(
    isDesktop: true,
    module: _module,
    switchModule: _switchModule,
    openInWorkspace: _openInWorkspace,
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _createCurrent,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openSearch,
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
            _switchModule(DesktopModule.notes),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
            _switchModule(DesktopModule.todos),
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Row(
          children: [
            SizedBox(
              width: 88,
              child: _DesktopNavigation(
                module: _module,
                settingsSelected: _settingsOpen,
                onChanged: _switchModule,
                onSettings: _openSettings,
              ),
            ),
            const VerticalDivider(),
            Expanded(
              child: IndexedStack(
                index: _module.index,
                children: [
                  Navigator(
                    key: _notesNavigator,
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) => const NotesHomeScreen(desktop: true),
                    ),
                  ),
                  Navigator(
                    key: _todosNavigator,
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) => const TodosScreen(desktop: true),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    required this.module,
    required this.settingsSelected,
    required this.onChanged,
    required this.onSettings,
  });

  final DesktopModule module;
  final bool settingsSelected;
  final ValueChanged<DesktopModule> onChanged;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surfaceContainerLow,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.auto_stories_rounded,
                  color: colors.onPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Moment',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 28),
              _DesktopNavItem(
                key: const ValueKey('desktop-nav-notes'),
                icon: Icons.note_alt_outlined,
                selectedIcon: Icons.note_alt_rounded,
                label: '笔记',
                selected: module == DesktopModule.notes,
                onTap: () => onChanged(DesktopModule.notes),
              ),
              const SizedBox(height: 6),
              _DesktopNavItem(
                key: const ValueKey('desktop-nav-todos'),
                icon: Icons.check_circle_outline_rounded,
                selectedIcon: Icons.check_circle_rounded,
                label: '待办',
                selected: module == DesktopModule.todos,
                onTap: () => onChanged(DesktopModule.todos),
              ),
              const Spacer(),
              _DesktopNavItem(
                key: const ValueKey('desktop-nav-settings'),
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings_rounded,
                label: '设置',
                selected: settingsSelected,
                onTap: onSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopNavItem extends StatelessWidget {
  const _DesktopNavItem({
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
    return Semantics(
      button: true,
      selected: selected,
      child: Tooltip(
        message: label,
        child: Material(
          color: selected
              ? colors.primaryContainer.withValues(alpha: .7)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(7),
            focusColor: colors.primaryContainer,
            child: SizedBox(
              height: 58,
              child: Stack(
                children: [
                  if (selected)
                    Positioned(
                      left: 0,
                      top: 15,
                      bottom: 15,
                      child: Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          selected ? selectedIcon : icon,
                          size: 21,
                          color: selected
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          label,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: selected
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
  const _PageFade({
    required this.opacity,
    required this.offstage,
    required this.interactive,
    required this.child,
  });

  final double opacity;
  final bool offstage;
  final bool interactive;
  final Widget child;

  @override
  Widget build(BuildContext context) => Offstage(
    offstage: offstage,
    child: TickerMode(
      enabled: interactive,
      child: IgnorePointer(
        ignoring: !interactive,
        child: Opacity(opacity: opacity.clamp(0, 1), child: child),
      ),
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
