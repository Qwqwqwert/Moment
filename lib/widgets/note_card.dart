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
    final hasTitle = note.title.trim().isNotEmpty;
    final contentLines = note.content.trim().isNotEmpty
        ? note.content
              .trim()
              .split(RegExp(r'\r?\n'))
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList()
        : const <String>[];
    final primaryText = hasTitle
        ? note.title.trim()
        : (contentLines.isEmpty ? '无标题笔记' : contentLines.first);
    final secondaryText = hasTitle
        ? (contentLines.isEmpty ? null : contentLines.first)
        : (contentLines.length > 1 ? contentLines[1] : null);
    final hasSecondaryText = secondaryText != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 10),
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
            padding: EdgeInsets.fromLTRB(
              16,
              hasSecondaryText ? 12 : 10,
              14,
              hasSecondaryText ? 11 : 9,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        primaryText,
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
                if (hasSecondaryText) ...[
                  const SizedBox(height: 4),
                  Text(
                    secondaryText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.3,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
                SizedBox(height: hasSecondaryText ? 10 : 7),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: note.tags.take(3).map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
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
                    if (note.videoPaths.isNotEmpty) ...[
                      Icon(
                        Icons.videocam_outlined,
                        size: 16,
                        color: colors.outline,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${note.videoPaths.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.outline,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    if (note.audioPaths.isNotEmpty) ...[
                      Icon(
                        Icons.mic_none_rounded,
                        size: 16,
                        color: colors.outline,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${note.audioPaths.length}',
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
