import 'package:flutter/material.dart';

import '../models/note.dart';
import '../state/app_controller.dart';
import '../widgets/note_card.dart';
import 'note_editor_screen.dart';
import 'note_library_screens.dart';

enum _SortMode { updated, created }

class NotesHomeScreen extends StatefulWidget {
  const NotesHomeScreen({super.key, this.desktop = false});

  final bool desktop;

  @override
  State<NotesHomeScreen> createState() => _NotesHomeScreenState();
}

class _NotesHomeScreenState extends State<NotesHomeScreen> {
  final Set<String> _selectedIds = {};
  final Set<String> _selectedTags = {};
  _SortMode _sortMode = _SortMode.updated;
  bool _selectionMode = false;
  String? _wideNoteId;
  String? _wideActiveNoteId;

  List<Note> _visibleNotes(AppController app) {
    final result = app.notes.where((note) {
      return _selectedTags.isEmpty || note.tags.any(_selectedTags.contains);
    }).toList();
    result.sort(
      (a, b) => _sortMode == _SortMode.updated
          ? b.updatedAt.compareTo(a.updatedAt)
          : b.createdAt.compareTo(a.createdAt),
    );
    return result;
  }

  void _openNote(String? id, bool wide) {
    if (_selectionMode && id != null) {
      setState(() {
        _selectedIds.contains(id)
            ? _selectedIds.remove(id)
            : _selectedIds.add(id);
      });
      return;
    }
    if (wide) {
      setState(() {
        _wideNoteId = id ?? 'new:${newId()}';
        _wideActiveNoteId = id;
      });
    } else {
      Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: id)),
      );
    }
  }

  void _enterSelection(String id) => setState(() {
    _selectionMode = true;
    _selectedIds.add(id);
  });

  void _leaveSelection() => setState(() {
    _selectionMode = false;
    _selectedIds.clear();
  });

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除所选笔记？'),
        content: Text('将 ${_selectedIds.length} 条笔记移入回收站。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await AppScope.of(context).trash(_selectedIds);
      _leaveSelection();
    }
  }

  Future<void> _openDestination(String destination) async {
    final page = switch (destination) {
      'favorites' => const FavoritesScreen(),
      'tags' => const TagsScreen(),
      'trash' => const TrashScreen(),
      _ => const SettingsScreen(),
    };
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final notes = _visibleNotes(app);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = widget.desktop || constraints.maxWidth >= 840;
        final editorSessionId = _wideNoteId;
        final list = _buildList(app, notes, wide);
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: widget.desktop ? 56 : 78,
            automaticallyImplyLeading: false,
            leading: _selectionMode
                ? IconButton(
                    onPressed: _leaveSelection,
                    icon: const Icon(Icons.close),
                  )
                : null,
            title: _selectionMode
                ? Text('已选 ${_selectedIds.length} 项')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.desktop ? '笔记' : 'Moment'),
                      const SizedBox(height: 2),
                      Text(
                        notes.isEmpty ? '记录此刻的想法' : '${notes.length} 条笔记',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
            actions: _selectionMode
                ? [
                    TextButton(
                      onPressed: () => setState(() {
                        _selectedIds
                          ..clear()
                          ..addAll(notes.map((note) => note.id));
                      }),
                      child: const Text('全选'),
                    ),
                    if (widget.desktop)
                      IconButton(
                        tooltip: '删除所选笔记',
                        onPressed: _selectedIds.isEmpty
                            ? null
                            : _deleteSelected,
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                  ]
                : [
                    IconButton.filledTonal(
                      tooltip: '搜索',
                      onPressed: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SearchNotesScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.search_rounded, size: 21),
                    ),
                    const SizedBox(width: 4),
                    IconButton.filledTonal(
                      tooltip: '收藏夹',
                      onPressed: () => _openDestination('favorites'),
                      icon: const Icon(Icons.star_outline_rounded, size: 21),
                    ),
                    const SizedBox(width: 4),
                    _ModernHomeMenu(
                      sortMode: _sortMode,
                      onSortChanged: (mode) {
                        setState(() => _sortMode = mode);
                      },
                      onNavigate: _openDestination,
                    ),
                    if (widget.desktop) ...[
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => _openNote(null, true),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('新建笔记'),
                      ),
                    ],
                    const SizedBox(width: 10),
                  ],
          ),
          body: wide
              ? Row(
                  children: [
                    SizedBox(
                      width: widget.desktop
                          ? (constraints.maxWidth < 1040 ? 310 : 360)
                          : 400,
                      child: ColoredBox(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerLowest,
                        child: list,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: editorSessionId == null
                          ? const _WidePlaceholder()
                          : NoteEditorScreen(
                              key: ValueKey(editorSessionId),
                              noteId: editorSessionId.startsWith('new:')
                                  ? null
                                  : editorSessionId,
                              embedded: true,
                              onSaved: (savedNoteId) {
                                if (!mounted ||
                                    _wideNoteId != editorSessionId ||
                                    _wideActiveNoteId == savedNoteId) {
                                  return;
                                }
                                setState(() => _wideActiveNoteId = savedNoteId);
                              },
                            ),
                    ),
                  ],
                )
              : list,
          floatingActionButton: widget.desktop
              ? null
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  reverseDuration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: .82,
                        end: 1,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: _selectionMode
                      ? FloatingActionButton(
                          key: const ValueKey('delete-selected-notes'),
                          heroTag: 'notes-delete-action',
                          onPressed: _selectedIds.isEmpty
                              ? null
                              : _deleteSelected,
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor: Theme.of(context)
                              .colorScheme
                              .onError,
                          child: const Icon(Icons.delete_outline),
                        )
                      : FloatingActionButton(
                          key: const ValueKey('create-note'),
                          heroTag: 'notes-create-action',
                          onPressed: () => _openNote(null, wide),
                          tooltip: '新建笔记',
                          child: const Icon(Icons.edit_rounded),
                        ),
                ),
        );
      },
    );
  }

  Widget _buildList(AppController app, List<Note> notes, bool wide) {
    final Widget content;
    if (app.loading) {
      content = const Center(
        key: ValueKey('loading-notes'),
        child: CircularProgressIndicator(),
      );
    } else if (notes.isEmpty) {
      content = _EmptyNotes(
        key: ValueKey('empty-notes:${_selectedTags.isNotEmpty}'),
        filtered: _selectedTags.isNotEmpty,
      );
    } else {
      content = RefreshIndicator(
        key: ValueKey('notes:${notes.map((note) => note.id).join(',')}'),
        onRefresh: app.reload,
        child: ListView.builder(
          primary: false,
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
          itemCount: notes.length,
          itemBuilder: (context, index) {
            final note = notes[index];
            return NoteCard(
              note: note,
              compact: widget.desktop,
              selected: _selectedIds.contains(note.id),
              active:
                  widget.desktop &&
                  !_selectionMode &&
                  _wideActiveNoteId == note.id,
              onTap: () => _openNote(note.id, wide),
              onLongPress: () => _enterSelection(note.id),
            );
          },
        ),
      );
    }

    return Column(
      children: [
        if (app.tags.isNotEmpty)
          _FrequentTagBar(
            tags: app.tags,
            selected: _selectedTags,
            onClear: () => setState(_selectedTags.clear),
            onChanged: (tags) => setState(() {
              _selectedTags
                ..clear()
                ..addAll(tags);
            }),
          ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            reverseDuration: const Duration(milliseconds: 190),
            layoutBuilder: (currentChild, previousChildren) => Stack(
              fit: StackFit.expand,
              children: [...previousChildren, ?currentChild],
            ),
            transitionBuilder: (child, animation) {
              final eased = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return FadeTransition(
                opacity: eased,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, .018),
                    end: Offset.zero,
                  ).animate(eased),
                  child: child,
                ),
              );
            },
            child: content,
          ),
        ),
      ],
    );
  }
}

