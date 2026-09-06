import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../services/platform_storage.dart';

class AttachmentStore {
  AttachmentStore({ImagePicker? picker, this.rootDirectory})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;
  final Directory? rootDirectory;

  Future<Directory> _root() async =>
      rootDirectory ?? await momentDataDirectory();

  Future<List<String>> pickAndStore(String noteId) async {
    final picked = await _picker.pickMultiImage();
    return _storeFiles(noteId, 'images', picked);
  }

  Future<String?> pickVideoAndStore(String noteId) async {
    final XFile? picked;
    if (Platform.isWindows) {
      final result = await FilePicker.pickFile(type: FileType.video);
      picked = result?.xFile;
    } else {
      picked = await _picker.pickVideo(source: ImageSource.gallery);
    }
    if (picked == null) return null;
    final stored = await _storeFiles(noteId, 'videos', [picked]);
    return stored.single;
  }

  Future<String?> importAudioAndStore(String noteId) async {
    final picked = await FilePicker.pickFile(type: FileType.audio);
    if (picked == null) return null;
    final extension = picked.extension == null
        ? '.m4a'
        : '.${picked.extension}';
    final target = await createAudioRecordingPath(noteId, extension: extension);
    await picked.xFile.saveTo(target);
    return target;
  }

  Future<String> createAudioRecordingPath(
    String noteId, {
    String extension = '.m4a',
  }) async {
    final root = await _root();
    final directory = Directory(p.join(root.path, 'audio', noteId));
    await directory.create(recursive: true);
    return p.join(
      directory.path,
      '${DateTime.now().microsecondsSinceEpoch}$extension',
    );
  }

  Future<RecoveredAttachments> recoverLost(String noteId) async {
    if (!Platform.isAndroid) return const RecoveredAttachments();
    final response = await _picker.retrieveLostData();
    final files = response.files ?? [if (response.file != null) response.file!];
    if (response.isEmpty || files.isEmpty) {
      return const RecoveredAttachments();
    }
    if (response.type == RetrieveType.video) {
      return RecoveredAttachments(
        videos: await _storeFiles(noteId, 'videos', files),
      );
    }
    return RecoveredAttachments(
      images: await _storeFiles(noteId, 'images', files),
    );
  }

  Future<List<String>> _storeFiles(
    String noteId,
    String kind,
    Iterable<XFile> files,
  ) async {
    final root = await _root();
    final directory = Directory(p.join(root.path, kind, noteId));
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

class RecoveredAttachments {
  const RecoveredAttachments({this.images = const [], this.videos = const []});

  final List<String> images;
  final List<String> videos;
}
