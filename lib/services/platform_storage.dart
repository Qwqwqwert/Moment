import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves Moment's durable application data location.
///
/// Windows deliberately stores data outside the portable ZIP so replacing or
/// moving the program directory cannot orphan the user's notes.
Future<Directory> momentDataDirectory() async {
  if (Platform.isWindows) {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.trim().isNotEmpty) {
      return Directory(p.join(localAppData, 'Moment'));
    }
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'Moment'));
  }
  if (Platform.isLinux) {
    final xdgDataHome = Platform.environment['XDG_DATA_HOME'];
    if (xdgDataHome != null && p.isAbsolute(xdgDataHome)) {
      return Directory(p.join(xdgDataHome, 'Moment'));
    }
    final home = Platform.environment['HOME'];
    if (home != null && home.trim().isNotEmpty) {
      return Directory(p.join(home, '.local', 'share', 'Moment'));
    }
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'Moment'));
  }
  final documents = await getApplicationDocumentsDirectory();
  return Directory(p.join(documents.path, 'moment'));
}
