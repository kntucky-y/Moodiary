import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

ImageProvider<Object>? avatarImageProvider(String? source) {
  if (source == null || source.trim().isEmpty) {
    return null;
  }

  final trimmed = source.trim();
  if (trimmed.startsWith('data:image/')) {
    final commaIndex = trimmed.indexOf(',');
    if (commaIndex == -1) return null;
    final base64Part = trimmed.substring(commaIndex + 1);
    try {
      final bytes = base64Decode(base64Part);
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  return NetworkImage(trimmed);
}

String? dataUrlFromImageBytes(Uint8List bytes, {required String mimeType}) {
  if (bytes.isEmpty) return null;
  final encoded = base64Encode(bytes);
  return 'data:$mimeType;base64,$encoded';
}
