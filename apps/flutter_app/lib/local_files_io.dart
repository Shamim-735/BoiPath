import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

Future<File> _pdf(String id) async {
  if (!RegExp(r'^[a-zA-Z0-9-]{1,36}$').hasMatch(id)) {
    throw const FormatException('Invalid book identifier');
  }
  final directory = await getApplicationSupportDirectory();
  final books = await Directory('${directory.path}/books').create(recursive: true);
  return File('${books.path}/$id.pdf');
}

Future<String?> existingPdf(String id) async {
  final file = await _pdf(id);
  return await file.exists() ? file.path : null;
}

Future<void> removePdf(String id) async {
  final file = await _pdf(id);
  if (await file.exists()) await file.delete();
}

Future<void> savePdf(Dio http, String id, String url, int? size,
    CancelToken token, void Function(int, int) progress) async {
  final file = await _pdf(id);
  final partial = File('${file.path}.partial');
  const maximum = 300 * 1024 * 1024;
  try {
    if (size != null && size > maximum) throw const FormatException('PDF too large');
    final response = await http.download(url, partial.path, cancelToken: token,
        options: Options(followRedirects: false, headers: {'Accept-Encoding': 'identity'}),
        onReceiveProgress: (received, total) {
          progress(received, total);
          if (received > maximum || total > maximum) token.cancel('PDF too large');
        });
    final length = await partial.length();
    final expected = size ?? int.tryParse(response.headers.value('content-length') ?? '');
    if ((expected != null && length != expected) || length < 10 || length > maximum) {
      throw const FormatException('Incomplete PDF');
    }
    final reader = await partial.open();
    try {
      final header = String.fromCharCodes(await reader.read(5));
      await reader.setPosition(math.max(0, length - 2048));
      final trailer = String.fromCharCodes(await reader.read(math.min(length, 2048)));
      if (header != '%PDF-' || !trailer.contains('%%EOF')) {
        throw const FormatException('Invalid PDF');
      }
    } finally {
      await reader.close();
    }
    if (token.isCancelled) return;
    await partial.rename(file.path);
  } finally {
    if (await partial.exists()) await partial.delete();
  }
}
