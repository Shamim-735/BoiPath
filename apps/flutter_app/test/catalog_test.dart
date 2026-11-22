import 'package:boipath/book.dart';
import 'package:boipath/book_artwork.dart';
import 'package:boipath/library_navigation.dart';
import 'package:boipath/main.dart';
import 'package:boipath/store.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const entry = Book({
  'id': 'example',
  'official_title': 'পরীক্ষার গণিত',
  'class_id': 1,
  'academic_year': 2026,
  'language_version': 'bn',
  'subject_id': 'mathematics',
  'verification_status': 'pending',
  'curriculum_track': 'Primary',
  'source_url': 'https://nctb.gov.bd/example',
  'pdf_url': 'https://nctb.gov.bd/hidden-fixture.pdf',
});

LibraryStore offlineStore() {
  final store = LibraryStore(findPdf: (_) async => null);
  store.api.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
    handler.reject(DioException(requestOptions: request, type: DioExceptionType.connectionError));
  }));
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('normalizes Bangla digits, matches spelling variants, and keeps pending PDF URLs private', () {
    expect(entry.matches('গণিত ২০২৬'), isTrue);
    expect(entry.matches('mathematicz'), isTrue);
    expect(entry.matches('ইংরেজি ২০২৬'), isFalse);
    expect(entry.pdf, isNull);
  });

  test('book-specific source links can download without enabling in-app reading', () {
    const link = 'https://drive.egovcloud.gov.bd/index.php/s/BookFixture/download';
    final book = Book({...entry.data, 'source_download_urls': [link, 'https://example.test/other.pdf']});
    expect(book.downloadUrl, link);
    expect(book.offlineDownloadUrl, link);
    expect(book.pdf, isNull);
    final unavailable = Book({...book.data, 'verification_status': 'unavailable'});
    expect(unavailable.downloadUrl, isNull);
  });

  test('a shared textbook belongs to each class in its range', () {
    final shared = Book({...entry.data, 'class_id': 9, 'class_end_id': 10});
    expect(shared.coversLevel(8), isFalse);
    expect(shared.coversLevel(9), isTrue);
    expect(shared.coversLevel(10), isTrue);
    expect(shared.coversLevel(11), isFalse);
    expect(shared.matches('Class 10'), isTrue);
    expect(entry.coversLevel(1), isTrue);
    expect(entry.coversLevel(2), isFalse);
  });

  testWidgets('book artwork draws locally at card and list sizes', (tester) async {
    final book = Book({
      ...entry.data,
      'cover_url': 'https://example.test/old-cover.png',
      'source_download_urls': ['https://drive.google.com/uc?export=download&id=Example'],
    });
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: Column(children: [
        SizedBox(width: 200, height: 140, child: BookArtwork(book: book)),
        SizedBox(width: 39, height: 49, child: BookArtwork(book: book, compact: true)),
      ])),
    ));
    expect(find.byIcon(Icons.calculate_rounded), findsNWidgets(2));
    expect(find.byType(Image), findsAtLeastNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  test('restores local bookmarks and page after creating a new store', () async {
    SharedPreferences.setMockInitialValues({'onboarded': true});
    final first = offlineStore();
    await first.initialize();
    await first.setPage(entry, 7);
    await first.toggleBookmark(entry, 7);
    final restored = offlineStore();
    await restored.initialize();
    expect(restored.pages[entry.id], 7);
    expect(restored.bookmarks[entry.id], [7]);
    expect(restored.byId(entry.id)?.title, entry.title);
    expect(restored.cached, isTrue);
  });

  test('a download failure clears its active job and supports retry', () async {
    SharedPreferences.setMockInitialValues({'onboarded': true});
    var attempts = 0;
    final store = LibraryStore(findPdf: (_) async => attempts == 2 ? '/fixture/file.pdf' : null,
      saveFile: (_, _, _, _, _, progress) async {
        attempts++;
        progress(1, 2);
        if (attempts == 1) throw const FormatException('Bad PDF');
      });
    store.api.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      handler.reject(DioException(requestOptions: request, type: DioExceptionType.connectionError));
    }));
    await store.initialize();
    final verified = Book({...entry.data, 'verification_status': 'verified'});
    await store.download(verified);
    expect(store.failures, contains(verified.id));
    expect(store.active, isEmpty);
    await store.download(verified);
    expect(store.failures, isEmpty);
    expect(store.paths[verified.id], '/fixture/file.pdf');
  });

  testWidgets('guest searches and navigates on a narrow screen', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarded': true});
    final store = offlineStore();
    await tester.runAsync(store.initialize);
    router.go('/');
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(overrides: [
      storeProvider.overrideWith((_) => store),
    ], child: const BoiPath()));
    await tester.pumpAndSettle();
    final navigation = find.byType(LibraryNavigation);
    expect(navigation, findsOneWidget);
    expect(tester.widget<LibraryNavigation>(navigation).selectedIndex, 0);
    expect(find.descendant(of: navigation, matching: find.text('Present')), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'no-such-book');
    await tester.pumpAndSettle();
    expect(find.text('No books match these filters.'), findsOneWidget);
    await tester.tap(find.descendant(of: navigation, matching: find.text('Downloads')));
    await tester.pumpAndSettle();
    expect(find.text('No downloads yet.'), findsOneWidget);
    expect(tester.widget<LibraryNavigation>(navigation).selectedIndex, 1);
    await tester.tap(find.descendant(of: navigation, matching: find.text('Present')));
    await tester.pumpAndSettle();
    expect(tester.widget<LibraryNavigation>(navigation).selectedIndex, 3);
    await tester.tap(find.descendant(of: navigation, matching: find.text('Settings')));
    await tester.pumpAndSettle();
    expect(tester.widget<LibraryNavigation>(navigation).selectedIndex, 4);
    await tester.tap(find.descendant(of: navigation, matching: find.text('Library')));
    await tester.pumpAndSettle();
    expect(tester.widget<LibraryNavigation>(navigation).selectedIndex, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first launch leaves the catalog available and clearly labels pending books', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = offlineStore();
    await tester.runAsync(store.initialize);
    store.books = [entry];
    router.go('/');
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(ProviderScope(overrides: [
      storeProvider.overrideWith((_) => store),
    ], child: const BoiPath()));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.scrollUntilVisible(find.text(entry.title), 130,
      scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text(entry.title));
    await tester.pumpAndSettle();
    expect(find.text('Book details'), findsOneWidget);
    expect(find.text('Open official source'), findsOneWidget);
    expect(find.text('Read online'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide screens use a navigation rail', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarded': true});
    final store = offlineStore();
    await tester.runAsync(store.initialize);
    router.go('/');
    tester.view.physicalSize = const Size(1350, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(overrides: [
      storeProvider.overrideWith((_) => store),
    ], child: const BoiPath()));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Catalog'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
