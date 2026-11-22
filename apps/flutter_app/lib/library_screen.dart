import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'book.dart';
import 'book_artwork.dart';
import 'design.dart';
import 'library_navigation.dart';
import 'library_widgets.dart';
import 'live.dart';
import 'reader.dart';
import 'store.dart';
import 'strings.dart';
import 'theme_profile.dart';

const routes = ['/', '/downloads', '/teach', '/settings'];
const labels = ['Library', 'Downloads', 'Teacher Mode', 'Settings'];
const icons = [Icons.home_outlined, Icons.download_outlined, Icons.school_outlined, Icons.settings_outlined];
const selectedIcons = [Icons.home_rounded, Icons.download_rounded, Icons.school_rounded, Icons.settings_rounded];
void toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

Future<void> openExternal(BuildContext context, String url, Words words) async {
  try {
    final target = Uri.tryParse(url);
    if (target != null && target.scheme == 'https' &&
        await launchUrl(target, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank')) return;
  } catch (_) {
    // Provide the same recovery message for missing browser handlers.
  }
  if (context.mounted) toast(context, words('Could not open the link.'));
}

Future<void> downloadBook(BuildContext context, LibraryStore store, Book book, Words words) async {
  final url = book.downloadUrl;
  if (url == null) return;
  if (!kIsWeb && !store.paths.containsKey(book.id) && book.offlineDownloadUrl != null &&
      !store.failures.contains(book.id)) {
    await store.download(book);
    if (context.mounted && store.failures.contains(book.id)) {
      await openExternal(context, url, words);
    }
  } else {
    await openExternal(context, url, words);
  }
}

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, required this.tab});
  final int tab;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final search = TextEditingController();
  final searchFocus = FocusNode();
  final catalogHeading = GlobalKey();
  final selected = <String>{};
  String? version;
  String? subject;
  int? year;
  int? level;
  bool grid = true;
  bool newest = false;
  bool onlyDownloaded = false;
  bool selecting = false;

  bool get hasFilters => search.text.trim().isNotEmpty || year != null || level != null ||
      version != null || subject != null || onlyDownloaded;

  @override
  void dispose() {
    search.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  void reset() {
    setState(() {
      search.clear();
      year = null;
      level = null;
      version = null;
      subject = null;
      onlyDownloaded = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final words = Words(store.bangla);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 820;
    final extended = width >= 1120;
    if (!store.ready) {
      return Scaffold(appBar: AppBar(title: BrandLockup(words: words)),
        body: const Center(child: CircularProgressIndicator()));
    }
    final page = switch (widget.tab) {
      1 => downloads(store, words),
      2 => teacher(store, words),
      3 => settings(store, words),
      _ => catalog(store, words),
    };
    final body = KeyedSubtree(key: ValueKey(widget.tab), child: page);
    final searchHeight = MediaQuery.textScalerOf(context).scale(16) + 53;
    final header = AppBar(
      toolbarHeight: wide ? 64 : 56,
      bottom: widget.tab == 0 ? PreferredSize(
        preferredSize: Size.fromHeight(searchHeight),
        child: SizedBox(height: searchHeight, width: double.infinity, child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
          child: Align(alignment: AlignmentDirectional.centerStart,
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640),
              child: catalogSearch(words))),
        )),
      ) : null,
      title: wide ? Text(words(labels[widget.tab]), style: Theme.of(context).textTheme.titleMedium)
          : BrandLockup(words: words),
      actions: [
        TextButton.icon(onPressed: () => store.setLanguage(!store.bangla),
          icon: const Icon(Icons.language_rounded, size: 18),
          style: TextButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.surfaceContainer),
          label: Text(store.bangla ? 'English' : 'বাংলা')),
        const SizedBox(width: 10),
      ],
    );
    return Scaffold(
      appBar: wide ? null : header,
      bottomNavigationBar: wide || MediaQuery.viewInsetsOf(context).bottom > 0 ? null : LibraryNavigation(
        selectedIndex: widget.tab >= 2 ? widget.tab + 1 : widget.tab,
        onSelected: (index) {
              if (index == 2) {
                if (widget.tab != 0) context.go(routes[0]);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) searchFocus.requestFocus();
                });
                  return;
              }
            context.go(routes[index > 2 ? index - 1 : index]);
            },
        items: [
      (label: words(labels[0]), icon: icons[0], selectedIcon: selectedIcons[0]),
            (label: words(labels[1]), icon: icons[1], selectedIcon: selectedIcons[1]),
            (label: words('Search'), icon: Icons.search_outlined, selectedIcon: Icons.search_rounded),
            (label: words('Teach'), icon: icons[2], selectedIcon: selectedIcons[2]),
            (label: words(labels[3]), icon: icons[3], selectedIcon: selectedIcons[3]),
        ],
      ),
      body: SafeArea(top: !wide, child: Row(children: [
        if (wide) ...[
          NavigationRail(
            selectedIndex: widget.tab,
            extended: extended,
            minExtendedWidth: 218,
            groupAlignment: -.88,
            useIndicator: true,
            onDestinationSelected: (i) => context.go(routes[i]),
            leading: Padding(padding: const EdgeInsets.symmetric(vertical: 20),
              child: BrandLockup(words: words, showName: extended)),
            destinations: List.generate(routes.length, (i) => NavigationRailDestination(
              icon: Icon(icons[i]), selectedIcon: Icon(selectedIcons[i]), label: Text(words(labels[i])))),
          ),
          const VerticalDivider(width: 1),
        ],
        Expanded(child: wide ? Column(children: [
          SizedBox(height: header.preferredSize.height, child: header),
          const Divider(height: 1),
          Expanded(child: body),
        ]) : body),
      ])),
    );
  }

  Widget catalog(LibraryStore store, Words words) {
    final available = store.books.where((book) =>
      (year == null || book.year == year) && (level == null || book.coversLevel(level!)) &&
      (version == null || book.version == version) && (subject == null || book.subject == subject) &&
      (!onlyDownloaded || store.paths.containsKey(book.id)) && book.matches(search.text)).toList();
    available.sort((a, b) {
      final years = b.year.compareTo(a.year);
      final titles = a.title.compareTo(b.title);
      if (newest && years != 0) return years;
      return titles != 0 ? titles : a.level.compareTo(b.level);
    });
    final recent = store.pages.keys.toList().reversed.map(store.byId).whereType<Book>()
      .where((book) => book.pdf != null || store.paths.containsKey(book.id)).take(4).toList();
    final scale = MediaQuery.textScalerOf(context).scale(16);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): searchFocus.requestFocus,
      },
      child: Focus(autofocus: true, child: LayoutBuilder(builder: (context, bounds) {
        final side = bounds.maxWidth >= 960 ? 34.0 : 16.0;
        final inset = side + ((bounds.maxWidth - 1250).clamp(0.0, double.infinity) / 2);
        final contentWidth = bounds.maxWidth - 2 * inset;
        final columns = contentWidth >= 945 ? 4 : contentWidth >= 650 ? 3 : 2;
        final showGrid = grid && contentWidth >= 330 && scale < 20;
        return CustomScrollView(key: const PageStorageKey('catalog-scroll'), slivers: [
          SliverPadding(padding: EdgeInsets.fromLTRB(inset, 20, inset, 14),
            sliver: SliverList.list(children: [
              filterPanel(store, words),
              if (store.busy) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (store.cached && !store.busy) ...[
                const SizedBox(height: 10),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Row(children: [
                  Icon(Icons.cloud_off_outlined, size: 17, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(child: Text(words('Showing the saved catalog.'))),
                  TextButton(onPressed: store.refresh, child: Text(words('Retry'))),
                ])),
              ],
              if (recent.isNotEmpty && !hasFilters) ...[
                const SizedBox(height: 17),
                Text(words('Continue reading'), style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final book in recent) ActionChip(
                    avatar: const Icon(Icons.history_rounded, size: 17),
                    label: Text('${book.title} · ${words('Page')} ${words.number(store.pages[book.id]!)}',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                    onPressed: () => context.push('/read/${book.id}')),
                ]),
              ],
              const SizedBox(height: 22),
              KeyedSubtree(key: catalogHeading, child: resultsHeader(
                store, words, available, showGrid, showGrid || (contentWidth >= 330 && scale < 20))),
              if (available.isEmpty) ...[
                const SizedBox(height: 8),
                EmptyPanel(icon: Icons.search_off_rounded, title: words('No books match these filters.'),
                  detail: words('Try a different title or adjust your filters.'),
                  action: hasFilters ? OutlinedButton(onPressed: reset, child: Text(words('Clear filters'))) : null),
              ],
            ])),
          SliverPadding(padding: EdgeInsets.fromLTRB(inset, 0, inset, 24),
            sliver: showGrid ? SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns, mainAxisExtent: (columns == 2 ? 328.0 : 353.0) + (scale - 16).clamp(0.0, 6.0).toDouble() * 6,
                mainAxisSpacing: 13, crossAxisSpacing: 13),
              itemCount: available.length,
              itemBuilder: (_, index) => bookCard(available[index], store, words, columns == 2),
            ) : SliverList.separated(
              itemCount: available.length,
              itemBuilder: (_, index) => catalogTile(available[index], store, words),
              separatorBuilder: (_, _) => const SizedBox(height: 9),
            )),
        ]);
      })),
    );
  }

  Widget catalogSearch(Words words) => TextField(
    controller: search,
    focusNode: searchFocus,
    onChanged: (_) {
      final store = ref.read(storeProvider);
      if (store.firstRun) store.finishOnboarding();
      setState(() {});
    },
    textInputAction: TextInputAction.search,
    onSubmitted: (_) {
      searchFocus.unfocus();
      if (catalogHeading.currentContext case final BuildContext heading) {
        Scrollable.ensureVisible(heading, duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero : const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
      }
    },
    decoration: InputDecoration(
      labelText: words('Search title, subject or class'),
      floatingLabelBehavior: FloatingLabelBehavior.never,
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainer,
      prefixIcon: Icon(Icons.search_rounded, color: Theme.of(context).colorScheme.primary),
      suffixIcon: search.text.isEmpty ? null : IconButton(
        tooltip: words('Clear search'), icon: const Icon(Icons.close_rounded),
        onPressed: () => setState(search.clear)),
    ),
  );

  Widget filterPanel(LibraryStore store, Words words) {
    final scheme = Theme.of(context).colorScheme;
    final bySubject = {for (final book in store.books) book.subject: book.subjectName(words.bn)};
    final subjects = bySubject.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    final editions = <int, Set<String>>{};
    for (final book in store.books) {
      editions.putIfAbsent(book.year, () => {}).add(words.academicYear(book.year, book.edition));
    }
    final years = editions.keys.toList()..sort((a, b) => b.compareTo(a));
    final versions = Wrap(spacing: 7, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (final entry in <String?, String>{null: 'All versions', 'bn': 'Bangla Version', 'en': 'English Version'}.entries)
        ChoiceChip(label: Text(words(entry.value)), selected: version == entry.key,
          showCheckmark: false,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          side: BorderSide(color: version == entry.key ? Colors.transparent : scheme.outlineVariant),
          selectedColor: scheme.primaryContainer, onSelected: (_) => setState(() => version = entry.key)),
    ]);
    final filters = Wrap(spacing: 7, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      dropdown<int>(words('All classes'), level,
        {for (var i = 1; i <= 12; i++) i: words.className(i)}, Icons.school_outlined, (v) => level = v),
      dropdown<int>(words('All years'), year,
        {for (final y in years) y: editions[y]!.length == 1 ? editions[y]!.single : words.number(y)},
        Icons.calendar_today_outlined, (v) => year = v),
      dropdown<String>(words('All subjects'), subject, Map.fromEntries(subjects),
        Icons.category_outlined, (v) => subject = v),
      if (!kIsWeb) FilterChip(label: Text(words('Downloaded')), selected: onlyDownloaded,
        onSelected: (value) => setState(() => onlyDownloaded = value)),
    ]);
    return SurfacePanel(padding: const EdgeInsets.fromLTRB(13, 8, 13, 8),
      child: LayoutBuilder(builder: (context, bounds) => bounds.maxWidth >= 880 && kIsWeb
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: versions),
            const SizedBox(width: 12),
            Flexible(child: Align(alignment: Alignment.centerRight, child: filters)),
          ])
        : Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [versions, const Divider(height: 13), filters])));
  }

  Widget dropdown<T>(String label, T? value, Map<T, String> items, IconData icon, void Function(T?) assign) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<(T?,)>(
      tooltip: label,
      onSelected: (option) => setState(() => assign(option.$1)),
      itemBuilder: (_) => [
        PopupMenuItem<(T?,)>(value: (null,), child: Text(label)),
        for (final entry in items.entries) PopupMenuItem<(T?,)>(value: (entry.key,), child: Text(entry.value)),
      ],
      child: Chip(label: Text(items[value] ?? label),
        avatar: Icon(icon, size: 15, color: scheme.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: value == null ? scheme.surfaceContainerLow : scheme.primaryContainer,
        side: BorderSide(color: scheme.outlineVariant)),
    );
  }

  Widget resultsHeader(LibraryStore store, Words words, List<Book> books, bool showGrid, bool canToggle) {
    final theme = Theme.of(context);
    final title = Wrap(spacing: 10, runSpacing: 5, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Semantics(header: true, child: Text(words('Catalog'), style: theme.textTheme.headlineSmall)),
      DecoratedBox(decoration: BoxDecoration(color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20)),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(words.bookCount(books.length), style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onPrimaryContainer)))),
    ]);
    final actions = Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      if (hasFilters)
        TextButton(onPressed: reset, child: Text(words('Clear filters'))),
      if (canToggle) IconButton(tooltip: words(showGrid ? 'List view' : 'Grid view'),
        onPressed: () => setState(() => grid = !grid),
        icon: Icon(showGrid ? Icons.view_list_outlined : Icons.grid_view_rounded)),
      IconButton(tooltip: words('Refresh catalog'), onPressed: store.busy ? null : store.refresh,
        icon: const Icon(Icons.refresh_rounded)),
      PopupMenuButton<bool>(tooltip: words('Sort books'), icon: const Icon(Icons.sort_rounded), initialValue: newest,
        onSelected: (value) => setState(() => newest = value), itemBuilder: (_) => [
          PopupMenuItem(value: false, child: Text(words('Title A–Z'))),
          PopupMenuItem(value: true, child: Text(words('Newest first'))),
        ]),
      if (!kIsWeb && (selecting || books.any((book) => book.offlineDownloadUrl != null))) ...[
        if (selecting) TextButton(onPressed: () => setState(() { selecting = false; selected.clear(); }),
          child: Text(words('Cancel'))),
        TextButton(
          onPressed: selecting && selected.isEmpty ? null : () {
            if (selecting) downloadSelection(store, Set.of(selected));
            setState(() { selecting = !selecting; selected.clear(); });
          }, child: Text(words(selecting ? 'Download selected' : 'Select books'))),
      ],
    ]);
    return LayoutBuilder(builder: (context, bounds) => bounds.maxWidth >= 760
      ? Row(children: [Expanded(child: title), Flexible(child: actions)])
      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, actions]));
  }

  Future<void> downloadSelection(LibraryStore store, Set<String> ids) async {
    for (final id in ids) {
      final book = store.byId(id);
      if (book != null) await store.download(book);
    }
  }

  bool selectable(Book book, LibraryStore store) =>
    !selecting || (book.offlineDownloadUrl != null && !store.paths.containsKey(book.id));

  void open(Book book) {
    if (selecting) {
      setState(() { if (!selected.remove(book.id)) selected.add(book.id); });
    } else {
      context.push('/book/${book.id}');
    }
  }

  Widget bookCard(Book book, LibraryStore store, Words words, bool compact) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final active = store.active.containsKey(book.id);
    final downloaded = store.paths.containsKey(book.id);
    final tap = selectable(book, store) ? () => open(book) : null;
    final heading = Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleMedium);
    return Semantics(selected: selecting ? selected.contains(book.id) : null,
      child: Card(clipBehavior: Clip.antiAlias, child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: InkWell(
            onTap: tap,
            child: Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 0), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: compact ? 122 : 139, width: double.infinity,
                  child: ClipRRect(borderRadius: BorderRadius.circular(16),
                    child: Stack(fit: StackFit.expand, children: [
                      BookArtwork(book: book),
                      if (tap != null) Align(alignment: Alignment.topRight, child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: colors.surfaceContainerLow, shape: BoxShape.circle),
                          child: Padding(padding: const EdgeInsets.all(6), child: Icon(
                            selecting ? (selected.contains(book.id) ? Icons.check_circle_rounded : Icons.radio_button_unchecked)
                              : Icons.north_east_rounded,
                            color: colors.primary, size: 16)),
                        ),
                      )),
                    ]))),
                const SizedBox(height: 10),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${words.className(book.level, book.lastLevel)} · ${words.academicYear(book.year, book.edition)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: colors.primary, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    heading,
                    const SizedBox(height: 4),
                    Text(words.version(book.version), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                  ],
                )),
              ],
            )),
          )),
          Padding(padding: const EdgeInsets.fromLTRB(13, 4, 13, 12), child:
            !selecting && book.downloadUrl != null
              ? FilledButton.tonalIcon(
                  onPressed: active ? null : () => downloadBook(context, store, book, words),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    textStyle: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                  icon: Icon(active ? Icons.hourglass_top_rounded : Icons.download_rounded, size: 17),
                  label: Text(words(active ? 'Downloading PDF' : 'Download PDF'),
                    maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                )
              : Align(alignment: Alignment.centerLeft,
                child: BookStatus(status: book.status, words: words, downloaded: downloaded))),
        ],
      )),
    );
  }

  Widget catalogTile(Book book, LibraryStore store, Words words) => Card(
    clipBehavior: Clip.antiAlias,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      leading: ClipRRect(borderRadius: BorderRadius.circular(7),
        child: SizedBox(width: 39, height: 49, child: BookArtwork(book: book, compact: true))),
      title: Text(book.title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${words.className(book.level, book.lastLevel)} · ${words.academicYear(book.year, book.edition)} · ${words.version(book.version)}'),
        const SizedBox(height: 5),
        BookStatus(status: book.downloadUrl != null && book.pdf == null ? 'linked' : book.status,
          words: words, downloaded: store.paths.containsKey(book.id)),
      ]),
      trailing: !selecting && book.downloadUrl != null
        ? IconButton.filledTonal(tooltip: words('Download PDF'), icon: const Icon(Icons.download_rounded),
            onPressed: store.active.containsKey(book.id) ? null : () => downloadBook(context, store, book, words))
        : Icon(selecting ? (selected.contains(book.id) ? Icons.check_circle_rounded : Icons.radio_button_unchecked)
            : Icons.chevron_right_rounded),
      onTap: selectable(book, store) ? () => open(book) : null,
    ),
  );

  Widget workspace(String title, String detail, List<Widget> children) => LayoutBuilder(
    builder: (context, bounds) => ListView(
      padding: EdgeInsets.fromLTRB(18.0 + ((bounds.maxWidth - 930).clamp(0.0, double.infinity) / 2), 28,
        18.0 + ((bounds.maxWidth - 930).clamp(0.0, double.infinity) / 2), 30),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 7),
        Text(detail, style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.45)),
        const SizedBox(height: 20),
        ...children,
      ],
    ),
  );

  Widget downloads(LibraryStore store, Words words) {
    final ids = {...store.active.keys, ...store.failures, ...store.paths.keys};
    return workspace(words('Downloads'), words(kIsWeb
      ? 'Browser downloads appear in your browser or device files.'
      : 'Open saved textbooks offline and manage active downloads.'), [
      if (ids.isEmpty) EmptyPanel(icon: Icons.download_for_offline_outlined,
        title: words(kIsWeb ? 'Find a textbook to download' : 'No downloads yet.'),
        action: FilledButton.tonalIcon(onPressed: () => context.go('/'),
          icon: const Icon(Icons.auto_stories_outlined), label: Text(words('Back to library')))),
      for (final id in ids)
        if (store.byId(id) case final Book book)
          Padding(padding: const EdgeInsets.only(bottom: 9), child: Card(child: ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(book.title),
            subtitle: store.active.containsKey(id) ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: LinearProgressIndicator(value: store.progress[id])) :
              Text(words(store.failures.contains(id) ? 'Download failed. Try again.' : 'Downloaded')),
            onTap: store.paths.containsKey(id) ? () => context.push('/read/$id') : null,
            trailing: store.active.containsKey(id)
                ? IconButton(tooltip: words('Cancel'), icon: const Icon(Icons.close_rounded), onPressed: () => store.cancel(id))
                : store.failures.contains(id)
                  ? IconButton(tooltip: words('Retry'), icon: const Icon(Icons.refresh_rounded), onPressed: () => store.download(book))
                  : IconButton(tooltip: words('Delete download'), icon: const Icon(Icons.delete_outline),
                      onPressed: () => confirmDelete(store, book, words)),
          ))),
    ]);
  }

  Future<void> confirmDelete(LibraryStore store, Book book, Words words) async {
    final confirmed = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
      title: Text(words('Delete download')), content: Text(book.title),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog), child: Text(words('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(words('Delete download'))),
      ],
    ));
    if (confirmed != true || !mounted) return;
    try {
      await store.deleteDownload(book.id);
    } catch (_) {
      if (mounted) toast(context, words('Request unsuccessful. Check the connection and try again.'));
    }
  }

  Widget teacher(LibraryStore store, Words words) {
    final textbooks = {for (final b in [...store.saved.values, ...store.books])
      if (b.pdf != null || store.paths.containsKey(b.id)) b.id: b};
    final actions = [
      LibraryQuickAction(icon: Icons.picture_as_pdf_outlined, title: words('Open PDF from device'),
        detail: words('Present and annotate a PDF you already have.'), emphasized: true,
        onTap: () => openDevicePdf(context, store, words)),
      LibraryQuickAction(icon: Icons.meeting_room_outlined, title: words('Join classroom'),
        detail: words('Enter a code to follow a live lesson.'),
        onTap: () => joinClassroom(context, store, words)),
    ];
    return workspace(words('Teacher Mode'), words('Present textbooks, mark up pages, and lead live lessons.'), [
      LayoutBuilder(builder: (context, bounds) => bounds.maxWidth >= 650
        ? Row(children: [Expanded(child: actions[0]), const SizedBox(width: 10), Expanded(child: actions[1])])
        : Column(children: [actions[0], const SizedBox(height: 10), actions[1]])),
      const SizedBox(height: 12),
      Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(
        onPressed: () async {
          await teacherSignIn(context, store, words);
          if (mounted) setState(() {});
        }, icon: const Icon(Icons.person_outline), label: Text(words(
          liveTeacherToken == null ? 'Teacher sign-in' : 'Sign out')))),
      const SizedBox(height: 26),
      Text(words('Choose a textbook to present'), style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      if (textbooks.isEmpty) EmptyPanel(icon: Icons.co_present_outlined,
        title: words('No verified or downloaded PDFs are available.')),
      for (final book in textbooks.values)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Card(child: ListTile(
          leading: const Icon(Icons.co_present_outlined), title: Text(book.title),
          subtitle: Text('${words.className(book.level, book.lastLevel)} · ${words.version(book.version)} · ${words.academicYear(book.year, book.edition)}'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push('/read/${book.id}?teach=1'),
        ))),
    ]);
  }

  Widget settings(LibraryStore store, Words words) => workspace(words('Settings'),
    words('Choose your language and appearance.'), [
      SurfacePanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(words('Language'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(label: const Text('English'), selected: !store.bangla,
            onSelected: (_) => store.setLanguage(false)),
          ChoiceChip(label: const Text('বাংলা'), selected: store.bangla,
            onSelected: (_) => store.setLanguage(true)),
        ]),
        const SizedBox(height: 10),
        const Divider(),
        SwitchListTile(contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.dark_mode_outlined), title: Text(words('Dark appearance')),
          value: store.dark, onChanged: store.setDark),
      ])),
      const SizedBox(height: 12),
      SurfacePanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(words('Color profile'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final profile in ThemeProfile.values)
            ChoiceChip(
              label: Text(words(profile.label)),
              avatar: ExcludeSemantics(child: CircleAvatar(backgroundColor: profile.seed)),
              selected: store.themeProfile == profile,
              showCheckmark: true,
              onSelected: (selected) {
                if (selected) store.setThemeProfile(profile);
              },
            ),
        ]),
      ])),
      const SizedBox(height: 12),
      SurfacePanel(child: Text(words('Independent platform linking to official NCTB resources.'))),
    ]);
}

String? appLink(String path) {
  final base = publicBase.isNotEmpty ? Uri.tryParse(publicBase) : (kIsWeb ? Uri.base : null);
  if (base == null || !base.hasAuthority || !{'http', 'https'}.contains(base.scheme)) return null;
  return Uri(scheme: base.scheme, host: base.host, port: base.hasPort ? base.port : null,
    path: base.path.isEmpty ? '/' : base.path, fragment: path).toString();
}
