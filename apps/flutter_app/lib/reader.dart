import 'dart:convert';
import 'dart:typed_data' show BytesBuilder;

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'annotations.dart';
import 'book.dart';
import 'fullscreen.dart';
import 'library_screen.dart';
import 'live.dart';
import 'store.dart';
import 'strings.dart';

class ReaderRoute extends ConsumerWidget {
  const ReaderRoute({super.key, required this.id, this.requestedPage, required this.teaching, this.sessionCode});
  final String id;
  final int? requestedPage;
  final bool teaching;
  final String? sessionCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    final book = store.byId(id);
    final words = Words(store.bangla);
    final local = store.paths[id];
    if (book == null || (book.pdf == null && local == null)) {
      return Scaffold(appBar: AppBar(title: Text(words('Library'))),
        body: Center(child: store.busy ? const CircularProgressIndicator() :
          Text(book == null ? words('This book is unavailable.') : words.status(book.status))));
    }
    if (!store.ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Reader(key: ValueKey((id, local, book.pdf)), book: book, local: local, store: store, words: words,
      start: requestedPage ?? store.pages[id] ?? 1, teaching: teaching, sessionCode: sessionCode);
  }
}

class Reader extends StatefulWidget {
  const Reader({super.key, required this.book, this.local, required this.store,
    required this.words, required this.start, required this.teaching, this.sessionCode, this.memory});
  final Book book;
  final String? local;
  final Uint8List? memory;
  final LibraryStore store;
  final Words words;
  final int start;
  final bool teaching;
  final String? sessionCode;

  @override
  State<Reader> createState() => _ReaderState();
}

class _ReaderState extends State<Reader> {
  final controller = PdfViewerController();
  PdfTextSearcher? searcher;
  final query = TextEditingController();
  late final LessonInk ink = LessonInk(widget.store, widget.book.id);
  late final int start = widget.start.clamp(1, 100000).toInt();
  late final LessonConnection? live = widget.sessionCode == null ? null :
      LessonConnection(widget.store, widget.sessionCode!, onState: handleLive);
  late bool presenting = widget.teaching;
  late bool teaching = widget.teaching;
  late int page = start;
  int total = 0;
  int attempt = 0;
  int? remotePage;
  bool follow = true;
  bool liveEnded = false;
  bool liveConnected = false;
  String? teachingCode;
  Words get words => widget.words;

  @override
  void initState() {
    super.initState();
    live?.connect();
    if (presenting && !kIsWeb) setPlatformFullscreen(true);
  }

  @override
  void dispose() {
    live?.dispose();
    ink.dispose();
    searcher?.dispose();
    query.dispose();
    if (presenting) setPlatformFullscreen(false);
    super.dispose();
  }

  void handleLive(Map<String, dynamic>? state) {
    if (!mounted) return;
    setState(() {
      liveConnected = state != null;
      liveEnded = state?['status'] == 'ended' || state?['status'] == 'expired';
      if (!liveEnded && state?['textbook_id'] == widget.book.id) {
        remotePage = state?['current_page'] as int?;
      }
    });
    if (follow && !liveEnded && remotePage != null && controller.isReady && page != remotePage) go(remotePage!);
  }

  void go(int next) {
    if (controller.isReady && total > 0) controller.goToPage(pageNumber: next.clamp(1, total).toInt());
  }

  void onPage(int? next) {
    if (next == null || !mounted) return;
    if (page != next) setState(() => page = next);
    widget.store.setPage(widget.book, next);
    final code = teachingCode;
    if (code != null) setClassroomPage(widget.store, code, next);
  }

  Future<void> startSession() async {
    if (liveTeacherToken == null) await teacherSignIn(context, widget.store, words);
    if (!mounted || liveTeacherToken == null) return;
    try {
      final code = await createClassroom(widget.store, widget.book.id, page);
      if (!mounted) return;
      setState(() => teachingCode = code);
      await showClassroomCode(context, words, code);
    } catch (_) {
      if (mounted) toast(context, words('Request unsuccessful. Check the connection and try again.'));
    }
  }

