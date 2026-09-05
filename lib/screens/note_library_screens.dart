import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/note.dart';
import '../state/app_controller.dart';
import '../utils/tag_name.dart';
import '../widgets/note_card.dart';
import 'note_editor_screen.dart';

class SearchNotesScreen extends StatefulWidget {
  const SearchNotesScreen({super.key});
  @override
  State<SearchNotesScreen> createState() => _SearchNotesScreenState();
}

class _SearchNotesScreenState extends State<SearchNotesScreen> {
  final _query = TextEditingController();
  final _focusNode = FocusNode();
  DateTime? _start;
  DateTime? _end;

  @override
  void dispose() {
    _query.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  List<Note> _results(List<Note> notes) {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return notes.where((note) {
      final haystack = [
        note.title,
        note.content,
        ...note.checklist.map((item) => item.text),
      ].join('\n').toLowerCase();
      final date = DateTime(
        note.updatedAt.year,
        note.updatedAt.month,
        note.updatedAt.day,
      );
      return haystack.contains(query) &&
          (_start == null || !date.isBefore(_start!)) &&
          (_end == null || !date.isAfter(_end!));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final results = _results(AppScope.of(context).notes);
    return Scaffold(
      appBar: AppBar(title: const Text('搜索笔记')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchBar(
              controller: _query,
              focusNode: _focusNode,
              hintText: '请输入关键词',
              leading: const Icon(Icons.search),
              onChanged: (_) => setState(() {}),
              trailing: [
                IconButton(
                  onPressed: _showDateFilter,
                  icon: const Icon(Icons.tune),
                ),
              ],
            ),
          ),
          if (_start != null || _end != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.date_range, size: 18),
                  const SizedBox(width: 8),
                  Text('${_format(_start)} — ${_format(_end)}'),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _start = null;
                      _end = null;
                    }),
                    child: const Text('清除'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _query.text.trim().isEmpty
                ? const Center(child: Text('输入关键词搜索笔记'))
                : results.isEmpty
                ? const Center(child: Text('未找到匹配的笔记'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: results.length,
                    itemBuilder: (context, index) => NoteCard(
                      note: results[index],
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              NoteEditorScreen(noteId: results[index].id),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDateFilter() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _start == null || _end == null
          ? null
          : DateTimeRange(start: _start!, end: _end!),
    );
    if (range != null) {
      setState(() {
        _start = range.start;
        _end = range.end;
      });
    }
  }

  String _format(DateTime? date) =>
      date == null ? '不限' : '${date.year}-${date.month}-${date.day}';
}

class TagsScreen extends StatefulWidget {
  const TagsScreen({super.key});
  @override
  State<TagsScreen> createState() => _TagsScreenState();
}

class _TagsScreenState extends State<TagsScreen> {
  final _tagLengthLimiter = LengthLimitingTextInputFormatter(
    maxTagNameLength,
  );
  final _tag = TextEditingController();
  @override
  void dispose() {
    _tag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
      child: Scaffold(
        appBar: AppBar(toolbarHeight: 72, title: const Text('标签管理')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Text(
              '创建新标签',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '使用标签整理笔记，让内容更容易查找。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: .06),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tag,
                      maxLength: maxTagNameLength,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      inputFormatters: [_tagLengthLimiter],
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _add(),
                      decoration: InputDecoration(
                        hintText: '输入标签名称',
                        prefixIcon: const Icon(Icons.label_outline_rounded),
                        fillColor: colors.surfaceContainerLow,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: _tag.text.trim().isEmpty ? null : _add,
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text('添加'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Text(
                  '全部标签',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${app.tags.length} 个',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (app.tags.isEmpty)
              _EmptyTags(colors: colors)
            else
              ...app.tags.map((tag) {
                final usage = [
                  ...app.notes,
                  ...app.trashedNotes,
                ].where((note) => note.tags.contains(tag)).length;
                return _TagManagementCard(
                  tag: tag,
                  usage: usage,
                  onDelete: () => _delete(tag),
                );
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _add() async {
    final value = normalizeTagName(_tag.text);
    if (value.isEmpty) return;
    final app = AppScope.of(context);
    final validationMessage = validateNewTagName(value, app.tags);
    if (validationMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validationMessage)));
      return;
    }
    await app.addTag(value);
    _tag.clear();
    if (mounted) setState(() {});
  }

  Future<void> _delete(String tag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded),
        title: const Text('删除标签？'),
        content: Text('“$tag”将从所有笔记（包括回收站）中移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await AppScope.of(context).deleteTag(tag);
  }
}

class _TagManagementCard extends StatelessWidget {
  const _TagManagementCard({
    required this.tag,
    required this.usage,
    required this.onDelete,
  });

  final String tag;
  final int usage;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: .045),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.label_outline_rounded,
              color: colors.onSecondaryContainer,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tag,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  usage == 0 ? '暂未使用' : '$usage 条笔记正在使用',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: '删除 $tag',
            onPressed: onDelete,
            style: IconButton.styleFrom(
              backgroundColor: colors.errorContainer.withValues(alpha: .72),
              foregroundColor: colors.onErrorContainer,
            ),
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _EmptyTags extends StatelessWidget {
  const _EmptyTags({required this.colors});
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 38),
    decoration: BoxDecoration(
      color: colors.surface,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Center(
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.label_off_outlined,
              color: colors.onSecondaryContainer,
              size: 30,
            ),
          ),
          const SizedBox(height: 14),
          Text('还没有标签', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '在上方创建第一个标签',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    ),
  );
}

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final notes = AppScope.of(context).notes
        .where((note) => note.isFavorite)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('收藏夹')),
      body: notes.isEmpty
          ? const Center(child: Text('收藏夹暂无笔记'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: notes.length,
              itemBuilder: (context, index) => NoteCard(
                note: notes[index],
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NoteEditorScreen(noteId: notes[index].id),
                  ),
                ),
                onLongPress: () => _remove(context, notes[index]),
              ),
            ),
    );
  }

  Future<void> _remove(BuildContext context, Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消收藏？'),
        content: Text('确定将“${note.title}”移出收藏夹吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await AppScope.of(context).favorite(note.id, false);
    }
  }
}

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});
  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  final Set<String> _selected = {};
  bool get selecting => _selected.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final notes = AppScope.of(context).trashedNotes;
    return Scaffold(
      appBar: AppBar(
        title: Text(selecting ? '已选 ${_selected.length} 项' : '回收站'),
        leading: selecting
            ? IconButton(
                onPressed: () => setState(_selected.clear),
                icon: const Icon(Icons.close),
              )
            : null,
        actions: selecting
            ? [
                TextButton(
                  onPressed: () => setState(() {
                    _selected
                      ..clear()
                      ..addAll(notes.map((e) => e.id));
                  }),
                  child: const Text('全选'),
                ),
              ]
            : null,
      ),
      body: notes.isEmpty
          ? const Center(child: Text('回收站暂无笔记'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: notes.length,
              itemBuilder: (context, index) {
                final note = notes[index];
                return NoteCard(
                  note: note,
                  selected: _selected.contains(note.id),
                  onLongPress: () => setState(() => _selected.add(note.id)),
                  onTap: () {
                    if (selecting) {
                      setState(
                        () => _selected.contains(note.id)
                            ? _selected.remove(note.id)
                            : _selected.add(note.id),
                      );
                    } else {
                      Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              NoteEditorScreen(noteId: note.id, readOnly: true),
                        ),
                      );
                    }
                  },
                  trailing: selecting
                      ? null
                      : PopupMenuButton<String>(
                          onSelected: (value) => value == 'restore'
                              ? _restore([note.id])
                              : _delete([note.id]),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'restore', child: Text('恢复')),
                            PopupMenuItem(value: 'delete', child: Text('永久删除')),
                          ],
                        ),
                );
              },
            ),
      bottomNavigationBar: selecting
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _restore(_selected),
                        icon: const Icon(Icons.restore),
                        label: const Text('恢复'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _delete(_selected),
                        icon: const Icon(Icons.delete_forever),
                        label: const Text('永久删除'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Future<void> _restore(Iterable<String> ids) async {
    await AppScope.of(context).restore(ids.toList());
    if (mounted) setState(_selected.clear);
  }

  Future<void> _delete(Iterable<String> ids) async {
    final values = ids.toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('永久删除？'),
        content: Text('${values.length} 条笔记及其图片将无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await AppScope.of(context).deleteForever(values);
      if (mounted) setState(_selected.clear);
    }
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('关于 Moment'),
              subtitle: Text('Flutter 笔记版 · 支持 Markdown 预览'),
            ),
          ),
        ],
      ),
    );
}
