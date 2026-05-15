import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/leccy_store.dart';

Future<String> buildVoiceRecordingPath(String extension) async {
  final temp = await getTemporaryDirectory();
  final cleanExtension = extension.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
  return p.join(
    temp.path,
    'leccy_voice_${DateTime.now().microsecondsSinceEpoch}.${cleanExtension.isEmpty ? 'wav' : cleanExtension}',
  );
}

Future<String> persistVoiceRecording({
  required LeccyStore repository,
  required String path,
  required String extension,
}) async {
  final bytes = await File(path).readAsBytes();
  return repository.saveAttachment(
    bytes: bytes,
    extension: extension,
    mediaType: 'voices',
  );
}