  Future<void> stopSession() async {
    final code = teachingCode;
    if (code == null) return;
    try {
      await endClassroom(widget.store, code);
      if (mounted) setState(() => teachingCode = null);
    } catch (_) {
      if (mounted) toast(context, words('Request unsuccessful. Check the connection and try again.'));
    }
  }

  void togglePresentation() {
    setState(() { presenting = !presenting; teaching = true; });
    setPlatformFullscreen(presenting);
  }

  void toggleSearch() {
    final current = searcher;
    if (current != null) {
      current.removeListener(updateSearch);
      current.resetTextSearch();
      current.dispose();
      query.clear();
      setState(() => searcher = null);
    } else if (controller.isReady) {
      setState(() => searcher = PdfTextSearcher(controller)..addListener(updateSearch));
    }
  }

  void retry() {
    searcher?.dispose();
    query.clear();
    setState(() {
      searcher = null;
      total = 0;
      attempt++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final local = widget.local;
    final activeSearch = searcher;
    final params = PdfViewerParams(
      backgroundColor: colors.surfaceContainerHighest,
      onPageChanged: onPage,
      panEnabled: ink.tool == InkTool.pan || !ink.visible,
      scaleEnabled: ink.tool == InkTool.pan || !ink.visible,
      pagePaintCallbacks: [if (activeSearch != null) activeSearch.pageTextMatchPaintCallback],
      onViewerReady: (document, _) {
        if (!mounted || document.pages.isEmpty) return;
        final count = document.pages.length;
        final target = (follow ? remotePage ?? start : start).clamp(1, count).toInt();
        setState(() { total = count; page = target; });
        if (target != start) go(target);
        widget.store.setPage(widget.book, target);
      },
      pageOverlaysBuilder: (_, rect, pdfPage) => [
        SizedBox.expand(child: PageInk(key: ValueKey(pdfPage.pageNumber), ink: ink, page: pdfPage.pageNumber)),
      ],
      errorBannerBuilder: (_, _, _, _) => Center(child: Padding(
        padding: const EdgeInsets.all(20), child: Wrap(spacing: 12, runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(words('Unable to load this PDF.')),
            FilledButton(onPressed: retry, child: Text(words('Retry'))),
            if (widget.book.pdf case final String target)
              TextButton(onPressed: () => openExternal(context, target, words), child: Text(words('Open PDF in browser'))),
            if (!widget.book.imported)
              TextButton(onPressed: () => openExternal(context, widget.book.source, words),
                child: Text(words('Open official source'))),
          ]),
      )),
    );
    final pdfKey = ValueKey((widget.book.id, local, attempt));
    final memory = widget.memory;
    final online = widget.book.pdf;
    final viewer = switch ((memory, local, online)) {
      (final Uint8List data, _, _) => PdfViewer.data(data, sourceName: widget.book.id,
        key: pdfKey, controller: controller, params: params, initialPageNumber: start),
      (_, final String path, _) => PdfViewer.file(path, key: pdfKey,
        controller: controller, params: params, initialPageNumber: start),
      (_, _, final String url) => PdfViewer.uri(Uri.parse(url), key: pdfKey,
        controller: controller, params: params, initialPageNumber: start, preferRangeAccess: !kIsWeb),
      _ => Center(child: Text(words('Unable to load this PDF.'))),
    };
    final pageLabel = '${words('Page')} ${words.number(page)}';
    final pagePosition = total == 0 ? pageLabel : '$pageLabel / ${words.number(total)}';
    final marked = widget.store.bookmarks[widget.book.id]?.contains(page) ?? false;

    return Scaffold(
      appBar: presenting ? null : AppBar(
        title: Text(widget.book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: Navigator.of(context).canPop() ? null : IconButton(
          icon: const Icon(Icons.arrow_back), tooltip: words('Back to library'),
          onPressed: () => context.go('/')),
      ),
      body: SafeArea(child: Column(children: [
        Material(color: colors.surfaceContainerLow, child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (presenting) readerGroup([
              IconButton(tooltip: words('Exit presentation'),
                icon: const Icon(Icons.fullscreen_exit), onPressed: togglePresentation),
              if (kIsWeb) IconButton(tooltip: words('Enter full screen'),
                icon: const Icon(Icons.fullscreen), onPressed: () => setPlatformFullscreen(true)),
            ]),
            readerGroup([
              IconButton(icon: const Icon(Icons.navigate_before_rounded), tooltip: words('Previous page'),
                onPressed: total > 0 && page > 1 ? () => go(page - 1) : null),
              TextButton(onPressed: total == 0 ? null : choosePage, child: Text(pagePosition)),
              IconButton(icon: const Icon(Icons.navigate_next_rounded), tooltip: words('Next page'),
                onPressed: total > page ? () => go(page + 1) : null),
            ]),
            readerGroup([
              IconButton(icon: const Icon(Icons.zoom_out_rounded), tooltip: words('Zoom out'),
                onPressed: total == 0 ? null : () => controller.zoomDown()),
              IconButton(icon: const Icon(Icons.zoom_in_rounded), tooltip: words('Zoom in'),
                onPressed: total == 0 ? null : () => controller.zoomUp()),
              IconButton(icon: Icon(marked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded),
                color: marked ? colors.primary : null,
                tooltip: words(marked ? 'Remove bookmark' : 'Bookmark page'),
                onPressed: total == 0 ? null : () => widget.store.toggleBookmark(widget.book, page)),
              IconButton(icon: const Icon(Icons.bookmarks_outlined), tooltip: words('Bookmarks'), onPressed: showBookmarks),
              IconButton(icon: Icon(activeSearch != null ? Icons.close_rounded : Icons.search_rounded),
                tooltip: words('Find in PDF'), onPressed: total == 0 ? null : toggleSearch),
              if (!presenting) IconButton(tooltip: words('Present'), icon: const Icon(Icons.fullscreen),
                onPressed: togglePresentation),
            ]),
          ]),
        )),
        const Divider(height: 1),
        if (activeSearch != null) searchBar(activeSearch),
        if (live != null) Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(words(liveEnded ? 'Session ended' : liveConnected ? 'Live classroom' : 'Reconnecting…')),
          if (!liveEnded) FilterChip(label: Text(words('Follow teacher')), selected: follow,
            onSelected: (enabled) {
              setState(() => follow = enabled);
              if (enabled && remotePage != null) go(remotePage!);
            }),
        ]),
        if (teaching) teacherTools(),
        Expanded(child: viewer),
      ])),
    );
  }

  Widget readerGroup(List<Widget> actions) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.surfaceContainer, borderRadius: BorderRadius.circular(12)),
      child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center,
        children: actions),
    );
  }

  Widget teacherTools() => ListenableBuilder(listenable: ink, builder: (_, _) => Material(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (final (tool, icon, label) in [
        (InkTool.pan, Icons.pan_tool_outlined, 'Pan'), (InkTool.pen, Icons.edit_outlined, 'Pen'),
        (InkTool.highlight, Icons.border_color, 'Highlighter'), (InkTool.erase, Icons.auto_fix_off, 'Eraser'),
      ])
        IconButton(
          isSelected: ink.tool == tool,
          selectedIcon: Icon(icon, color: Theme.of(context).colorScheme.primary),
          style: ink.tool == tool ? IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer) : null,
          tooltip: words(label), icon: Icon(icon), onPressed: () {
          setState(() {
            ink.tool = tool;
            if (tool != InkTool.pan) ink.visible = true;
          });
          ink.changed();
        }),
      PopupMenuButton<Color>(tooltip: words('Ink color'), icon: Icon(Icons.palette_outlined, color: ink.color),
        onSelected: (color) { ink.color = color; ink.changed(); },
        itemBuilder: (_) => [
          for (final color in [Colors.blue, Colors.red, Colors.green, Colors.amber, Colors.black])
            PopupMenuItem(value: color, child: Icon(Icons.circle, color: color)),
        ]),
      PopupMenuButton<double>(tooltip: words('Ink width'), icon: const Icon(Icons.line_weight),
        onSelected: (width) { ink.width = width; ink.changed(); },
        itemBuilder: (_) => [for (final width in [2.0, 4.0, 7.0]) PopupMenuItem(value: width, child: Text('${width.toInt()} px'))]),
      IconButton(icon: const Icon(Icons.undo), tooltip: words('Undo'), onPressed: () => ink.undo(page)),
      IconButton(icon: const Icon(Icons.redo), tooltip: words('Redo'), onPressed: () => ink.redo(page)),
      IconButton(icon: Icon(ink.visible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
        tooltip: words(ink.visible ? 'Hide annotations' : 'Show annotations'),
        onPressed: () { setState(() => ink.visible = !ink.visible); ink.changed(); }),
      IconButton(icon: const Icon(Icons.note_alt_outlined), tooltip: words('Lesson notes'), onPressed: notes),
      if (!widget.book.imported)
        IconButton(icon: const Icon(Icons.qr_code), tooltip: words('Lesson QR'), onPressed: shareLesson),
      if (live == null && total > 0 && widget.book.pdf != null)
        if (teachingCode case final String code) ...[
          TextButton(onPressed: () => showClassroomCode(context, words, code), child: Text(code)),
          TextButton(onPressed: stopSession, child: Text(words('End session'))),
        ] else
          TextButton(onPressed: startSession, child: Text(words('Start classroom'))),
    ])),
  ));

  Widget searchBar(PdfTextSearcher searcher) => Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(controller: query, maxLength: 120, textInputAction: TextInputAction.search,
        onSubmitted: (text) {
          if (text.trim().isEmpty) {
            searcher.resetTextSearch();
          } else {
            searcher.startTextSearch(text.trim());
          }
        },
        decoration: InputDecoration(labelText: words('Find in PDF'), counterText: '',
          suffixIcon: IconButton(tooltip: words('Find in PDF'), icon: const Icon(Icons.search),
            onPressed: () {
              if (query.text.trim().isNotEmpty) searcher.startTextSearch(query.text.trim());
            }))),
      if (searcher.isSearching)
        const LinearProgressIndicator()
      else if (searcher.matches.isEmpty && query.text.trim().isNotEmpty)
        Text(words('No text matches. Scanned PDFs may not contain selectable text.'))
      else if (searcher.matches.isNotEmpty)
        Row(children: [
          Text('${words.number((searcher.currentIndex ?? 0) + 1)} / ${words.number(searcher.matches.length)}'),
          IconButton(tooltip: words('Previous match'), icon: const Icon(Icons.keyboard_arrow_up),
            onPressed: () => searcher.goToPrevMatch()),
          IconButton(tooltip: words('Next match'), icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () => searcher.goToNextMatch()),
        ]),
    ]),
  );

  void updateSearch() {
    if (mounted && searcher != null) setState(() {});
  }

  Future<void> choosePage() async {
    final next = await showDialog<int>(context: context, builder: (_) => ReaderInput(
      words: words, label: 'Go to page', initial: '', maximum: total,
    ));
    if (mounted && next != null) go(next);
  }

  Future<void> showBookmarks() async {
    final pages = widget.store.bookmarks[widget.book.id] ?? [];
    final selected = await showDialog<int>(context: context, builder: (dialog) => SimpleDialog(
      title: Text(words('Bookmarks')), children: [
        if (pages.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text(words('No bookmarks yet.'))),
        for (final p in pages)
          SimpleDialogOption(onPressed: () => Navigator.pop(dialog, p),
            child: Text('${words('Page')} ${words.number(p)}')),
      ],
    ));
    if (mounted && selected != null) go(selected);
  }

  Future<void> notes() async {
    final key = 'note:${widget.book.id}:$page';
    final original = widget.store.storedText(key) ?? '';
    final text = await showDialog<String>(context: context, builder: (_) => ReaderInput(
      words: words, label: 'Lesson notes', initial: original,
      onExport: (note) async {
        await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert({
          'textbook_id': widget.book.id, 'page': page, 'note': note, 'annotations': ink.toJson(),
        })));
        if (mounted) toast(context, words('Copied to clipboard'));
      },
    ));
    if (text != null) await widget.store.setText(key, text);
  }

  Future<void> shareLesson() async {
    final link = appLink('/read/${widget.book.id}?page=$page');
    if (link == null) {
      toast(context, words('Set PUBLIC_APP_URL to share links from the mobile app.'));
      return;
    }
    await qrDialog(context, words, words('Lesson QR'), link);
  }
}

