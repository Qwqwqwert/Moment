import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:just_audio/just_audio.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../models/note.dart';
import '../services/ai_service.dart';
import '../state/app_controller.dart';
import '../theme/desktop_environment.dart';
import '../utils/tag_name.dart';
import '../widgets/markdown_code_block.dart';

class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({
    super.key,
    this.noteId,
    this.readOnly = false,
    this.deleted = false,
    this.historyPreview = false,
    this.embedded = false,
    this.onSaved,
  }) : assert(!historyPreview || readOnly);

  final String? noteId;
  final bool readOnly;
  final bool deleted;
  final bool historyPreview;
  final bool embedded;
  final ValueChanged<String>? onSaved;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen>
    with WidgetsBindingObserver {
  late final AppController _app;
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final PageController _imagePageController;
  late final PageController _videoPageController;
  late final String _id;
  late final DateTime _createdAt;
  List<String> _images = [];
  List<String> _videos = [];
  List<String> _audio = [];
  List<String> _tags = [];
  int _imagePage = 0;
  int _videoPage = 0;
  bool _favorite = false;
  bool _persisted = false;
  bool _saving = false;
  bool _dirty = false;
  bool _discarded = false;
  bool _markdownPreview = false;
  bool _saveHandledForDispose = false;
  bool _disposing = false;
  bool _keyboardWasVisible = false;
  String _saveLabel = '新笔记';
  Timer? _saveTimer;

  bool get _desktop => DesktopEnvironment.isDesktopOf(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _app = AppScope.read(context);
    final source = widget.noteId == null
        ? null
        : _app.findNote(widget.noteId!, deleted: widget.deleted);
    final now = DateTime.now();
    _id = source?.id ?? newId();
    _createdAt = source?.createdAt ?? now;
    _persisted = source != null;
    _saveLabel = widget.readOnly ? '只读预览' : (_persisted ? '已保存' : '新笔记');
    _titleController = TextEditingController(text: source?.title ?? '');
    _contentController = TextEditingController(text: source?.content ?? '');
    _imagePageController = PageController();
    _videoPageController = PageController();
    _images = [...?source?.imagePaths];
    _videos = [...?source?.videoPaths];
    _audio = [...?source?.audioPaths];
    _tags = [...?source?.tags];
    _favorite = source?.isFavorite ?? false;
    _markdownPreview = widget.readOnly || widget.historyPreview;
    _app.pendingWork.register(_flushPendingSave);
    if (!widget.readOnly) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _recoverLostAttachments(),
      );
    }
  }

  @override
  void dispose() {
    _disposing = true;
    WidgetsBinding.instance.removeObserver(this);
    _app.pendingWork.unregister(_flushPendingSave);
    _saveTimer?.cancel();
    if (!widget.readOnly && !_discarded && !_saveHandledForDispose) {
      _save();
    }
    _titleController.dispose();
    _contentController.dispose();
    _imagePageController.dispose();
    _videoPageController.dispose();
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
    _dirty = true;
    _discarded = false;
    if (mounted && !_disposing) setState(() => _saveLabel = '编辑中');
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), _save);
  }

  void _setMarkdownPreview(bool value) {
    if (_markdownPreview == value) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _markdownPreview = value);
  }

  Future<void> _openMarkdownLink(String href) async {
    final uri = Uri.tryParse(href.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法打开该链接')));
      }
      return;
    }
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // The platform can throw when no external handler is available.
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('浏览器打开失败')));
    }
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
        backgroundColor: Colors.transparent,
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
    videoPaths: _videos,
    audioPaths: _audio,
    tags: _tags,
    createdAt: _createdAt,
    updatedAt: DateTime.now(),
    isFavorite: _favorite,
  );

  String _markdownDocument() {
    final sections = <String>[];
    final title = _titleController.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final content = _contentController.text.trim();
    if (title.isNotEmpty) sections.add('# $title');
    if (content.isNotEmpty) sections.add(content);

    if (_tags.isNotEmpty) {
      sections.add('标签：${_tags.map((tag) => '#$tag').join(' ')}');
    }
    return sections.join('\n\n').trim();
  }

  String _markdownFileName() {
    final title = _titleController.text
        .replaceAll(RegExp(r'[\\/:*?"<>|\r\n]+'), ' ')
        .trim();
    if (title.isNotEmpty) {
      final safeTitle = title.length > 80
          ? title.substring(0, 80).trim()
          : title;
      return '$safeTitle.md';
    }
    final now = DateTime.now();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return 'Moment-${now.year}${twoDigits(now.month)}${twoDigits(now.day)}-'
        '${twoDigits(now.hour)}${twoDigits(now.minute)}.md';
  }

  Future<void> _shareNote() async {
    final markdown = _markdownDocument();
    if (markdown.isEmpty) {
      _showActionMessage('没有可分享的文字内容');
      return;
    }
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: markdown,
          subject: _titleController.text.trim().isEmpty
              ? 'Moment 笔记'
              : _titleController.text.trim(),
        ),
      );
    } catch (_) {
      _showActionMessage('无法打开系统分享面板');
    }
  }

  Future<void> _exportMarkdown() async {
    final markdown = _markdownDocument();
    if (markdown.isEmpty) {
      _showActionMessage('没有可导出的文字内容');
      return;
    }
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: '导出 Markdown',
        fileName: _markdownFileName(),
        bytes: Uint8List.fromList(utf8.encode(markdown)),
        type: FileType.custom,
        allowedExtensions: const ['md'],
        mimeType: 'text/markdown',
      );
      if (uri != null) _showActionMessage('Markdown 文件已导出');
    } catch (_) {
      _showActionMessage('导出失败，请稍后重试');
    }
  }

  void _showActionMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _handleShareExportAction(_NoteShareExportAction action) {
    switch (action) {
      case _NoteShareExportAction.share:
        unawaited(_shareNote());
        break;
      case _NoteShareExportAction.exportMarkdown:
        unawaited(_exportMarkdown());
        break;
    }
  }

  Future<void> _save() async {
    if (_saving || widget.readOnly || (_persisted && !_dirty)) return;
    final note = _buildNote();
    if (!_persisted &&
        note.isBlank &&
        note.imagePaths.isEmpty &&
        note.videoPaths.isEmpty &&
        note.audioPaths.isEmpty) {
      if (mounted && !_disposing) setState(() => _saveLabel = '新笔记');
      _dirty = false;
      return;
    }
    _saving = true;
    if (mounted && !_disposing) setState(() => _saveLabel = '保存中…');
    try {
      if (_persisted &&
          note.isBlank &&
          note.imagePaths.isEmpty &&
          note.videoPaths.isEmpty &&
          note.audioPaths.isEmpty) {
        _discarded = true;
        await _app.trash([note.id]);
      } else {
        await _app.save(note, isNew: !_persisted);
        _persisted = true;
      }
      _dirty = false;
      widget.onSaved?.call(note.id);
    } finally {
      _saving = false;
      if (mounted && !_disposing) setState(() => _saveLabel = '已保存');
    }
  }

  Future<void> _flushPendingSave() async {
    _saveTimer?.cancel();
    while (_saving) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await _save();
    while (_saving) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
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

  Future<void> _recoverLostAttachments() async {
    final recovered = await _app.pendingWork.track(
      _app.attachmentStore.recoverLost(_id),
    );
    if ((recovered.images.isNotEmpty || recovered.videos.isNotEmpty) &&
        mounted) {
      setState(() {
        _images = [..._images, ...recovered.images];
        _videos = [..._videos, ...recovered.videos].take(9).toList();
      });
      _dirty = true;
      await _save();
    }
  }

  Future<void> _pickImages() async {
    try {
      final added = await _app.pendingWork.track(
        _app.attachmentStore.pickAndStore(_id),
      );
      if (!mounted || added.isEmpty) return;
      final wasEmpty = _images.isEmpty;
      setState(() => _images = [..._images, ...added]);
      if (wasEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_imagePageController.hasClients) {
            _imagePageController.jumpToPage(0);
          }
        });
      }
      _dirty = true;
      await _save();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('选择图片失败：$error')));
      }
    }
  }

  Future<void> _pickVideo() async {
    try {
      final added = await _app.pendingWork.track(
        _app.attachmentStore.pickVideoAndStore(_id),
      );
      if (!mounted || added == null) return;
      final wasEmpty = _videos.isEmpty;
      setState(() => _videos = [..._videos, added]);
      if (wasEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_videoPageController.hasClients) {
            _videoPageController.jumpToPage(0);
          }
        });
      }
      _dirty = true;
      await _save();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('选择视频失败：$error')));
      }
    }
  }

  Future<void> _chooseAttachment() async {
    FocusManager.instance.primaryFocus?.unfocus();
    Widget choices(BuildContext context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.add_photo_alternate_outlined),
            title: const Text('图片'),
            onTap: () => Navigator.pop(context, _AttachmentAction.image),
          ),
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: const Text('视频'),
            subtitle: _videos.length >= 9 ? const Text('最多添加 9 个视频') : null,
            enabled: _videos.length < 9,
            onTap: _videos.length >= 9
                ? null
                : () => Navigator.pop(context, _AttachmentAction.video),
          ),
          ListTile(
            leading: const Icon(Icons.mic_none_rounded),
            title: const Text('语音'),
            onTap: () => Navigator.pop(context, _AttachmentAction.voice),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
    final action = _desktop
        ? await showDialog<_AttachmentAction>(
            context: context,
            builder: (context) =>
                Dialog(child: SizedBox(width: 400, child: choices(context))),
          )
        : await showModalBottomSheet<_AttachmentAction>(
            context: context,
            showDragHandle: true,
            builder: choices,
          );
    if (!mounted || action == null) return;
    switch (action) {
      case _AttachmentAction.image:
        await _pickImages();
        break;
      case _AttachmentAction.video:
        await _pickVideo();
        break;
      case _AttachmentAction.voice:
        await _chooseVoice();
        break;
    }
  }

  Future<void> _chooseVoice() async {
    FocusManager.instance.primaryFocus?.unfocus();
    Widget choices(BuildContext context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.mic_rounded),
            title: const Text('录制语音'),
            onTap: () => Navigator.pop(context, _VoiceAction.record),
          ),
          ListTile(
            leading: const Icon(Icons.audio_file_outlined),
            title: const Text('导入现有语音'),
            onTap: () => Navigator.pop(context, _VoiceAction.import),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
    final action = _desktop
        ? await showDialog<_VoiceAction>(
            context: context,
            builder: (context) =>
                Dialog(child: SizedBox(width: 400, child: choices(context))),
          )
        : await showModalBottomSheet<_VoiceAction>(
            context: context,
            showDragHandle: true,
            builder: choices,
          );
    if (!mounted || action == null) return;
    switch (action) {
      case _VoiceAction.record:
        await _recordVoice();
        break;
      case _VoiceAction.import:
        await _importVoice();
        break;
    }
  }

  Future<void> _recordVoice() async {
    final recorder = AudioRecorder();
    try {
      final allowed = await recorder.hasPermission();
      if (!mounted) return;
      if (!allowed) {
        _showActionMessage('需要麦克风权限才能录制语音');
        return;
      }
      final path = await _app.attachmentStore.createAudioRecordingPath(_id);
      if (!mounted) return;
      final recordedPath = _desktop
          ? await showDialog<String>(
              context: context,
              barrierDismissible: false,
              builder: (context) => Dialog(
                child: SizedBox(
                  width: 430,
                  child: _VoiceRecorderSheet(recorder: recorder, path: path),
                ),
              ),
            )
          : await showModalBottomSheet<String>(
              context: context,
              isDismissible: false,
              enableDrag: false,
              showDragHandle: true,
              builder: (context) =>
                  _VoiceRecorderSheet(recorder: recorder, path: path),
            );
      if (!mounted || recordedPath == null) return;
      setState(() => _audio = [..._audio, recordedPath]);
      _dirty = true;
      await _save();
    } catch (error) {
      _showActionMessage(
        _desktop ? '录制语音失败，请检查 Windows 设置中的麦克风隐私权限：$error' : '录制语音失败：$error',
      );
    } finally {
      await recorder.dispose();
    }
  }

  Future<void> _importVoice() async {
    try {
      final path = await _app.pendingWork.track(
        _app.attachmentStore.importAudioAndStore(_id),
      );
      if (!mounted || path == null) return;
      setState(() => _audio = [..._audio, path]);
      _dirty = true;
      await _save();
    } catch (error) {
      _showActionMessage('导入语音失败：$error');
    }
  }

  Future<void> _chooseTags() async {
    Widget picker(BuildContext context) => _TagPickerSheet(
      app: _app,
      initialSelected: _tags,
      noteTitle: _titleController.text,
      noteContent: _contentController.text,
    );
    final selected = _desktop
        ? await showDialog<List<String>>(
            context: context,
            builder: (context) =>
                Dialog(child: SizedBox(width: 540, child: picker(context))),
          )
        : await showModalBottomSheet<List<String>>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: picker,
          );
    if (!mounted || selected == null) return;
    if (listEquals(_tags, selected)) return;
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
              if (widget.historyPreview) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: .55,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.auto_stories_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '来自 ${_createdAt.year} 年的今天 · '
                          '${DateTime.now().year - _createdAt.year} 年前',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                _formatDate(_createdAt),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: .2,
                ),
              ),
              const SizedBox(height: 10),
              if (widget.historyPreview)
                SelectableText(
                  _titleController.text.trim().isEmpty
                      ? '无标题笔记'
                      : _titleController.text,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: _titleController.text.trim().isEmpty
                        ? theme.colorScheme.onSurfaceVariant
                        : null,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                )
              else
                TextField(
                  controller: _titleController,
                  readOnly: widget.readOnly,
                  onChanged: widget.readOnly ? null : (_) => _scheduleSave(),
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
                        onChanged: (_) => _scheduleSave(),
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
                            : Align(
                                alignment: Alignment.topLeft,
                                child: SizedBox(
                                  width: double.infinity,
                                  child: SelectionArea(
                                    key: const Key('markdown-selection-area'),
                                    child: MarkdownBody(
                                      key: const Key('markdown-preview'),
                                      data: _contentController.text,
                                      selectable: false,
                                      styleSheet: _markdownStyle(theme),
                                      builders: {
                                        'pre': MarkdownCodeBlockBuilder(
                                          colors: theme.colorScheme,
                                        ),
                                      },
                                      onTapLink: (text, href, title) {
                                        if (href != null) {
                                          unawaited(_openMarkdownLink(href));
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ),
                      ),
              ),
              if (_images.isNotEmpty || _videos.isNotEmpty) ...[
                const SizedBox(height: 24),
                SizedBox(
                  height: 220,
                  child: Row(
                    children: [
                      if (_images.isNotEmpty) Expanded(child: _imageGallery()),
                      if (_images.isNotEmpty && _videos.isNotEmpty)
                        const SizedBox(width: 10),
                      if (_videos.isNotEmpty) Expanded(child: _videoGallery()),
                    ],
                  ),
                ),
              ],
              if (_audio.isNotEmpty) ...[
                const SizedBox(height: 20),
                for (var index = 0; index < _audio.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _AudioAttachmentTile(
                      key: ValueKey(_audio[index]),
                      path: _audio[index],
                      index: index,
                      readOnly: widget.readOnly,
                      onRemove: () => _removeAudio(index),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );

    final body = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          unawaited(_flushPendingSave());
        },
      },
      child: PopScope(
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
                onTags: _chooseTags,
                onAdd: _chooseAttachment,
                onShareExport: _handleShareExportAction,
                onDelete: _delete,
              ),
            Expanded(child: editor),
            if (widget.embedded && !widget.readOnly && !_desktop)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _markdownPreview
                    ? const SizedBox.shrink(key: ValueKey('preview-bottom-bar'))
                    : _EditorBottomBar(
                        key: const ValueKey('edit-bottom-bar'),
                        onTags: _chooseTags,
                        onAdd: _chooseAttachment,
                      ),
              ),
          ],
        ),
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
          widget.historyPreview
              ? '历史的今天'
              : widget.readOnly
              ? '只读预览'
              : (_markdownPreview ? 'Markdown 预览' : _saveLabel),
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [
          if (_desktop && !widget.readOnly) ...[
            TextButton.icon(
              onPressed: _chooseTags,
              icon: const Icon(Icons.label_outline_rounded, size: 18),
              label: const Text('标签'),
            ),
            TextButton.icon(
              onPressed: _chooseAttachment,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('添加'),
            ),
          ],
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
          if (!widget.historyPreview)
            _ShareExportMenu(onSelected: _handleShareExportAction),
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
          : _desktop
          ? null
          : Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _markdownPreview
                    ? const SizedBox.shrink(key: ValueKey('preview-bottom-bar'))
                    : _EditorBottomBar(
                        key: const ValueKey('edit-bottom-bar'),
                        onTags: _chooseTags,
                        onAdd: _chooseAttachment,
                      ),
              ),
            ),
    );
  }

  String _formatDate(DateTime date) =>
      '${date.year}年${date.month}月${date.day}日  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  Widget _imageGallery() => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _imagePageController,
          itemCount: _images.length,
          onPageChanged: (value) => setState(() => _imagePage = value),
          itemBuilder: (context, index) => GestureDetector(
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) =>
                  _ImageGalleryDialog(paths: _images, initialIndex: index),
            ),
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Image.file(
                File(_images[index]),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
        ),
        Positioned(
          left: 10,
          bottom: 10,
          child: _MediaCounter(current: _imagePage + 1, total: _images.length),
        ),
        if (!widget.readOnly)
          Positioned(
            right: 8,
            top: 8,
            child: IconButton.filledTonal(
              tooltip: '移除当前图片',
              visualDensity: VisualDensity.compact,
              onPressed: () => _removeImage(_imagePage),
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ),
      ],
    ),
  );

  Widget _videoGallery() => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _videoPageController,
          itemCount: _videos.length,
          onPageChanged: (value) => setState(() => _videoPage = value),
          itemBuilder: (context, index) => _VideoThumbnail(
            key: ValueKey(_videos[index]),
            path: _videos[index],
            readOnly: widget.readOnly,
            onPlay: () => showDialog<void>(
              context: context,
              builder: (context) =>
                  _VideoPlayerDialog(paths: _videos, initialIndex: index),
            ),
            onRemove: () => _removeVideo(index),
          ),
        ),
        Positioned(
          left: 10,
          bottom: 10,
          child: _MediaCounter(current: _videoPage + 1, total: _videos.length),
        ),
      ],
    ),
  );

  Future<void> _removeImage(int index) async {
    final removed = _images[index];
    setState(() {
      _images.removeAt(index);
      if (_images.isEmpty) {
        _imagePage = 0;
      } else if (_imagePage >= _images.length) {
        _imagePage = _images.length - 1;
      }
    });
    if (_images.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_imagePageController.hasClients) {
          _imagePageController.jumpToPage(_imagePage);
        }
      });
    }
    _dirty = true;
    await _save();
    await _app.attachmentStore.deleteFiles([removed]);
  }

  Future<void> _removeVideo(int index) async {
    final removed = _videos[index];
    setState(() {
      _videos.removeAt(index);
      if (_videos.isEmpty) {
        _videoPage = 0;
      } else if (_videoPage >= _videos.length) {
        _videoPage = _videos.length - 1;
      }
    });
    if (_videos.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_videoPageController.hasClients) {
          _videoPageController.jumpToPage(_videoPage);
        }
      });
    }
    _dirty = true;
    await _save();
    await _app.attachmentStore.deleteFiles([removed]);
  }

  Future<void> _removeAudio(int index) async {
    final removed = _audio[index];
    setState(() => _audio.removeAt(index));
    _dirty = true;
    await _save();
    await _app.attachmentStore.deleteFiles([removed]);
  }
}

