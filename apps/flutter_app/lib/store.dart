import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'book.dart';
import 'local_files.dart';
import 'theme_profile.dart';

const apiBase = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000');
const publicBase = String.fromEnvironment('PUBLIC_APP_URL');
final storeProvider = ChangeNotifierProvider<LibraryStore>((ref) => LibraryStore()..initialize());

typedef PdfSaver = Future<void> Function(Dio http, String id, String url, int? size,
    CancelToken token, void Function(int, int) progress);

class LibraryStore extends ChangeNotifier {
  static const _catalogCacheKey = 'catalog-v3';
  LibraryStore({this.findPdf = existingPdf, this.saveFile = savePdf});

  final Future<String?> Function(String) findPdf;
  final PdfSaver saveFile;
  final api = Dio(BaseOptions(baseUrl: apiBase,
    connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 15)));
  final downloadClient = Dio(BaseOptions(connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 40)));
  List<Book> books = [];
  final saved = <String, Book>{};
  final paths = <String, String>{};
  final active = <String, CancelToken>{};
  final progress = <String, double?>{};
  final failures = <String>{};
  final pages = <String, int>{};
  final bookmarks = <String, List<int>>{};
  SharedPreferences? _prefs;
  bool busy = true;
  var _refreshing = false;
  bool cached = false;
  bool bangla = false;
  bool dark = true;
  ThemeProfile themeProfile = ThemeProfile.violet;
  bool firstRun = false;

  bool get ready => _prefs != null;
  Book? byId(String id) {
    for (final book in books) {
      if (book.id == id) return book;
    }
    return saved[id];
  }

  Future<void> initialize() async {
    final prefs = _prefs = await SharedPreferences.getInstance();
    bangla = prefs.getBool('bangla') ?? false;
    dark = prefs.getBool('dark') ?? true
    themeProfile = ThemeProfile.restore(prefs.getString('themeProfile'));
    firstRun = !(prefs.getBool('onboarded') ?? false);
    pages.addAll(Map<String, int>.from(jsonDecode(prefs.getString('pages') ?? '{}') as Map));
    final stored = jsonDecode(prefs.getString('bookmarks') ?? '{}') as Map;
    for (final entry in stored.entries) {
      bookmarks[entry.key as String] = List<int>.from(entry.value as List);
    }
    final retained = _decode(prefs.getString('retained') ?? '[]');
    for (final book in retained) {
      saved[book.id] = book;
      final path = await findPdf(book.id);
      if (path != null) paths[book.id] = path;
    }
    final snapshot = prefs.getString(_catalogCacheKey);
    books = _decode(snapshot ?? await rootBundle.loadString('assets/starter_catalog.json'));
    cached = true;
    notifyListeners();
    await refresh();
  }

  List<Book> _decode(String source) => (jsonDecode(source) as List)
      .map((item) => Book(Map<String, dynamic>.from(item as Map))).toList();

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    busy = true;
    notifyListeners();
    try {
      final result = <String, Book>{};
      const batchSize = 100;
      const maxBatches = 200;
      for (var page = 0; page < maxBatches; page++) {
        final offset = page * batchSize;
        final response = await api.get<Map<String, dynamic>>('/api/v1/books',
            queryParameters: {'limit': batchSize, 'offset': offset});
        final items = response.data!['items'] as List;
        for (final item in items) {
          final book = Book(Map<String, dynamic>.from(item as Map));
          result[book.id] = book;
        }
        final total = response.data!['total'] as int;
        if (total > batchSize * maxBatches) throw StateError('Catalog exceeds local cache capacity');
        if (offset + items.length >= total || items.isEmpty) break;
      }
      books = result.values.toList();
      await _prefs?.setString(_catalogCacheKey, jsonEncode(books.map((book) => book.data).toList()));
      cached = false;
    } on DioException {
      cached = true;
    } on StateError {
      cached = true;
    } finally {
      _refreshing = false;
      busy = false;
      notifyListeners();
    }
  }

  Future<void> setLanguage(bool value) async {
    bangla = value;
    notifyListeners();
    await _prefs?.setBool('bangla', value);
  }

  Future<void> setDark(bool value) async {
    dark = value;
    notifyListeners();
    await _prefs?.setBool('dark', value);
  }

  Future<void> setThemeProfile(ThemeProfile value) async {
    themeProfile = value;
    notifyListeners();
    await _prefs?.setString('themeProfile', value.name);
  }

  Future<void> finishOnboarding() async {
    firstRun = false;
    notifyListeners();
    await _prefs?.setBool('onboarded', true);
  }

  Future<void> retain(Book book) async {
    saved[book.id] = book;
    await _prefs?.setString('retained', jsonEncode(saved.values.map((item) => item.data).toList()));
  }

  Future<void> setPage(Book book, int number) async {
    if (pages[book.id] == number) return;
    pages.remove(book.id);
    pages[book.id] = number;
    notifyListeners();
    if (!book.imported && !saved.containsKey(book.id)) await retain(book);
    await _prefs?.setString('pages', jsonEncode(pages));
  }

  Future<void> toggleBookmark(Book book, int number) async {
    final list = bookmarks.putIfAbsent(book.id, () => []);
    if (!list.remove(number)) list.add(number);
    list.sort();
    notifyListeners();
    if (!book.imported && !saved.containsKey(book.id)) await retain(book);
    await _prefs?.setString('bookmarks', jsonEncode(bookmarks));
  }

  String? storedText(String key) => _prefs?.getString(key);
  Future<void> setText(String key, String value) async {
    await _prefs?.setString(key, value);
  }

  Future<void> download(Book book) async {
    final url = book.offlineDownloadUrl;
    if (kIsWeb || active.containsKey(book.id) || paths.containsKey(book.id) || url == null) return;
    final token = active[book.id] = CancelToken();
    failures.remove(book.id);
    progress[book.id] = null;
    notifyListeners();
    try {
      await retain(book);
      await saveFile(downloadClient, book.id, url, url == book.pdf ? book.fileSize : null, token, (received, total) {
        progress[book.id] = total > 0 ? received / total : null;
        notifyListeners();
      });
      final path = await findPdf(book.id);
      if (path != null) paths[book.id] = path;
    } catch (_) {
      if (!token.isCancelled || token.cancelError?.error != 'cancel') failures.add(book.id);
    } finally {
      active.remove(book.id);
      progress.remove(book.id);
      notifyListeners();
    }
  }

  void cancel(String id) => active[id]?.cancel('cancel');

  Future<void> deleteDownload(String id) async {
    await removePdf(id);
    paths.remove(id);
    notifyListeners();
  }
}
