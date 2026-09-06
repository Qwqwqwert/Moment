enum AchievementKind { notesCreated, todosCompleted }

class Achievement {
  const Achievement({
    required this.id,
    required this.kind,
    required this.milestone,
    required this.unlockedAt,
  });

  final String id;
  final AchievementKind kind;
  final int milestone;
  final DateTime unlockedAt;

  String get title => switch ((kind, milestone)) {
    (AchievementKind.notesCreated, 10) => '灵感初绽',
    (AchievementKind.notesCreated, 100) => '百篇印记',
    (AchievementKind.notesCreated, 250) => '积跬成章',
    (AchievementKind.notesCreated, 1000) => '千页时光',
    (AchievementKind.todosCompleted, 10) => '初见成效',
    (AchievementKind.todosCompleted, 100) => '百事皆成',
    (AchievementKind.todosCompleted, 250) => '步履不停',
    (AchievementKind.todosCompleted, 1000) => '千项达成',
    _ => '新的里程碑',
  };

  String get description => switch (kind) {
    AchievementKind.notesCreated => '已创建并保存 $milestone 条笔记',
    AchievementKind.todosCompleted => '已完成 $milestone 项待办',
  };
}