class _ImageGalleryDialog extends StatefulWidget {
  const _ImageGalleryDialog({required this.paths, required this.initialIndex});

  final List<String> paths;
  final int initialIndex;

  @override
  State<_ImageGalleryDialog> createState() => _ImageGalleryDialogState();
}

class _ImageGalleryDialogState extends State<_ImageGalleryDialog> {
  late final PageController _controller;
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = widget.initialIndex;
    _controller = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    backgroundColor: Colors.black,
    child: SafeArea(
      child: Stack(
        children: [
          PhotoViewGallery.builder(
            pageController: _controller,
            itemCount: widget.paths.length,
            onPageChanged: (value) => setState(() => _page = value),
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            loadingBuilder: (context, event) =>
                const Center(child: CircularProgressIndicator()),
            builder: (context, index) => PhotoViewGalleryPageOptions(
              imageProvider: FileImage(File(widget.paths[index])),
              initialScale: PhotoViewComputedScale.contained,
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 5,
            ),
          ),
          Positioned(
            left: 4,
            top: 4,
            child: IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
          Positioned(
            right: 16,
            top: 10,
            child: _MediaCounter(
              current: _page + 1,
              total: widget.paths.length,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MediaCounter extends StatelessWidget {
  const _MediaCounter({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        '$current / $total',
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

class _VideoThumbnail extends StatefulWidget {
  const _VideoThumbnail({
    super.key,
    required this.path,
    required this.readOnly,
    required this.onPlay,
    required this.onRemove,
  });

  final String path;
  final bool readOnly;
  final VoidCallback onPlay;
  final VoidCallback onRemove;

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  late final VideoPlayerController _controller;
  late final Future<void> _initialize;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path));
    _initialize = _prepareThumbnail();
  }

  Future<void> _prepareThumbnail() async {
    await _controller.initialize();
    await _controller.setVolume(0);
    await _controller.seekTo(const Duration(milliseconds: 1));
    await _controller.pause();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: Material(
      color: Colors.black,
      child: InkWell(
        onTap: widget.onPlay,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<void>(
              future: _initialize,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Icon(
                      Icons.videocam_off_outlined,
                      color: Colors.white70,
                      size: 40,
                    ),
                  );
                }
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                return FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox.fromSize(
                    size: _controller.value.size,
                    child: VideoPlayer(_controller),
                  ),
                );
              },
            ),
            const Center(
              child: Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white,
                size: 52,
                shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
              ),
            ),
            if (!widget.readOnly)
              Positioned(
                right: 6,
                top: 6,
                child: IconButton.filledTonal(
                  tooltip: '移除视频',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _VideoPlayerDialog extends StatefulWidget {
  const _VideoPlayerDialog({required this.paths, required this.initialIndex});

  final List<String> paths;
  final int initialIndex;

  @override
  State<_VideoPlayerDialog> createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<_VideoPlayerDialog> {
  late final PageController _pageController;
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = widget.initialIndex;
    _pageController = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    backgroundColor: Colors.black,
    child: SafeArea(
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.paths.length,
            onPageChanged: (value) => setState(() => _page = value),
            itemBuilder: (context, index) => _VideoPlayerPage(
              key: ValueKey(widget.paths[index]),
              path: widget.paths[index],
              active: index == _page,
            ),
          ),
          Positioned(
            left: 4,
            top: 4,
            child: IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
          Positioned(
            right: 16,
            top: 10,
            child: _MediaCounter(
              current: _page + 1,
              total: widget.paths.length,
            ),
          ),
        ],
      ),
    ),
  );
}

class _VideoPlayerPage extends StatefulWidget {
  const _VideoPlayerPage({super.key, required this.path, required this.active});

  final String path;
  final bool active;

  @override
  State<_VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<_VideoPlayerPage> {
  late final VideoPlayerController _controller;
  late final Future<void> _initialize;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path));
    _initialize = _prepare();
  }

  Future<void> _prepare() async {
    await _controller.initialize();
    if (widget.active) await _controller.play();
  }

  @override
  void didUpdateWidget(covariant _VideoPlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active || !_controller.value.isInitialized) {
      return;
    }
    if (widget.active) {
      unawaited(_controller.play());
    } else {
      unawaited(_controller.pause());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: FutureBuilder<void>(
      future: _initialize,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text(
            '视频无法播放，系统可能缺少对应解码器',
            style: TextStyle(color: Colors.white),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const CircularProgressIndicator();
        }
        return ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: _controller,
          builder: (context, value, child) => Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                onTap: () =>
                    value.isPlaying ? _controller.pause() : _controller.play(),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
                ),
              ),
              if (!value.isPlaying)
                IgnorePointer(
                  child: Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      color: Colors.white.withValues(alpha: .9),
                      size: 64,
                    ),
                  ),
                ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 12,
                child: VideoProgressIndicator(
                  _controller,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Colors.white,
                    bufferedColor: Colors.white38,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _VoiceRecorderSheet extends StatefulWidget {
  const _VoiceRecorderSheet({required this.recorder, required this.path});

  final AudioRecorder recorder;
  final String path;

  @override
  State<_VoiceRecorderSheet> createState() => _VoiceRecorderSheetState();
}

class _VoiceRecorderSheetState extends State<_VoiceRecorderSheet> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _recording = false;
  bool _stopping = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await widget.recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: widget.path,
      );
      if (!mounted) return;
      setState(() => _recording = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _elapsed += const Duration(seconds: 1));
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _finish() async {
    if (!_recording || _stopping) return;
    setState(() => _stopping = true);
    _timer?.cancel();
    final path = await widget.recorder.stop();
    if (path == null) {
      final file = File(widget.path);
      if (await file.exists()) await file.delete();
    }
    if (mounted) Navigator.pop(context, path);
  }

  Future<void> _cancel() async {
    if (_stopping) return;
    setState(() => _stopping = true);
    _timer?.cancel();
    if (_recording) {
      await widget.recorder.cancel();
    } else {
      final file = File(widget.path);
      if (await file.exists()) await file.delete();
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_cancel());
    },
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _error == null ? Icons.mic_rounded : Icons.mic_off_rounded,
              size: 48,
              color: _error == null
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              _error == null ? '正在录音' : '无法开始录音',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              _error == null ? _formatMediaDuration(_elapsed) : '请稍后重试',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _stopping ? null : _cancel,
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _recording && !_stopping ? _finish : null,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('完成'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _AudioAttachmentTile extends StatefulWidget {
  const _AudioAttachmentTile({
    super.key,
    required this.path,
    required this.index,
    required this.readOnly,
    required this.onRemove,
  });

  final String path;
  final int index;
  final bool readOnly;
  final VoidCallback onRemove;

  @override
  State<_AudioAttachmentTile> createState() => _AudioAttachmentTileState();
}

class _AudioAttachmentTileState extends State<_AudioAttachmentTile> {
  late final AudioPlayer _player;
  late final Future<Duration?> _load;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _load = _player.setFilePath(widget.path);
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _toggle(PlayerState state) async {
    if (state.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    if (state.playing && state.processingState != ProcessingState.completed) {
      await _player.pause();
    } else {
      unawaited(_player.play());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<Duration?>(
        future: _load,
        builder: (context, durationSnapshot) {
          if (durationSnapshot.hasError) {
            return ListTile(
              leading: const Icon(Icons.error_outline_rounded),
              title: Text('语音 ${widget.index + 1}'),
              subtitle: const Text('音频无法播放'),
              trailing: widget.readOnly
                  ? null
                  : IconButton(
                      tooltip: '移除语音',
                      onPressed: widget.onRemove,
                      icon: const Icon(Icons.close_rounded),
                    ),
            );
          }
          if (durationSnapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 72,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final duration = durationSnapshot.data ?? Duration.zero;
          return StreamBuilder<PlayerState>(
            stream: _player.playerStateStream,
            initialData: _player.playerState,
            builder: (context, stateSnapshot) {
              final state = stateSnapshot.data ?? _player.playerState;
              return StreamBuilder<Duration>(
                stream: _player.positionStream,
                initialData: _player.position,
                builder: (context, positionSnapshot) {
                  final position = positionSnapshot.data ?? Duration.zero;
                  final maximum = duration.inMilliseconds.toDouble();
                  final value = position.inMilliseconds
                      .clamp(0, duration.inMilliseconds)
                      .toDouble();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
                    child: Row(
                      children: [
                        IconButton.filledTonal(
                          tooltip:
                              state.processingState == ProcessingState.completed
                              ? '重新播放'
                              : (state.playing ? '暂停' : '播放'),
                          onPressed: () => _toggle(state),
                          icon: Icon(
                            state.processingState == ProcessingState.completed
                                ? Icons.replay_rounded
                                : state.playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '语音 ${widget.index + 1}',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              Slider(
                                value: maximum == 0 ? 0 : value,
                                max: maximum == 0 ? 1 : maximum,
                                onChanged: maximum == 0
                                    ? null
                                    : (value) => _player.seek(
                                        Duration(milliseconds: value.round()),
                                      ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${_formatMediaDuration(position > duration ? duration : position)} / ${_formatMediaDuration(duration)}',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        if (!widget.readOnly)
                          IconButton(
                            tooltip: '移除语音',
                            onPressed: widget.onRemove,
                            icon: const Icon(Icons.close_rounded),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

String _formatMediaDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

class _TagPickerSheet extends StatefulWidget {
  const _TagPickerSheet({
    required this.app,
    required this.initialSelected,
    required this.noteTitle,
    required this.noteContent,
  });

  final AppController app;
  final List<String> initialSelected;
  final String noteTitle;
  final String noteContent;

  @override
  State<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<_TagPickerSheet> {
  final _tagController = TextEditingController();
  final _tagLengthLimiter = LengthLimitingTextInputFormatter(maxTagNameLength);
  late final List<String> _availableTags;
  late final List<String> _selected;
  bool _addingTag = false;
  bool _generatingAiTags = false;

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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(validationMessage)));
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

  Future<void> _generateAiTags() async {
    if (_generatingAiTags) return;
    if (widget.noteTitle.trim().isEmpty && widget.noteContent.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先输入笔记标题或内容')));
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _generatingAiTags = true);
    try {
      final generated = await AiService(widget.app.aiConfig)
          .generateTags(title: widget.noteTitle, content: widget.noteContent);
      if (!mounted) return;
      final tags = generated
          .map(normalizeTagName)
          .where((tag) => tag.isNotEmpty && tag.length <= maxTagNameLength)
          .toSet()
          .toList();
      if (tags.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('AI 没有生成可用标签')));
        return;
      }

      final chosen = await showDialog<List<String>>(
        context: context,
        builder: (context) => _AiTagSelectionDialog(tags: tags),
      );
      if (!mounted || chosen == null || chosen.isEmpty) return;

      for (final tag in chosen) {
        if (!_availableTags.contains(tag)) {
          await widget.app.addTag(tag);
          if (!mounted) return;
          _availableTags.add(tag);
        }
        if (!_selected.contains(tag)) _selected.add(tag);
      }
      setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('AI 标签生成失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _generatingAiTags = false);
    }
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
              if (widget.app.aiConfig.isComplete) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _generatingAiTags ? null : _generateAiTags,
                  icon: _generatingAiTags
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_rounded),
                  label: Text(_generatingAiTags ? '正在生成' : 'AI标签'),
                ),
              ],
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

class _AiTagSelectionDialog extends StatefulWidget {
  const _AiTagSelectionDialog({required this.tags});

  final List<String> tags;

  @override
  State<_AiTagSelectionDialog> createState() => _AiTagSelectionDialogState();
}

class _AiTagSelectionDialogState extends State<_AiTagSelectionDialog> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.tags.toSet();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('选择 AI 生成的标签'),
    content: SingleChildScrollView(
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: widget.tags
            .map(
              (tag) => FilterChip(
                label: Text(tag),
                selected: _selected.contains(tag),
                onSelected: (selected) => setState(() {
                  selected ? _selected.add(tag) : _selected.remove(tag);
                }),
              ),
            )
            .toList(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _selected.isEmpty
            ? null
            : () => Navigator.pop(context, _selected.toList()),
        child: const Text('使用所选标签'),
      ),
    ],
  );
}

enum _NoteShareExportAction { share, exportMarkdown }

enum _VoiceAction { record, import }

enum _AttachmentAction { image, video, voice }

class _ShareExportMenu extends StatelessWidget {
  const _ShareExportMenu({required this.onSelected});

  final ValueChanged<_NoteShareExportAction> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<_NoteShareExportAction>(
    tooltip: '分享与导出',
    icon: const Icon(Icons.ios_share_rounded),
    onSelected: onSelected,
    itemBuilder: (context) => const [
      PopupMenuItem(
        value: _NoteShareExportAction.share,
        child: Row(
          children: [
            Icon(Icons.share_outlined),
            SizedBox(width: 12),
            Text('分享'),
          ],
        ),
      ),
      PopupMenuItem(
        value: _NoteShareExportAction.exportMarkdown,
        child: Row(
          children: [
            Icon(Icons.download_outlined),
            SizedBox(width: 12),
            Text('导出为 .md'),
          ],
        ),
      ),
    ],
  );
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({
    required this.readOnly,
    required this.favorite,
    required this.saveLabel,
    required this.markdownPreview,
    required this.onMarkdownPreview,
    required this.onFavorite,
    required this.onTags,
    required this.onAdd,
    required this.onShareExport,
    required this.onDelete,
  });
  final bool readOnly;
  final bool favorite;
  final String saveLabel;
  final bool markdownPreview;
  final VoidCallback onMarkdownPreview;
  final VoidCallback onFavorite;
  final VoidCallback onTags;
  final VoidCallback onAdd;
  final ValueChanged<_NoteShareExportAction> onShareExport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final desktop = DesktopEnvironment.isDesktopOf(context);
    return Container(
      height: desktop ? 56 : 64,
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
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          if (!readOnly && desktop) ...[
            TextButton.icon(
              onPressed: onTags,
              icon: const Icon(Icons.label_outline_rounded, size: 18),
              label: const Text('标签'),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('添加'),
            ),
            const SizedBox(width: 4),
          ],
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
          _ShareExportMenu(onSelected: onShareExport),
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
}

class _EditorBottomBar extends StatelessWidget {
  const _EditorBottomBar({
    super.key,
    required this.onTags,
    required this.onAdd,
  });

  final VoidCallback onTags;
  final VoidCallback onAdd;

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
              icon: Icons.add_circle_outline_rounded,
              label: '添加',
              onPressed: onAdd,
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
    padding: const EdgeInsets.only(right: 2),
    child: TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6),
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
