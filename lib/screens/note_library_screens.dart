import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/note.dart';
import '../services/ai_service.dart';
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
  bool _naturalLanguage = false;
  bool _aiSearching = false;
  List<Note> _aiResults = const [];

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
      final haystack = [note.title, note.content].join('\n').toLowerCase();
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
    final app = AppScope.of(context);
    final results = _naturalLanguage
        ? _filterByDate(_aiResults)
        : _results(app.notes);
    return Scaffold(
      appBar: AppBar(title: const Text('搜索笔记')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchBar(
              controller: _query,
              focusNode: _focusNode,
              hintText: _naturalLanguage ? '描述你想查找的笔记' : '请输入关键词',
              leading: const Icon(Icons.search),
              onChanged: (_) => setState(() {
                if (_naturalLanguage) _aiResults = const [];
              }),
              onSubmitted: (_) {
                if (_naturalLanguage) _runNaturalSearch(app);
              },
              trailing: [
                if (_naturalLanguage)
                  IconButton(
                    tooltip: '开始自然语言搜索',
                    onPressed: _aiSearching
                        ? null
                        : () => _runNaturalSearch(app),
                    icon: _aiSearching
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_rounded),
                  ),
                IconButton(
                  onPressed: _showDateFilter,
                  icon: const Icon(Icons.tune),
                ),
              ],
            ),
          ),
          if (app.aiConfig.isComplete)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('关键词')),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.auto_awesome_rounded),
                    label: Text('自然语言'),
                  ),
                ],
                selected: {_naturalLanguage},
                onSelectionChanged: (value) => setState(() {
                  _naturalLanguage = value.single;
                  _aiResults = const [];
                }),
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
            child: _aiSearching
                ? const Center(child: CircularProgressIndicator())
                : _query.text.trim().isEmpty
                ? Center(
                    child: Text(_naturalLanguage ? '描述你想查找的笔记' : '输入关键词搜索笔记'),
                  )
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

  Future<void> _runNaturalSearch(AppController app) async {
    final query = _query.text.trim();
    if (query.isEmpty || _aiSearching) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('使用自然语言搜索？'),
        content: const Text('该功能会把搜索内容、所有笔记正文及必要元数据发送给你配置的 AI，可能消耗大量模型额度。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续搜索'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _aiSearching = true);
    try {
      final ids = await AiService(app.aiConfig)
          .searchNotes(query: query, notes: app.notes);
      final byId = {for (final note in app.notes) note.id: note};
      if (mounted) {
        setState(
          () => _aiResults = [
            for (final id in ids)
              if (byId[id] != null) byId[id]!,
          ],
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('AI 搜索失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _aiSearching = false);
    }
  }

  List<Note> _filterByDate(List<Note> notes) => notes.where((note) {
    final date = DateTime(
      note.updatedAt.year,
      note.updatedAt.month,
      note.updatedAt.day,
    );
    return (_start == null || !date.isBefore(_start!)) &&
        (_end == null || !date.isAfter(_end!));
  }).toList();

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
  final _tagLengthLimiter = LengthLimitingTextInputFormatter(maxTagNameLength);
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(validationMessage)));
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
                              NoteEditorScreen(
                                noteId: note.id,
                                readOnly: true,
                                deleted: true,
                              ),
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
        content: Text('${values.length} 条笔记及其附件将无法恢复。'),
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

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _apiKey = TextEditingController();
  bool _loaded = false;
  bool _saving = false;
  bool _testing = false;
  bool _updatingCreatedAt = false;
  bool _showKey = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    final config = AppScope.of(context).aiConfig;
    _baseUrl.text = config.baseUrl;
    _model.text = config.model;
    _apiKey.text = config.apiKey;
    _loaded = true;
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await AppScope.read(context).saveAiConfig(
        AiConfig(
          baseUrl: _baseUrl.text,
          model: _model.text,
          apiKey: _apiKey.text,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('AI 配置已保存')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  AiConfig get _currentConfig => AiConfig(
    baseUrl: _baseUrl.text,
    model: _model.text,
    apiKey: _apiKey.text,
  );

  Future<void> _testSingleTurn() async {
    final config = _currentConfig;
    if (!config.isComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先完整填写 Base URL、模型名称和 API Key')),
      );
      return;
    }

    var draftMessage = '请只回复“调用成功”四个字。';
    final message = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('LLM 单轮对话测试'),
        content: TextFormField(
          initialValue: draftMessage,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          onChanged: (value) => draftMessage = value,
          decoration: const InputDecoration(
            labelText: '发送给模型的消息',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draftMessage.trim()),
            child: const Text('发送'),
          ),
        ],
      ),
    );
    if (!mounted || message == null || message.isEmpty) return;

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _testing = true);
    try {
      final response = await AiService(config).singleTurn(message);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle_outline_rounded),
          title: const Text('调用成功'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(child: SelectableText(response)),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            icon: Icon(
              Icons.error_outline_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            title: const Text('调用失败'),
            content: SingleChildScrollView(
              child: SelectableText(error.toString()),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _changeNoteCreatedAt() async {
    final app = AppScope.read(context);
    if (app.notes.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前没有可修改的笔记')));
      return;
    }

    final note = await showModalBottomSheet<Note>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .68,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Text(
                  '选择笔记',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: app.notes.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final candidate = app.notes[index];
                    return ListTile(
                      leading: const Icon(Icons.note_outlined),
                      title: Text(
                        _noteDisplayTitle(candidate),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '创建于 ${_formatDateTime(candidate.createdAt)}',
                      ),
                      onTap: () => Navigator.pop(context, candidate),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || note == null) return;

    final date = await showDatePicker(
      context: context,
      initialDate: note.createdAt,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
      helpText: '选择创建日期',
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(note.createdAt),
      helpText: '选择创建时间',
    );
    if (!mounted || time == null) return;

    final createdAt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认修改创建时间？'),
        content: Text(
          '“${_noteDisplayTitle(note)}”\n\n'
          '${_formatDateTime(note.createdAt)}\n'
          '改为\n'
          '${_formatDateTime(createdAt)}\n\n'
          '最新修改时间不会改变。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认修改'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    setState(() => _updatingCreatedAt = true);
    try {
      await app.save(note.copyWith(createdAt: createdAt));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('笔记创建时间已修改')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('修改失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _updatingCreatedAt = false);
    }
  }

  String _noteDisplayTitle(Note note) {
    final title = note.title.trim();
    if (title.isNotEmpty) return title;
    final content = note.content.trim();
    if (content.isEmpty) return '无标题笔记';
    return content.split(RegExp(r'\r?\n')).first.trim();
  }

  String _formatDateTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute';
  }

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
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.edit_calendar_outlined),
            title: const Text('修改笔记创建时间'),
            subtitle: const Text('临时测试工具 · 不会改变最新修改时间'),
            trailing: _updatingCreatedAt
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right_rounded),
            onTap: _updatingCreatedAt ? null : _changeNoteCreatedAt,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI 配置', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text(
                  '支持 OpenAI 兼容的 Chat Completions 接口。API Key 将加密保存在本机；三项全部填写后，AI 标签和自然语言搜索才会显示。',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _baseUrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'https://api.example.com/v1',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _model,
                  decoration: const InputDecoration(labelText: '模型名称'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _apiKey,
                  obscureText: !_showKey,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _showKey = !_showKey),
                      icon: Icon(
                        _showKey
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _saving || _testing ? null : _testSingleTurn,
                    icon: _testing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chat_outlined),
                    label: Text(_testing ? '正在调用' : '测试单轮对话'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving || _testing ? null : _save,
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('保存 AI 配置'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