Future<void> qrDialog(BuildContext context, Words words, String title, String link) =>
  showDialog<void>(context: context, builder: (dialog) => AlertDialog(
    title: Text(title),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      ColoredBox(color: Colors.white, child: QrImageView(data: link, size: 180)),
      const SizedBox(height: 12), SelectableText(link),
    ]),
    actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: Text(words('Close')))],
  ));

class ReaderInput extends StatefulWidget {
  const ReaderInput({super.key, required this.words, required this.label,
    required this.initial, this.maximum, this.onExport});
  final Words words;
  final String label;
  final String initial;
  final int? maximum;
  final Future<void> Function(String)? onExport;

  @override
  State<ReaderInput> createState() => _ReaderInputState();
}

class _ReaderInputState extends State<ReaderInput> {
  late String value = widget.initial;

  @override
  Widget build(BuildContext context) {
    final words = widget.words;
    final maximum = widget.maximum;
    final number = int.tryParse(normalizeSearch(value));
    return AlertDialog(
      title: Text(words(widget.label)),
      content: TextFormField(initialValue: value, autofocus: true,
        keyboardType: maximum == null ? TextInputType.multiline : TextInputType.number,
        maxLines: maximum == null ? 4 : 1, maxLength: maximum == null ? 8000 : 6,
        onChanged: (text) => setState(() => value = text)),
      actions: [
        if (widget.onExport case final Future<void> Function(String) sendToClipboard)
          TextButton(onPressed: () => sendToClipboard(value), child: Text(words('Export notes and ink as JSON'))),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(words('Cancel'))),
        FilledButton(onPressed: maximum != null && (number == null || number < 1 || number > maximum)
          ? null : () => Navigator.pop(context, maximum == null ? value : number),
          child: Text(words(maximum == null ? 'Save' : 'Go to page'))),
      ],
    );
  }
}

