import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moment/data/attachment_store.dart';
import 'package:moment/data/note_repository.dart';
import 'package:moment/models/note.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory sandbox;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('moment_windows_test_');
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test(
    'injected FFI database persists notes and reminder deliveries',
    () async {
      final path = p.join(sandbox.path, 'data', 'moment.sqlite');
      final repository = SqliteNoteRepository(
        databaseFactoryOverride: databaseFactoryFfiNoIsolate,
        databasePath: path,
      );
      await repository.initialize();

      final createdAt = DateTime(2026, 9, 5, 10);
      final note = Note(
        id: 'windows-note',
        title: 'Windows',
        content: 'portable data',
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      await repository.saveNote(note);
      expect((await repository.getNote(note.id))?.content, 'portable data');

      final dueAt = DateTime(2026, 9, 5, 10, 30);
      expect(
        await repository.wasWindowsReminderDelivered('todo-1', dueAt),
        isFalse,
      );
      await repository.markWindowsReminderDelivered('todo-1', dueAt);
      expect(
        await repository.wasWindowsReminderDelivered('todo-1', dueAt),
        isTrue,
      );
      expect(
        await repository.wasWindowsReminderDelivered(
          'todo-1',
          dueAt.add(const Duration(minutes: 1)),
        ),
        isFalse,
      );
      await repository.close();
    },
  );

  test(
    'attachment root can be injected outside the portable directory',
    () async {
      final store = AttachmentStore(rootDirectory: sandbox);
      final path = await store.createAudioRecordingPath('note-1');
      expect(p.isWithin(sandbox.path, path), isTrue);
      expect(p.extension(path), '.m4a');
    },
  );
}
