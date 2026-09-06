import 'dart:io';

/// Small Linux integration helpers kept out of widgets and platform branches.
class LinuxSystemService {
  const LinuxSystemService._();

  static const recordingCommands = ['ffmpeg', 'parecord', 'pactl'];

  static Future<List<String>> missingRecordingDependencies() async {
    if (!Platform.isLinux) return const [];
    final missing = <String>[];
    for (final command in recordingCommands) {
      try {
        final result = await Process.run('which', [command]);
        if (result.exitCode != 0) missing.add(command);
      } catch (_) {
        missing.add(command);
      }
    }
    return missing;
  }
}
