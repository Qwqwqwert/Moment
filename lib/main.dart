import 'package:flutter/material.dart';

import 'data/attachment_store.dart';
import 'data/note_repository.dart';
import 'screens/home_shell.dart';
import 'services/todo_reminder_service.dart';
import 'state/app_controller.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final todoReminderService = TodoReminderService();
  await todoReminderService.initialize();
  runApp(
    MomentApp(
      repository: SqliteNoteRepository(),
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

class _MomentAppState extends State<MomentApp> {
  late final AppController controller;

  @override
  void initState() {
    super.initState();
    controller = AppController(
      repository: widget.repository,
      attachmentStore: widget.attachmentStore ?? AttachmentStore(),
      todoReminderService: widget.todoReminderService,
    )..initialize();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => AppScope(
      controller: controller,
      child: MaterialApp(
        title: 'Moment',
        debugShowCheckedModeBanner: false,
        theme: buildMomentTheme(),
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
