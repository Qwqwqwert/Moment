import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

import 'data/attachment_store.dart';
import 'data/note_repository.dart';
import 'screens/home_shell.dart';
import 'services/todo_reminder_service.dart';
import 'services/platform_storage.dart';
import 'state/app_controller.dart';
import 'theme/app_theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  SqliteNoteRepository repository;
  AttachmentStore attachmentStore;
  if (Platform.isWindows) {
    await WindowsSingleInstance.ensureSingleInstance(
      args,
      'moment_desktop_single_instance',
    );
    sqfliteFfiInit();
    final dataDirectory = await momentDataDirectory();
    await dataDirectory.create(recursive: true);
    repository = SqliteNoteRepository(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: p.join(dataDirectory.path, 'moment.sqlite'),
    );
    attachmentStore = AttachmentStore(rootDirectory: dataDirectory);
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(const Size(900, 600));
    await windowManager.setSize(const Size(1200, 760));
    await windowManager.center();
    await windowManager.setTitle('Moment');
    await windowManager.setPreventClose(true);
  } else {
    repository = SqliteNoteRepository();
    attachmentStore = AttachmentStore();
  }
  final todoReminderService = TodoReminderService();
  await todoReminderService.initialize();
  runApp(
    MomentApp(
      repository: repository,
      attachmentStore: attachmentStore,
      todoReminderService: todoReminderService,
    ),
  );
}

class MomentApp extends StatefulWidget {
  const MomentApp({
    super.key,
    required this.repository,
    this.attachmentStore,
    this.todoReminderService,
  });

  final NoteRepository repository;
  final AttachmentStore? attachmentStore;
  final TodoReminderService? todoReminderService;

  @override
  State<MomentApp> createState() => _MomentAppState();
}

class _MomentAppState extends State<MomentApp> with WindowListener {
  late final AppController controller;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    controller = AppController(
      repository: widget.repository,
      attachmentStore: widget.attachmentStore ?? AttachmentStore(),
      todoReminderService: widget.todoReminderService,
    )..initialize();
    if (Platform.isWindows) windowManager.addListener(this);
  }

  @override
  void dispose() {
    if (Platform.isWindows) windowManager.removeListener(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    if (_closing) return;
    _closing = true;
    await controller.shutdown();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onWindowFocus() {
    final reminderService = controller.todoReminderService;
    if (reminderService != null) {
      unawaited(reminderService.resume(controller.todos));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => AppScope(
      controller: controller,
      child: MaterialApp(
        title: 'Moment',
        debugShowCheckedModeBanner: false,
        theme: buildMomentTheme(
          desktop: defaultTargetPlatform == TargetPlatform.windows,
        ),
        builder: (context, child) => Actions(
          actions: {
            EditableTextTapOutsideIntent:
                CallbackAction<EditableTextTapOutsideIntent>(
                  onInvoke: (intent) {
                    intent.focusNode.unfocus();
                    return null;
                  },
                ),
          },
          child: child!,
        ),
        home: controller.initialized
            ? const HomeShell()
            : const _StartupScreen(),
      ),
    ),
  );
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) {
    final error = AppScope.of(context).initializationError;
    return Scaffold(
      body: Center(
        child: error == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Text('无法打开本地数据：$error', textAlign: TextAlign.center),
              ),
      ),
    );
  }
}
