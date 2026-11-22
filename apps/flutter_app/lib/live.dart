import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'library_screen.dart';
import 'reader.dart';
import 'store.dart';
import 'strings.dart';

String? _teacherAccess;
String? _teacherRefresh;
String? get liveTeacherToken => _teacherAccess;
Future<String?>? _refreshingTeacher;
Future<void> _lastPageUpdate = Future.value();

Options bearer(String token) => Options(headers: {'Authorization': 'Bearer $token'});

Future<void> teacherSignIn(BuildContext context, LibraryStore store, Words words) async {
  final current = liveTeacherToken;
  if (current != null) {
    _teacherAccess = null;
    _teacherRefresh = null;
    try {
      await store.api.post('/api/v1/auth/logout', options: bearer(current));
    } on DioException {
      if (context.mounted) toast(context, words('Request unsuccessful. Check the connection and try again.'));
    }
    return;
  }
  final token = await showDialog<String>(context: context, builder: (_) => SignInDialog(
    words: words, authenticate: (email, password) async {
      final response = await store.api.post<Map<String, dynamic>>('/api/v1/auth/login',
        data: {'email': email, 'password': password});
      if (response.data?['role'] != 'teacher') throw StateError('Teacher account required');
      _teacherRefresh = response.data!['refresh_token'] as String;
      return response.data!['access_token'] as String;
    }));
  if (token != null) _teacherAccess = token;
}

Future<String?> _rotateTeacher(LibraryStore store, String previous) async {
  if (_teacherAccess != previous) return _teacherAccess;
  final refresh = _teacherRefresh;
  if (refresh == null) return null;
  try {
    final response = await store.api.post<Map<String, dynamic>>('/api/v1/auth/refresh',
      data: {'refresh_token': refresh});
    if (_teacherRefresh != refresh) return _teacherAccess;
    _teacherAccess = response.data!['access_token'] as String;
    _teacherRefresh = response.data!['refresh_token'] as String;
  } on DioException catch (error) {
    if (error.response?.statusCode == 401 && _teacherRefresh == refresh) {
      _teacherAccess = null;
      _teacherRefresh = null;
    }
    rethrow;
  }
  return _teacherAccess;
}

Future<T> _withTeacher<T>(LibraryStore store, Future<T> Function(Options) request) async {
  final token = _teacherAccess;
  if (token == null) throw StateError('Sign in first');
  try {
    return await request(bearer(token));
  } on DioException catch (error) {
    if (error.response?.statusCode != 401) rethrow;
    final rotated = await (_refreshingTeacher ??= _rotateTeacher(store, token)
        .whenComplete(() => _refreshingTeacher = null));
    if (rotated == null) rethrow;
    return request(bearer(rotated));
  }
}

Future<String> createClassroom(LibraryStore store, String id, int page) async {
  final response = await _withTeacher(store, (options) =>
    store.api.post<Map<String, dynamic>>('/api/v1/classrooms',
      data: {'textbook_id': id, 'page': page}, options: options));
  return response.data!['code'] as String;
}

Future<void> setClassroomPage(LibraryStore store, String code, int page) {
  if (_teacherAccess == null) return Future.value();
  return _lastPageUpdate = _lastPageUpdate.then((_) async {
    try {
      await _withTeacher(store, (options) => store.api.patch('/api/v1/classrooms/$code/page',
        data: {'page': page}, options: options));
    } catch (_) {
      // The next page turn retries an interrupted update.
    }
  });
}

Future<void> endClassroom(LibraryStore store, String code) async {
  await _lastPageUpdate;
  await _withTeacher(store, (options) => store.api.post('/api/v1/classrooms/$code/end', options: options));
}

Future<void> showClassroomCode(BuildContext context, Words words, String code) async {
  final link = appLink('/classroom/$code');
  if (link != null) {
    await qrDialog(context, words, '${words('Session code')} $code', link);
    return;
  }
  await showDialog<void>(context: context, builder: (dialog) => AlertDialog(
    title: Text(words('Session code')), content: SelectableText(code),
    actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: Text(words('Close')))],
  ));
}

Future<void> joinClassroom(BuildContext context, LibraryStore store, Words words) async {
  final code = await showDialog<String>(context: context, builder: (dialog) => CodeDialog(words: words));
  if (code != null && context.mounted) context.push('/classroom/$code');
}

class ClassroomEntry extends StatefulWidget {
  const ClassroomEntry({super.key, required this.code, required this.store, required this.words});
  final String code;
  final LibraryStore store;
  final Words words;

  @override
  State<ClassroomEntry> createState() => _ClassroomEntryState();
}