class _FrequentTagBar extends StatelessWidget {
  const _FrequentTagBar({
    required this.tags,
    required this.selected,
    required this.onClear,
    required this.onChanged,
  });

  final List<String> tags;
  final Set<String> selected;
  final VoidCallback onClear;
  final ValueChanged<Set<String>> onChanged;

  Future<void> _openFilter(BuildContext context) async {
    final draft = <String>{...selected};
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final colors = Theme.of(context).colorScheme;
          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            titlePadding: const EdgeInsets.fromLTRB(22, 20, 18, 8),
            contentPadding: const EdgeInsets.fromLTRB(22, 10, 22, 8),
            actionsPadding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.filter_alt_rounded,
                    size: 21,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('筛选标签')),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '选择一个或多个标签，显示包含任意已选标签的笔记。',
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final tag in tags)
                            FilterChip(
                              label: Text(
                                tag,
                                style: TextStyle(
                                  color: draft.contains(tag)
                                      ? colors.onPrimary
                                      : colors.onSurfaceVariant,
                                  fontWeight: draft.contains(tag)
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                              selected: draft.contains(tag),
                              showCheckmark: false,
                              backgroundColor: colors.surfaceContainerLow,
                              selectedColor: colors.primary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onSelected: (_) => setDialogState(() {
                                draft.contains(tag)
                                    ? draft.remove(tag)
                                    : draft.add(tag);
                              }),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: draft.isEmpty
                    ? null
                    : () => setDialogState(draft.clear),
                child: const Text('清空'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, {...draft}),
                child: const Text('应用'),
              ),
            ],
          );
        },
      ),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    Widget filterButton({
      required String label,
      required bool active,
      required VoidCallback onTap,
      IconData? icon,
    }) => Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 230),
        curve: Curves.easeOutCubic,
        height: 40,
        decoration: BoxDecoration(
          color: active ? colors.secondaryContainer : colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? colors.primary.withValues(alpha: .14)
                : Colors.transparent,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 18,
                      color: active ? colors.primary : colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 7),
                  ],
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 210),
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      height: 1,
                      color: active
                          ? colors.onSecondaryContainer
                          : colors.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    child: Text(label),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return SizedBox(
      height: 54,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 7, 12, 7),
        child: Row(
          children: [
            filterButton(label: '全部', active: selected.isEmpty, onTap: onClear),
            const SizedBox(width: 8),
            Badge.count(
              count: selected.length,
              isLabelVisible: selected.isNotEmpty,
              child: Tooltip(
                message: selected.isEmpty
                    ? '筛选标签'
                    : '筛选标签（已选 ${selected.length} 个）',
                child: filterButton(
                  label: '筛选',
                  active: selected.isNotEmpty,
                  icon: Icons.filter_alt_outlined,
                  onTap: () => _openFilter(context),
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _ModernHomeMenu extends StatelessWidget {
  const _ModernHomeMenu({
    required this.sortMode,
    required this.onSortChanged,
    required this.onNavigate,
  });

  final _SortMode sortMode;
  final ValueChanged<_SortMode> onSortChanged;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MenuAnchor(
      // Align the menu's right edge with the trigger and place it below the
      // app-bar button instead of letting the wider panel drift to the center.
      alignmentOffset: const Offset(-192, 52),
      style: MenuStyle(
        alignment: AlignmentDirectional.topEnd,
        backgroundColor: WidgetStatePropertyAll(colors.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(10),
        shadowColor: WidgetStatePropertyAll(
          colors.shadow.withValues(alpha: .18),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(9)),
        minimumSize: const WidgetStatePropertyAll(Size(192, 0)),
        maximumSize: const WidgetStatePropertyAll(Size(192, double.infinity)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      menuChildren: [
        SizedBox(
          key: const Key('home-menu-panel'),
          width: 174,
          child: const _MenuSectionLabel('笔记排序'),
        ),
        _ModernMenuItem(
          icon: Icons.update_rounded,
          label: '最近修改',
          selected: sortMode == _SortMode.updated,
          onPressed: () => onSortChanged(_SortMode.updated),
        ),
        _ModernMenuItem(
          icon: Icons.calendar_today_outlined,
          label: '创建时间',
          selected: sortMode == _SortMode.created,
          onPressed: () => onSortChanged(_SortMode.created),
        ),
        const Divider(height: 12),
        const _MenuSectionLabel('更多功能'),
        _ModernMenuItem(
          icon: Icons.label_outline_rounded,
          label: '标签管理',
          onPressed: () => onNavigate('tags'),
        ),
        _ModernMenuItem(
          icon: Icons.delete_outline_rounded,
          label: '回收站',
          onPressed: () => onNavigate('trash'),
        ),
        _ModernMenuItem(
          icon: Icons.settings_outlined,
          label: '设置',
          onPressed: () => onNavigate('settings'),
        ),
      ],
      builder: (context, controller, child) => IconButton.filledTonal(
        tooltip: '管理与设置',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.tune_rounded, size: 21),
      ),
    );
  }
}

class _ModernMenuItem extends StatelessWidget {
  const _ModernMenuItem({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => MenuItemButton(
    onPressed: onPressed,
    leadingIcon: Icon(icon, size: 20),
    trailingIcon: selected ? const Icon(Icons.check_rounded, size: 19) : null,
    style: ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(40)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10),
      ),
      backgroundColor: WidgetStatePropertyAll(
        selected
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
    ),
  );
}

class _MenuSectionLabel extends StatelessWidget {
  const _MenuSectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes({super.key, required this.filtered});
  final bool filtered;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Icon(
            Icons.edit_note_rounded,
            size: 40,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          filtered ? '该标签下没有笔记' : '开始记录你的想法',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          filtered ? '试试其他标签组合' : '点击右下角按钮，写下第一条记录',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    ),
  );
}

class _WidePlaceholder extends StatelessWidget {
  const _WidePlaceholder();
  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.edit_note, size: 72),
        SizedBox(height: 12),
        Text('选择一篇笔记开始编辑'),
      ],
    ),
  );
}
