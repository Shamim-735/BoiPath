import 'package:dio/dio.dart';

Future<String?> existingPdf(String id) async => null;
Future<void> removePdf(String id) async {}
Future<void> savePdf(Dio http, String id, String url, int? size,
    CancelToken token, void Function(int, int) progress) async {
  throw UnsupportedError('Browser downloads are handled by the official site.');
}