class _ClassroomEntryState extends State<ClassroomEntry> {
  bool loading = true;
  bool ended = false;

  @override
  void initState() {
    super.initState();
    join();
  }

  Future<void> join() async {
    try {
      final response = await widget.store.api.get<Map<String, dynamic>>('/api/v1/classrooms/${widget.code}');
      if (!mounted) return;
      if (response.data case {'status': 'active', 'textbook_id': final String id, 'current_page': final int page}) {
        context.go('/read/$id?page=$page&classroom=${widget.code}');
        return;
      }
      ended = true;
    } catch (_) {
      ended = false;
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.words('Live classroom'))),
    body: Center(child: loading ? const CircularProgressIndicator() :
      Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(widget.words(ended ? 'Session ended' : 'Request unsuccessful. Check the connection and try again.')),
        if (!ended) TextButton(onPressed: () { setState(() => loading = true); join(); },
          child: Text(widget.words('Retry'))),
        TextButton(onPressed: () => context.go('/teach'), child: Text(widget.words('Teacher Mode'))),
      ]))),
  );
}

class LessonConnection {
  LessonConnection(this.store, this.code, {required this.onState});
  final LibraryStore store;
  final String code;
  final void Function(Map<String, dynamic>?) onState;
  WebSocketChannel? channel;
  StreamSubscription<dynamic>? subscription;
  Timer? retry;
  bool disposed = false;
  bool finished = false;
  int attempts = 0;

  void connect() {
    if (disposed || finished) return;
    final base = Uri.parse(apiBase);
    final uri = base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/api/v1/classrooms/$code/ws', query: '', fragment: '');
    channel = WebSocketChannel.connect(uri);
    channel!.ready.catchError((Object _) { disconnected(); });
    subscription = channel!.stream.listen((message) {
      final state = Map<String, dynamic>.from(jsonDecode(message as String) as Map);
      attempts = 0;
      finished = state['status'] != 'active';
      onState(state);
    }, onError: (Object _) => disconnected(), onDone: disconnected);
  }

  void disconnected() {
    if (disposed || finished || (retry?.isActive ?? false)) return;
    onState(null);
    final delay = (1 << attempts.clamp(0, 4).toInt());
    attempts++;
    retry = Timer(Duration(seconds: delay), () {
      subscription?.cancel();
      channel?.sink.close();
      connect();
    });
  }

  void dispose() {
    disposed = true;
    retry?.cancel();
    subscription?.cancel();
    channel?.sink.close();
  }
}

class SignInDialog extends StatefulWidget {
  const SignInDialog({super.key, required this.words, required this.authenticate});
  final Words words;
  final Future<String> Function(String, String) authenticate;

  @override
  State<SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<SignInDialog> {
  String email = '';
  String password = '';
  bool busy = false;
  bool failed = false;

  Future<void> submit() async {
    setState(() { busy = true; failed = false; });
    try {
      final token = await widget.authenticate(email, password);
      if (mounted) Navigator.pop(context, token);
    } catch (_) {
      if (mounted) setState(() { busy = false; failed = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = widget.words;
    return AlertDialog(title: Text(words('Sign in')),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(autofocus: true, keyboardType: TextInputType.emailAddress,
          onChanged: (value) => setState(() => email = value.trim()),
          decoration: InputDecoration(labelText: words('Email'))),
        const SizedBox(height: 12),
        TextField(obscureText: true, onChanged: (value) => setState(() => password = value),
          decoration: InputDecoration(labelText: words('Password'))),
        if (failed) Text(words('Request unsuccessful. Check the connection and try again.')),
      ])),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: Text(words('Cancel'))),
        FilledButton(onPressed: busy || email.isEmpty || password.isEmpty ? null : submit, child: Text(words('Sign in'))),
      ]);
  }
}

class CodeDialog extends StatefulWidget {
  const CodeDialog({super.key, required this.words});
  final Words words;

  @override
  State<CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<CodeDialog> {
  String code = '';

  @override
  Widget build(BuildContext context) => AlertDialog(title: Text(widget.words('Join classroom')),
    content: TextField(autofocus: true, maxLength: 8, textCapitalization: TextCapitalization.characters,
      onChanged: (value) => setState(() => code = value.toUpperCase().trim()),
      decoration: InputDecoration(labelText: widget.words('Session code'))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.words('Cancel'))),
      FilledButton(onPressed: RegExp(r'^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{8}$').hasMatch(code)
        ? () => Navigator.pop(context, code) : null, child: Text(widget.words('Join classroom'))),
    ]);
}
