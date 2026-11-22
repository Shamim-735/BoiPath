import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'admin.dart';
import 'book_detail.dart';
import 'design.dart';
import 'library_screen.dart';
import 'live.dart';
import 'reader.dart';
import 'store.dart';
import 'strings.dart';

void main() => runApp(const ProviderScope(child: BoiPath()));

final router = GoRouter(routes: [
  GoRoute(path: '/classroom/:code', builder: (_, s) => Consumer(
    builder: (_, ref, _) {
      final store = ref.watch(storeProvider);
      return ClassroomEntry(code: s.pathParameters['code']!.toUpperCase(), store: store, words: Words(store.bangla));
    },
  )),
  GoRoute(path: '/admin', builder: (_, _) => const AdminScreen()),
  GoRoute(path: '/book/:id', builder: (_, s) => BookDetail(id: s.pathParameters['id']!)),
  GoRoute(path: '/read/:id', builder: (_, s) => ReaderRoute(
    id: s.pathParameters['id']!,
    requestedPage: int.tryParse(s.uri.queryParameters['page'] ?? ''),
    teaching: s.uri.queryParameters['teach'] == '1',
    sessionCode: s.uri.queryParameters['classroom'],
  )),
  for (final (path, tab) in [('/', 0), ('/downloads', 1), ('/teach', 2), ('/settings', 3)])
    GoRoute(path: path, pageBuilder: (_, _) => NoTransitionPage<void>(
      key: const ValueKey('library-shell'),
      name: path,
      child: LibraryScreen(tab: tab),
    )),
]);

class BoiPath extends ConsumerWidget {
  const BoiPath({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (bangla, dark, profile) = ref.watch(storeProvider.select((s) => (s.bangla, s.dark, s.themeProfile)));
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: Words(bangla)('BoiPath'),
      theme: boiPathTheme(Brightness.light, profile),
      darkTheme: boiPathTheme(Brightness.dark, profile),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      locale: Locale(bangla ? 'bn' : 'en'),
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
    );
  }
}
