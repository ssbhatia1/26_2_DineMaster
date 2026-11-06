import 'dart:io' as io;
import 'package:video_player/video_player.dart';

VideoPlayerController? createVideoControllerFromPath(String path) {
  final file = io.File(path);
  if (!file.existsSync()) return null;
  return VideoPlayerController.file(file);
}