Future<void> openDevicePdf(BuildContext context, LibraryStore store, Words words) async {
  try {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom,
      allowedExtensions: ['pdf'], withData: false, withReadStream: kIsWeb);
    if (result == null || !context.mounted) return;
    final picked = result.files.single;
    final limit = (kIsWeb ? 40 : 300) * 1024 * 1024;
    if (picked.size < 10 || picked.size > limit) throw const FormatException('Unsupported PDF size');
    final nativeFile = kIsWeb ? null : result.xFiles.single;
    Uint8List? memory;
    late List<int> header;
    late Digest digest;
    if (nativeFile == null) {
      final stream = picked.readStream;
      if (stream == null) throw const FormatException('Browser file data unavailable');
      final buffer = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        if (buffer.length + chunk.length > limit) throw const FormatException('Unsupported PDF size');
        buffer.add(chunk);
      }
      memory = buffer.takeBytes();
      header = memory.take(5).toList();
      digest = sha256.convert(memory);
    } else {
      header = await nativeFile.openRead(0, 5).expand((chunk) => chunk).toList();
      digest = await sha256.bind(nativeFile.openRead()).first;
    }
    if (String.fromCharCodes(header) != '%PDF-') throw const FormatException('Invalid PDF');
    final id = 'local-$digest';
    final book = Book({'id': id, 'official_title': picked.name, 'is_local': true,
      'verification_status': 'local'});
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => Reader(
      book: book, local: nativeFile?.path, memory: memory,
      store: store, words: words, start: store.pages[id] ?? 1, teaching: true,
    )));
  } catch (_) {
    if (context.mounted) toast(context, words('Unable to load this PDF.'));
  }
}
