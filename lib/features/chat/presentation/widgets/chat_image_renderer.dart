import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

ImageProvider<Object>? resolveChatImageProvider(String source) {
  final trimmed = source.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  final scheme = uri?.scheme.toLowerCase();
  if (scheme == 'http' || scheme == 'https') {
    return NetworkImage(trimmed);
  }
  if (scheme == 'file' && uri != null) {
    return FileImage(File.fromUri(uri));
  }
  if (trimmed.startsWith('/')) {
    return FileImage(File(trimmed));
  }

  final bytes = _decodeBase64ImageData(trimmed);
  if (bytes != null) {
    return MemoryImage(bytes);
  }

  return NetworkImage(trimmed);
}

Uint8List? _decodeBase64ImageData(String source) {
  if (!source.startsWith('data:image/')) return null;
  final splitAt = source.indexOf(',');
  if (splitAt <= 0) return null;

  final metadata = source.substring(0, splitAt);
  if (!metadata.contains(';base64')) return null;

  try {
    return base64Decode(source.substring(splitAt + 1));
  } catch (_) {
    return null;
  }
}
