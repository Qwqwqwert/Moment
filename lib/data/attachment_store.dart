import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AttachmentStore {
  AttachmentStore({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<List<String>> pickAndStore(
    String noteId, {
    required int remaining,
  }) async {
    if (remaining <= 0) return [];
    final picked = await _picker.pickMultiImage(limit: remaining);
    return _storeFiles(noteId, picked.take(remaining));
  }

  Future<List<String>> recoverLost(String noteId) async {
    final response = await _picker.retrieveLostData();
    if (response.isEmpty || response.files == null) return [];
    return _storeFiles(noteId, response.files!);
  }

  Future<List<String>> _storeFiles(String noteId, Iterable<XFile> files) async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      p.join(documents.path, 'moment', 'images', noteId),
    );
    await directory.create(recursive: true);
    final result = <String>[];
    for (final source in files) {
      final extension = p.extension(source.path).isEmpty
          ? '.jpg'
          : p.extension(source.path);
      final target = p.join(
        directory.path,
        '${DateTime.now().microsecondsSinceEpoch}$extension',
      );
      await File(source.path).copy(target);
      result.add(target);
    }
    return result;
  }

  Future<void> deleteFiles(Iterable<String> paths) async {
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }
}
