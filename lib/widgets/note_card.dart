import 'package:flutter/material.dart';

import '../models/note.dart';

class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    this.selected = false,
    this.onLongPress,
    this.trailing,
  });

  final Note note;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final preview = note.content.trim().isNotEmpty
        ? note.content.trim()
        : note.checklist
              .map((item) => item.text)
              .where((text) => text.isNotEmpty)
              .join(' · ');
    final title = note.title.trim().isEmpty
        ? (preview.isEmpty ? '无标题笔记' : preview.split('\n').first)
        : note.title.trim();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: selected
            ? colors.primaryContainer.withValues(alpha: 0.68)
            : colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? colors.primary : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: selected
            ? null
            : const [
                BoxShadow(
                  color: Color(0x0A111827),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 17, 14, 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: selected
                            ? colors.primary
                            : colors.primaryContainer,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        selected ? Icons.check_rounded : Icons.notes_rounded,
                        size: 19,
                        color: selected ? colors.onPrimary : colors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (note.isFavorite)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.star_rounded,
                          size: 20,
                          color: colors.tertiary,
                        ),
                      ),
                    ?trailing,
                  ],
                ),
                if (preview.isNotEmpty && note.title.trim().isNotEmpty) ...[
                  const SizedBox(height: 11),
                  Text(
                    preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.45,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: note.tags.take(3).map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primaryContainer.withValues(
                                alpha: 0.55,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              tag,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    if (note.checklist.isNotEmpty) ...[
                      Icon(
                        Icons.checklist_rounded,
                        size: 16,
                        color: colors.outline,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${note.checklist.where((item) => item.isChecked).length}/${note.checklist.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.outline,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    if (note.imagePaths.isNotEmpty) ...[
                      Icon(
                        Icons.image_outlined,
                        size: 15,
                        color: colors.outline,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${note.imagePaths.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.outline,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      _formatDate(note.updatedAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.outline,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final value = DateTime(date.year, date.month, date.day);
    final difference = today.difference(value).inDays;
    if (difference == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    if (difference == 1) return '昨天';
    return '${date.month}月${date.day}日';
  }
}
