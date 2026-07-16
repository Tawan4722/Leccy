import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

ImageProvider coverImageProvider(String path) {
  if (path.startsWith('data:')) {
    final comma = path.indexOf(',');
    if (comma != -1) {
      final bytes = base64Decode(path.substring(comma + 1));
      return MemoryImage(bytes);
    }
  }
  return FileImage(File(path));
}
