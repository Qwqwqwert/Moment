const maxTagNameLength = 20;

String normalizeTagName(String value) => value.trim();

String? validateNewTagName(String value, Iterable<String> existingTags) {
  final normalized = normalizeTagName(value);
  if (normalized.isEmpty) return null;
  if (normalized.length > maxTagNameLength) {
    return '标签名不能超过20个字符';
  }
  if (existingTags.contains(normalized)) return '标签已存在';
  return null;
}
