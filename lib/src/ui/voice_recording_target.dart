import '../data/leccy_store.dart';

Future<String> buildVoiceRecordingPath(String extension) async {
  return 'leccy_voice_${DateTime.now().microsecondsSinceEpoch}.$extension';
}

Future<String> persistVoiceRecording({
  required LeccyStore repository,
  required String path,
  required String extension,
}) async {
  return path;
}
