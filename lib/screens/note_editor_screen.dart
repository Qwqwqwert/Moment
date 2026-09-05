import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../models/note.dart';
import '../state/app_controller.dart';
import '../utils/tag_name.dart';

class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({
    super.key,
    this.noteId,
    this.readOnly = false,
    this.embedded = false,
    this.onSaved,
  });

  final String? noteId;
  final bool readOnly;
  final bool embedded;
  final VoidCallback? onSaved;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen>
    with WidgetsBindingObserver {
  late final AppController _app;
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final String _id;
  late final DateTime _createdAt;
  final List<_ChecklistEditor> _checklist = [];
  List<String> _images = [];
  List<String> _tags = [];
  bool _favorite = false;
  bool _persisted = false;
  bool _saving = false;
  bool _discarded = false;
  bool _markdownPreview = false;
  bool _saveHandledForDispose = false;
  bool _disposing = false;
  bool _keyboardWasVisible = false;
  String _saveLabel = '新笔记';
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _app = AppScope.read(context);
    final source = widget.noteId == null
        ? null
        : _app.findNote(widget.noteId!, deleted: widget.readOnly);
    final now = DateTime.now();
    _id = source?.id ?? newId();
    _createdAt = source?.createdAt ?? now;
    _persisted = source != null;
    _saveLabel = widget.readOnly ? '只读预览' : (_persisted ? '已保存' : '新笔记');
    _titleController = TextEditingController(text: source?.title ?? '');
    _contentController = TextEditingController(text: source?.content ?? '');
    _images = [...?source?.imagePaths];
    _tags = [...?source?.tags];
    _favorite = source?.isFavorite ?? false;
    for (final item in source?.checklist ?? const <ChecklistItem>[]) {
      _checklist.add(_ChecklistEditor(item));
    }
    if (!widget.readOnly) {
      _titleController.addListener(_scheduleSave);
      _contentController.addListener(_scheduleSave);
      WidgetsBinding.instance.addPostFrameCallback((_) => _recoverLostImages());
    }
  }

  @override
  void dispose() {
    _disposing = true;
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    if (!widget.readOnly && !_discarded && !_saveHandledForDispose) {
      _save();
    }
    _titleController.dispose();
    _contentController.dispose();
    for (final item in _checklist) {
      item.controller.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final keyboardVisible = View.of(context).viewInsets.bottom > 0;
    if (_keyboardWasVisible && !keyboardVisible && _isTextInputFocused) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    _keyboardWasVisible = keyboardVisible;
  }

  void _scheduleSave() {
    if (widget.readOnly) return;
    _discarded = false;
    if (mounted && !_disposing) setState(() => _saveLabel = '编辑中');
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), _save);
  }

  void _addChecklist() {
    setState(() {
      _checklist.add(_ChecklistEditor(ChecklistItem(id: newId(), text: '')));
    });
    _scheduleSave();
  }

  void _setMarkdownPreview(bool value) {
    if (_markdownPreview == value) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _markdownPreview = value);
  }

  MarkdownStyleSheet _markdownStyle(ThemeData theme) {
    final colors = theme.colorScheme;
    final base = MarkdownStyleSheet.fromTheme(theme);
    return base.copyWith(
      p: theme.textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.625),
      h1: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
      h2: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      h3: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      h4: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      h5: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      h6: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
      a: TextStyle(
        color: colors.primary,
        decoration: TextDecoration.underline,
        decorationColor: colors.primary,
      ),
      code: TextStyle(
        color: colors.error,
        fontFamily: 'monospace',
        fontSize: 14,
      ),
      blockSpacing: 8,
      listIndent: 24,
      codeblockPadding: const EdgeInsets.all(12),
      codeblockDecoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
      blockquoteDecoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(left: BorderSide(color: colors.outline, width: 3)),
      ),
      tableBorder: TableBorder.all(color: colors.outlineVariant),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 8,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
    );
  }

  Note _buildNote() => Note(
    id: _id,
    title: _titleController.text,
    content: _contentController.text,
    imagePaths: _images,
    tags: _tags,
    checklist: _checklist
        .where((item) => item.controller.text.trim().isNotEmpty)
        .map(
          (item) => ChecklistItem(
            id: item.id,
            text: item.controller.text,
            isChecked: item.checked,
          ),
        )
        .toList(),
    createdAt: _createdAt,
    updatedAt: DateTime.now(),
    isFavorite: _favorite,
  );

  Future<void> _save() async {
    if (_saving || widget.readOnly) return;
    final note = _buildNote();
    if (!_persisted &&
        note.isBlank &&
        note.checklist.isEmpty &&
        note.imagePaths.isEmpty) {
      if (mounted && !_disposing) setState(() => _saveLabel = '新笔记');
      return;
    }
    _saving = true;
    if (mounted && !_disposing) setState(() => _saveLabel = '保存中…');
    try {
      if (_persisted &&
          note.isBlank &&
          note.checklist.isEmpty &&
          note.imagePaths.isEmpty) {
        _discarded = true;
        await _app.trash([note.id]);
      } else {
        await _app.save(note);
        _persisted = true;
      }
      widget.onSaved?.call();
    } finally {
      _saving = false;
      if (mounted && !_disposing) setState(() => _saveLabel = '已保存');
    }
  }

  Future<void> _close() async {
    _saveTimer?.cancel();
    await _save();
    _saveHandledForDispose = true;
    if (mounted && !widget.embedded) Navigator.pop(context);
  }

  bool get _isTextInputFocused {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    return focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _handleSystemBack(bool didPop) {
    if (didPop) return;
    if (_isTextInputFocused) {
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    _close();
  }

  Future<void> _recoverLostImages() async {
    final recovered = await _app.attachmentStore.recoverLost(_id);
    if (recovered.isNotEmpty && mounted) {
      setState(() => _images = [..._images, ...recovered].take(9).toList());
      await _save();
    }
  }

  Future<void> _pickImages() async {
    try {
      final added = await _app.attachmentStore.pickAndStore(
        _id,
        remaining: 9 - _images.length,
      );
      if (!mounted || added.isEmpty) return;
      setState(() => _images = [..._images, ...added]);
      await _save();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('选择图片失败：$error')));
      }
    }
  }

  Future<void> _chooseTags() async {
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TagPickerSheet(
        app: _app,
        initialSelected: _tags,
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => _tags = selected);
    _scheduleSave();
  }

  Future<void> _toggleFavorite() async {
    final app = _app;
    if (!_persisted) await _save();
    if (!_persisted) return;
    setState(() => _favorite = !_favorite);
    await app.favorite(_id, _favorite);
  }

  Future<void> _delete() async {
    if (!_persisted) return _close();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除笔记？'),
        content: const Text('笔记将移入回收站，可稍后恢复。'),
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
      _discarded = true;
      await _app.trash([_id]);
      if (mounted && !widget.embedded) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editor = ColoredBox(
      color: theme.colorScheme.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 56),
            children: [
              Text(
                _formatDate(_createdAt),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: .2,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _titleController,
                readOnly: widget.readOnly,
                maxLength: 20,
                maxLines: null,
                decoration: const InputDecoration(
                  hintText: '无标题笔记',
                  counterText: '',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              if (_tags.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _tags.map((tag) => _EditorTag(tag: tag)).toList(),
                ),
              ],
              const SizedBox(height: 20),
              Divider(
                color: theme.colorScheme.outlineVariant.withValues(alpha: .55),
              ),
              if (_checklist.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (var index = 0; index < _checklist.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _checklistRow(index),
                  ),
                const SizedBox(height: 8),
              ],
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.topLeft,
                  children: [...previousChildren, ?currentChild],
                ),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: !widget.readOnly && !_markdownPreview
                    ? TextField(
                        key: const Key('markdown-source-editor'),
                        controller: _contentController,
                        autofocus: widget.noteId == null,
                        minLines: 12,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        decoration: const InputDecoration(
                          hintText: '从这里开始记录…',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontSize: 17,
                          height: 1.7,
                        ),
                      )
                    : ConstrainedBox(
                        key: const ValueKey('markdown-rendered-content'),
                        constraints: const BoxConstraints(minHeight: 300),
                        child: _contentController.text.trim().isEmpty
                            ? Text(
                                '还没有正文',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              )
                            : SelectionArea(
                                key: const Key('markdown-selection-area'),
                                child: MarkdownBody(
                                  key: const Key('markdown-preview'),
                                  data: _contentController.text,
                                  selectable: false,
                                  styleSheet: _markdownStyle(theme),
                                ),
                              ),
                      ),
              ),
              if (_images.isNotEmpty) ...[
                const SizedBox(height: 24),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _images.length,
                  itemBuilder: (context, index) => _imageTile(index),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    final body = PopScope(
      canPop: widget.embedded,
      onPopInvokedWithResult: (didPop, result) => _handleSystemBack(didPop),
      child: Column(
        children: [
          if (widget.embedded)
            _EditorToolbar(
              readOnly: widget.readOnly,
              favorite: _favorite,
              saveLabel: _saveLabel,
              markdownPreview: _markdownPreview,
              onMarkdownPreview: () => _setMarkdownPreview(!_markdownPreview),
              onFavorite: _toggleFavorite,
              onDelete: _delete,
            ),
          Expanded(child: editor),
          if (widget.embedded && !widget.readOnly)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _markdownPreview
                  ? const SizedBox.shrink(key: ValueKey('preview-bottom-bar'))
                  : _EditorBottomBar(
                      key: const ValueKey('edit-bottom-bar'),
                      onTags: _chooseTags,
                      onChecklist: _addChecklist,
                      onImages: _images.length >= 9 ? null : _pickImages,
                    ),
            ),
        ],
      ),
    );
    if (widget.embedded) {
      return Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: body,
      );
    }
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        backgroundColor: theme.colorScheme.surface,
        leading: IconButton(
          onPressed: _close,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          widget.readOnly
              ? '只读预览'
              : (_markdownPreview ? 'Markdown 预览' : _saveLabel),
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [
          if (!widget.readOnly)
            IconButton(
              tooltip: _markdownPreview ? '继续编辑' : '预览 Markdown',
              onPressed: () => _setMarkdownPreview(!_markdownPreview),
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  _markdownPreview
                      ? Icons.edit_outlined
                      : Icons.visibility_outlined,
                  key: ValueKey(_markdownPreview),
                ),
              ),
            ),
          if (!widget.readOnly)
            IconButton(
              tooltip: _favorite ? '取消收藏' : '收藏',
              onPressed: _toggleFavorite,
              icon: Icon(
                _favorite ? Icons.star_rounded : Icons.star_outline_rounded,
              ),
            ),
          if (!widget.readOnly && _persisted)
            IconButton(
              tooltip: '删除',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: body,
      bottomNavigationBar: widget.readOnly
          ? null
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _markdownPreview
                  ? const SizedBox.shrink(key: ValueKey('preview-bottom-bar'))
                  : _EditorBottomBar(
                      key: const ValueKey('edit-bottom-bar'),
                      onTags: _chooseTags,
                      onChecklist: _addChecklist,
                      onImages: _images.length >= 9 ? null : _pickImages,
                    ),
            ),
    );
  }

  Widget _checklistRow(int index) {
    final item = _checklist[index];
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Checkbox(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            value: item.checked,
            onChanged: widget.readOnly
                ? null
                : (value) {
                    setState(() => item.checked = value ?? false);
                    _scheduleSave();
                  },
          ),
          Expanded(
            child: TextField(
              controller: item.controller,
              readOnly: widget.readOnly,
              decoration: const InputDecoration(
                hintText: '清单内容',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
              style: TextStyle(
                decoration: item.checked ? TextDecoration.lineThrough : null,
                color: item.checked ? colors.onSurfaceVariant : null,
              ),
              onChanged: (_) => _scheduleSave(),
            ),
          ),
          if (!widget.readOnly)
            IconButton(
              tooltip: '移除',
              onPressed: () {
                setState(() => _checklist.removeAt(index).controller.dispose());
                _scheduleSave();
              },
              icon: const Icon(Icons.close_rounded, size: 19),
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) =>
      '${date.year}年${date.month}月${date.day}日  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  Widget _imageTile(int index) => Stack(
    fit: StackFit.expand,
    children: [
      InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => Dialog.fullscreen(
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    child: Image.file(File(_images[index])),
                  ),
                ),
                SafeArea(
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(File(_images[index]), fit: BoxFit.cover),
        ),
      ),
      if (!widget.readOnly)
        Positioned(
          right: 4,
          top: 4,
          child: IconButton.filledTonal(
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              final removed = _images[index];
              setState(() => _images.removeAt(index));
              await _save();
              await _app.attachmentStore.deleteFiles([removed]);
            },
            icon: const Icon(Icons.close, size: 18),
          ),
        ),
    ],
  );
}

