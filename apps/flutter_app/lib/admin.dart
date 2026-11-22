import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'book.dart';
import 'library_screen.dart';
import 'live.dart';
import 'store.dart';
import 'strings.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  String? token;
  var busy = false;
  var tab = 0;
  var offset = 0;
  List<Map<String, dynamic>> rows = [];
  List<Map<String, dynamic>> subjects = [];
  Map<String, dynamic> counts = {};
  LibraryStore get store => ref.read(storeProvider);
  Words get words => Words(store.bangla);

  Options get authorization => bearer(token!);
  static const sections = ['Catalog', 'Reports', 'Audit history'];
  static const endpoints = ['books', 'reports', 'audit'];

  void message(String value) {
    if (mounted) toast(context, words(value));
  }

  void showError(Object error) {
    if (error is DioException) {
      if (error.response?.statusCode == 401 && mounted) setState(() => token = null);
      final body = error.response?.data;
      if (body is Map && body['detail'] is String) {
        message(body['detail'] as String);
        return;
      }
    }
    message('Request unsuccessful. Check the connection and try again.');
  }

  Future<void> signIn() async {
    final result = await showDialog<String>(context: context, builder: (_) => SignInDialog(
      words: words, authenticate: (email, password) async {
        final response = await store.api.post<Map<String, dynamic>>('/api/v1/auth/login',
          data: {'email': email, 'password': password});
        if (response.data?['role'] != 'admin') throw StateError('Administrator role required');
        return response.data!['access_token'] as String;
      },
    ));
    if (!mounted || result == null) return;
    setState(() => token = result);
    await load();
  }

  Future<void> signOut() async {
    final auth = authorization;
    setState(() { token = null; rows = []; counts = {}; offset = 0; tab = 0; });
    try {
      await store.api.post('/api/v1/auth/logout', options: auth);
    } catch (error) {
      showError(error);
    }
  }

  Future<void> load() async {
    if (token == null || busy) return;
    setState(() => busy = true);
    await refreshRows();
    if (mounted) setState(() => busy = false);
  }

  Future<void> refreshRows() async {
    try {
      final response = await store.api.get<List<dynamic>>('/api/v1/admin/${endpoints[tab]}',
        queryParameters: {'offset': offset}, options: authorization);
      final data = response.data!.map((row) => Map<String, dynamic>.from(row as Map)).toList();
      if (!mounted) return;
      if (tab == 0) {
        final stats = await store.api.get<Map<String, dynamic>>('/api/v1/admin/stats', options: authorization);
        final topicResponse = await store.api.get<List<dynamic>>('/api/v1/subjects');
        if (!mounted) return;
        subjects = topicResponse.data!.map((row) => Map<String, dynamic>.from(row as Map)).toList();
        counts = stats.data!;
      }
      setState(() => rows = data);
    } catch (error) {
      showError(error);
    }
  }

  Future<void> mutate(Future<dynamic> Function() action) async {
    if (busy || token == null) return;
    setState(() => busy = true);
    try {
      await action();
      if (mounted) await refreshRows();
    } catch (error) {
      showError(error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit([Book? book]) async {
    final record = await showDialog<Map<String, dynamic>>(context: context,
      builder: (_) => BookForm(words: words, subjects: subjects, book: book));
    if (record == null || !mounted) return;
    await mutate(() => book == null
      ? store.api.post('/api/v1/admin/books', data: record, options: authorization)
      : store.api.patch('/api/v1/admin/books/${book.id}', data: record, options: authorization));
  }

  @override
  Widget build(BuildContext context) {
    final words = Words(ref.watch(storeProvider.select((store) => store.bangla)));
    final signedIn = token != null;
    return Scaffold(
      appBar: AppBar(title: Text(words('Catalog administration')), actions: [
        if (signedIn) TextButton(onPressed: busy ? null : signOut, child: Text(words('Sign out'))),
        IconButton(tooltip: words('Back to library'), icon: const Icon(Icons.local_library_outlined),
          onPressed: () => context.go('/')),
      ]),
      body: !signedIn
        ? Center(child: FilledButton.icon(onPressed: signIn,
            icon: const Icon(Icons.lock_outline), label: Text(words('Sign in'))))
        : Align(alignment: Alignment.topCenter, child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1060),
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var i = 0; i < sections.length; i++)
                  ChoiceChip(label: Text(words(sections[i])), selected: tab == i,
                    onSelected: busy || i == tab ? null : (_) {
                      setState(() { tab = i; offset = 0; rows = []; });
                      load();
                    }),
                if (tab == 0)
                  FilledButton.icon(onPressed: busy || subjects.isEmpty ? null : edit,
                    icon: const Icon(Icons.add), label: Text(words('Add textbook'))),
                IconButton(tooltip: words('Refresh catalog'), onPressed: busy ? null : load, icon: const Icon(Icons.refresh)),
              ]),
              if (busy) const LinearProgressIndicator(),
              if (tab == 0 && counts.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 10), child: Wrap(spacing: 8, children: [
                  for (final entry in counts.entries)
                    Chip(label: Text('${words.status(entry.key)} · ${words.number(entry.value as int)}')),
                ])),
              const SizedBox(height: 12),
              if (rows.isEmpty && !busy) Text(words('No records.')),
              for (final row in rows)
                switch (tab) {
                  0 => adminBook(Book(row)),
                  1 => report(row),
                  _ => Card(child: ListTile(title: Text('${row['action']} · ${row['book_id']}'),
                    subtitle: Text(row['at'] as String))),
                },
              Wrap(children: [
                if (offset > 0) TextButton(onPressed: busy ? null : () {
                  setState(() => offset -= 100);
                  load();
                }, child: Text(words('Previous page'))),
                if (rows.length == 100) TextButton(onPressed: busy ? null : () {
                  setState(() => offset += 100);
                  load();
                }, child: Text(words('Next page'))),
              ]),
            ]),
          )),
    );
  }

  Widget adminBook(Book book) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(book.title, style: Theme.of(context).textTheme.titleMedium),
      Text('${words.className(book.level, book.lastLevel)} · ${words.academicYear(book.year, book.edition)} · ${words.version(book.version)} · ${words.status(book.status)}'),
      Wrap(spacing: 8, children: [
        TextButton(onPressed: busy ? null : () => edit(book), child: Text(words('Edit'))),
        if (book.data['pdf_url'] != null && book.status != 'archived')
          TextButton(onPressed: busy ? null : () => mutate(() =>
            store.api.post('/api/v1/admin/books/${book.id}/verify', options: authorization)),
            child: Text(words('Verify and publish'))),
        if (book.status != 'archived')
          TextButton(onPressed: busy ? null : () => mutate(() =>
            store.api.delete('/api/v1/admin/books/${book.id}', options: authorization)),
            child: Text(words('Archive'))),
        TextButton(onPressed: () => openExternal(context, book.source, words),
          child: Text(words('Open official source'))),
      ]),
    ],
  )));

  Widget report(Map<String, dynamic> row) => Card(child: ListTile(
    title: Text(row['description'] as String),
    subtitle: Text('${row['issue_type']} · ${row['textbook_id']} · ${row['status']}'),
    trailing: row['status'] != 'open' ? null : TextButton(
      onPressed: busy ? null : () => mutate(() => store.api.patch(
        '/api/v1/admin/reports/${row['id']}/resolve', options: authorization)),
      child: Text(words('Resolve'))),
  ));
}

