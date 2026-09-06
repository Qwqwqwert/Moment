import '../models/achievement.dart';

abstract interface class AchievementRepository {
  Future<List<Achievement>> getAchievements();
  Future<Achievement?> recordNoteCreated(String noteId);
  Future<Achievement?> recordTodoCompleted(String todoId);
}