class _TagPickerSheet extends StatefulWidget {
  const _TagPickerSheet({
    required this.app,
    required this.initialSelected,
  });

  final AppController app;
  final List<String> initialSelected;

  @override
  State<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<_TagPickerSheet> {
  final _tagController = TextEditingController();
  final _tagLengthLimiter = LengthLimitingTextInputFormatter(
    maxTagNameLength,
  );
  late final List<String> _availableTags;
  late final List<String> _selected;
  bool _addingTag = false;

  @override
  void initState() {
    super.initState();
    _availableTags = [...widget.app.tags];
    _selected = [...widget.initialSelected];
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _addTag() async {
    final value = normalizeTagName(_tagController.text);
    if (value.isEmpty || _addingTag) return;
    final validationMessage = validateNewTagName(value, _availableTags);
    if (validationMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validationMessage)));
      return;
    }

    setState(() => _addingTag = true);
    await widget.app.addTag(value);
    if (!mounted) return;
    setState(() {
      _availableTags.add(value);
      _selected.add(value);
      _tagController.clear();
      _addingTag = false;
    });
  }

  void _finish() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(context, [..._selected]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    final sheetHeight = (mediaQuery.size.height * .68 + keyboardHeight)
        .clamp(0.0, mediaQuery.size.height * .92)
        .toDouble();

    return SafeArea(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: sheetHeight,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + keyboardHeight),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('选择标签', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tagController,
                      maxLength: maxTagNameLength,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      inputFormatters: [_tagLengthLimiter],
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _addTag(),
                      decoration: const InputDecoration(
                        hintText: '输入标签名称',
                        prefixIcon: Icon(Icons.label_outline_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      onPressed:
                          _tagController.text.trim().isEmpty || _addingTag
                          ? null
                          : _addTag,
                      icon: _addingTag
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_rounded, size: 20),
                      label: const Text('添加'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _availableTags.isEmpty
                    ? Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          '还没有标签，可以在上方快速创建',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: _availableTags
                              .map(
                                (tag) => FilterChip(
                                  label: Text(tag),
                                  selected: _selected.contains(tag),
                                  onSelected: (value) => setState(() {
                                    value
                                        ? _selected.add(tag)
                                        : _selected.remove(tag);
                                  }),
                                ),
                              )
                              .toList(),
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _finish,
                  child: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChecklistEditor {
  _ChecklistEditor(ChecklistItem item)
    : id = item.id,
      checked = item.isChecked,
      controller = TextEditingController(text: item.text);
  final String id;
  bool checked;
  final TextEditingController controller;
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({
    required this.readOnly,
    required this.favorite,
    required this.saveLabel,
    required this.markdownPreview,
    required this.onMarkdownPreview,
    required this.onFavorite,
    required this.onDelete,
  });
  final bool readOnly;
  final bool favorite;
  final String saveLabel;
  final bool markdownPreview;
  final VoidCallback onMarkdownPreview;
  final VoidCallback onFavorite;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Container(
    height: 64,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(
        bottom: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant
              .withValues(alpha: .4),
        ),
      ),
    ),
    child: Row(
      children: [
        Text(
          readOnly ? '只读预览' : (markdownPreview ? 'Markdown 预览' : saveLabel),
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const Spacer(),
        if (!readOnly)
          IconButton(
            tooltip: markdownPreview ? '继续编辑' : '预览 Markdown',
            onPressed: onMarkdownPreview,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(
                markdownPreview
                    ? Icons.edit_outlined
                    : Icons.visibility_outlined,
                key: ValueKey(markdownPreview),
              ),
            ),
          ),
        if (!readOnly)
          IconButton(
            tooltip: favorite ? '取消收藏' : '收藏',
            onPressed: onFavorite,
            icon: Icon(
              favorite ? Icons.star_rounded : Icons.star_outline_rounded,
            ),
          ),
        if (!readOnly)
          IconButton(
            tooltip: '删除',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
      ],
    ),
  );
}

class _EditorBottomBar extends StatelessWidget {
  const _EditorBottomBar({
    super.key,
    required this.onTags,
    required this.onChecklist,
    required this.onImages,
  });

  final VoidCallback onTags;
  final VoidCallback onChecklist;
  final VoidCallback? onImages;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(
            top: BorderSide(color: colors.outlineVariant.withValues(alpha: .5)),
          ),
        ),
        child: Row(
          children: [
            _EditorAction(
              icon: Icons.label_outline_rounded,
              label: '标签',
              onPressed: onTags,
            ),
            _EditorAction(
              icon: Icons.check_box_outlined,
              label: '清单',
              onPressed: onChecklist,
            ),
            _EditorAction(
              icon: Icons.add_photo_alternate_outlined,
              label: '图片',
              onPressed: onImages,
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorAction extends StatelessWidget {
  const _EditorAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        visualDensity: VisualDensity.compact,
      ),
    ),
  );
}

class _EditorTag extends StatelessWidget {
  const _EditorTag({required this.tag});
  final String tag;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '# $tag',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colors.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