class BookForm extends StatefulWidget {
  const BookForm({super.key, required this.words, required this.subjects, this.book});
  final Words words;
  final List<Map<String, dynamic>> subjects;
  final Book? book;

  @override
  State<BookForm> createState() => _BookFormState();
}

class _BookFormState extends State<BookForm> {
  final form = GlobalKey<FormState>();
  static const labels = {
    'official_title': 'Official title', 'alternative_title': 'Alternative title',
    'academic_year': 'Academic year', 'curriculum_track': 'Curriculum track',
    'edition': 'Edition', 'source_url': 'NCTB source', 'pdf_url': 'Direct PDF URL',
  };
  static const requiredKeys = {'official_title', 'academic_year', 'curriculum_track', 'source_url'};
  late final fields = <String, dynamic>{
    for (final name in labels.keys) name: widget.book?.data[name],
    'cover_url': widget.book?.cover,
    'class_id': widget.book?.level ?? 1,
    'class_end_id': widget.book?.data['class_end_id'] ?? 0,
    'subject_id': widget.book?.subject ?? widget.subjects.first['id'],
    'language_version': widget.book?.version ?? 'bn',
    'verification_status': widget.book?.status == 'verified' ? 'pending' : widget.book?.status ?? 'draft',
  };

  void submit() {
    if (!form.currentState!.validate()) return;
    form.currentState!.save();
    final end = fields['class_end_id'] as int;
    if (end != 0 && end <= (fields['class_id'] as int)) {
      toast(context, widget.words('Last class must be above the first class.'));
      return;
    }
    Navigator.pop(context, {...fields, 'class_end_id': end == 0 ? null : end});
  }

  @override
  Widget build(BuildContext context) {
    final words = widget.words;
    return AlertDialog(title: Text(words(widget.book == null ? 'Add textbook' : 'Edit')),
      content: SizedBox(width: 490, child: SingleChildScrollView(child: Form(key: form, child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          for (final entry in labels.entries) Padding(padding: const EdgeInsets.only(bottom: 10), child: TextFormField(
            initialValue: fields[entry.key]?.toString(),
            keyboardType: entry.key == 'academic_year' ? TextInputType.number : TextInputType.text,
            decoration: InputDecoration(labelText: words(entry.value)),
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty && requiredKeys.contains(entry.key)) return words('Required field');
              if (entry.key == 'academic_year') {
                final year = int.tryParse(normalizeSearch(text));
                if (year == null || year < 2000 || year > 2100) return words('Enter a year between 2000 and 2100');
              }
              return null;
            },
            onSaved: (value) {
              final text = value?.trim() ?? '';
              fields[entry.key] = entry.key == 'academic_year' ? int.parse(normalizeSearch(text))
                : text.isEmpty && entry.key != 'edition' ? null : text;
            },
          )),
          field<int>('class_id', 'Class', {
            for (var level = 1; level <= 12; level++) level: words.className(level),
          }),
          field<int>('class_end_id', 'Last class', {
            0: words('One class'),
            for (var level = 2; level <= 12; level++) level: words.className(level),
          }),
          field<String>('subject_id', 'Subject', {
            for (final subject in widget.subjects)
              subject['id'] as String: subject[words.bn ? 'name_bn' : 'name_en'] as String,
          }),
          field<String>('language_version', 'Version', {'bn': words.version('bn'), 'en': words.version('en')}),
          field<String>('verification_status', 'Status', {
            for (final status in ['draft', 'pending', 'unavailable', 'archived']) status: words.status(status),
          }),
        ],
      )))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(words('Cancel'))),
        FilledButton(onPressed: submit, child: Text(words('Save'))),
      ],
    );
  }

  Widget field<T>(String name, String label, Map<T, String> values) {
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: DropdownButtonFormField<T>(
      initialValue: fields[name] as T,
      isExpanded: true,
      decoration: InputDecoration(labelText: widget.words(label)),
      items: [for (final item in values.entries) DropdownMenuItem(value: item.key, child: Text(item.value))],
      onChanged: (value) => fields[name] = value,
    ));
  }
}
