import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'book.dart';
import 'book_artwork.dart';
import 'design.dart';
import 'library_screen.dart';
import 'store.dart';
import 'strings.dart';

class BookDetail extends ConsumerWidget {
  const BookDetail({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    final words = Words(store.bangla);
    final book = store.byId(id);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bar = AppBar(
      title: Text(words('Book details')),
      leading: IconButton(tooltip: words('Back to library'), icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/');
          }
        }),
    );
    if (book == null) return Scaffold(appBar: bar,
      body: Center(child: store.busy ? const CircularProgressIndicator() :
        Padding(padding: const EdgeInsets.all(16), child: EmptyPanel(icon: Icons.book_outlined,
          title: words('This book is unavailable.'),
          action: TextButton(onPressed: () => context.go('/'), child: Text(words('Back to library')))))));
    final downloaded = store.paths.containsKey(id);
    final active = store.active.containsKey(id);
    final readable = downloaded || book.pdf != null;
    final download = book.downloadUrl;
    final alternate = book.sourceDownloads.where((url) => url != download).toList();
    final metadata = <(IconData, String, String)>[
      (Icons.school_outlined, words('Class'), words.className(book.level, book.lastLevel)),
      (Icons.calendar_today_outlined, words('Academic year'), words.academicYear(book.year, book.edition)),
      (Icons.category_outlined, words('Subject'), book.subjectName(words.bn)),
      (Icons.language_rounded, words('Version'), words.version(book.version)),
      if (book.track.isNotEmpty) (Icons.route_outlined, words('Curriculum track'), book.track),
      if (book.edition.isNotEmpty) (Icons.layers_outlined, words('Edition'), book.edition),
      if (book.fileSize case final int bytes)
        (Icons.data_usage_rounded, words('File size'), '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'),
      if (book.verifiedAt case final String verified)
        (Icons.verified_outlined, words('Last verified'), verified.split('T').first),
    ];

    return Scaffold(appBar: bar, body: SafeArea(child: LayoutBuilder(builder: (context, bounds) {
      final side = 16.0 + ((bounds.maxWidth - 1050).clamp(0.0, double.infinity) / 2);
      final desktop = bounds.maxWidth - 2 * side >= 685;
      final heading = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${words.className(book.level, book.lastLevel)} · ${words.academicYear(book.year, book.edition)}',
          style: theme.textTheme.labelLarge?.copyWith(color: colors.primary, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        BookStatus(status: download != null && book.pdf == null ? 'linked' : book.status, words: words, downloaded: downloaded),
        const SizedBox(height: 13),
        Text(book.title, style: desktop ? theme.textTheme.displaySmall : theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text('${book.subjectName(words.bn)} · ${words.version(book.version)}',
          style: theme.textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant, height: 1.45)),
        if (!readable && download == null) ...[
          const SizedBox(height: 12),
          Text(words('You can check the official NCTB page for textbook access.'),
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
        ],
        const SizedBox(height: 18),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (download != null && !active && !downloaded)
            FilledButton.icon(
              onPressed: () => downloadBook(context, store, book, words),
              icon: const Icon(Icons.download_rounded), label: Text(words('Download PDF'))),
          if (readable)
            OutlinedButton.icon(onPressed: () => context.push('/read/$id'),
              icon: const Icon(Icons.menu_book_rounded), label: Text(words(downloaded ? 'Read offline' : 'Read online')))
          else if (download == null)
            FilledButton.icon(onPressed: () => openExternal(context, book.source, words),
              icon: const Icon(Icons.open_in_new_rounded), label: Text(words('Open official source'))),
          if (active) OutlinedButton(onPressed: () => store.cancel(id), child: Text(words('Cancel'))),
        ]),
        if (active) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: store.progress[id]),
        ],
        if (store.failures.contains(id)) ...[
          const SizedBox(height: 8),
          Text(words('Download failed. Try again.'), style: TextStyle(color: colors.error)),
        ],
      ]);
      final artwork = ClipRRect(borderRadius: BorderRadius.circular(20),
        child: SizedBox(height: desktop ? 308 : 208, width: desktop ? 270 : double.infinity,
          child: BookArtwork(book: book)));

      return ListView(padding: EdgeInsets.fromLTRB(side, 20, side, 28), children: [
        SurfacePanel(padding: EdgeInsets.all(desktop ? 24 : 15), child: desktop
          ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              artwork, const SizedBox(width: 26), Expanded(child: heading),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              artwork, const SizedBox(height: 16), heading,
            ])),
        const SizedBox(height: 15),
        SurfacePanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(words('Book information'), style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, constraints) {
            final column = constraints.maxWidth >= 470 ? (constraints.maxWidth - 10) / 2 : constraints.maxWidth;
            return Wrap(spacing: 10, runSpacing: 8, children: [
              for (final (icon, label, value) in metadata)
                SizedBox(width: column, child: Row(children: [
                  Container(width: 36, height: 36,
                    decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(10)),
                    child: Icon(icon, size: 18, color: colors.primary)),
                  const SizedBox(width: 9),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: theme.textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant)),
                    Text(value, style: theme.textTheme.bodyMedium),
                  ])),
                ])),
            ]);
          }),
          const SizedBox(height: 14),
          const Divider(),
          Wrap(spacing: 4, runSpacing: 4, children: [
            if (alternate.isNotEmpty)
              TextButton.icon(onPressed: () => openExternal(context, alternate.first, words),
                icon: const Icon(Icons.download_outlined), label: Text(words('Alternate PDF download'))),
            if (readable || download != null) TextButton.icon(onPressed: () => openExternal(context, book.source, words),
              icon: const Icon(Icons.open_in_new_rounded), label: Text(words('Open official source'))),
            TextButton.icon(onPressed: () async {
              await Clipboard.setData(ClipboardData(text: appLink('/book/$id') ?? book.source));
              if (context.mounted) toast(context, words('Link copied'));
            }, icon: const Icon(Icons.share_outlined), label: Text(words('Share book link'))),
            TextButton.icon(onPressed: () => reportIssue(context, store, book, words),
              icon: const Icon(Icons.flag_outlined), label: Text(words('Report an issue'))),
          ]),
        ])),
        const SizedBox(height: 13),
        Text(words('Independent platform linking to official NCTB resources.'),
          style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
      ]);
    })));
  }
}

Future<void> reportIssue(BuildContext context, LibraryStore store, Book book, Words words) async {
  final detail = await showDialog<String>(context: context, builder: (_) => IssueDialog(words: words));
  if (detail == null || !context.mounted) return;
  try {
    await store.api.post('/api/v1/reports', data: {
      'textbook_id': book.id, 'issue_type': 'other', 'description': detail,
    });
    if (context.mounted) toast(context, words('Report submitted'));
  } catch (_) {
    if (context.mounted) toast(context, words('Request unsuccessful. Check the connection and try again.'));
  }
}

class IssueDialog extends StatefulWidget {
  const IssueDialog({super.key, required this.words});
  final Words words;

  @override
  State<IssueDialog> createState() => _IssueDialogState();
}

class _IssueDialogState extends State<IssueDialog> {
  String detail = '';

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.words('Report an issue')),
    content: TextField(maxLength: 1000, maxLines: 3, autofocus: true,
      onChanged: (text) => setState(() => detail = text.trim()),
      decoration: InputDecoration(labelText: widget.words('Describe the issue'))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.words('Cancel'))),
      FilledButton(onPressed: detail.isEmpty ? null : () => Navigator.pop(context, detail),
        child: Text(widget.words('Send'))),
    ],
  );
}
