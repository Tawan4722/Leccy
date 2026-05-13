import 'dart:io';

import 'package:flutter/material.dart';

ImageProvider coverImageProvider(String path) => FileImage(File(path));
