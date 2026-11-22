class Book {
  const Book(this.data);

  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  bool get imported => data['is_local'] == true;
  String get title => data['official_title'] as String;
  int get year => data['academic_year'] as int;
  int get level => data['class_id'] as int;
  int get lastLevel => data['class_end_id'] as int? ?? level;
  bool coversLevel(int grade) => grade >= level && grade <= lastLevel;
  String get version => data['language_version'] as String;
  String get subject => data['subject_id'] as String;
  String get status => data['verification_status'] as String;
  String get track => data['curriculum_track'] as String;
  String get edition => data['edition'] as String? ?? '';
  String get source => data['source_url'] as String;
  String? get verifiedAt => data['last_verified_at'] as String?;
  String? get cover => data['cover_url'] as String?;
  String? get pdf => status == 'verified' ? data['pdf_url'] as String? : null;
  List<String> get sourceDownloads {
    if (status != 'pending' && status != 'verified') return const [];
    final links = data['source_download_urls'] as List? ?? const [];
    return links.whereType<String>().where((link) {
      final uri = Uri.tryParse(link);
      return uri != null && uri.scheme == 'https' && uri.userInfo.isEmpty &&
          (uri.host == 'drive.egovcloud.gov.bd' || uri.host == 'drive.google.com');
    }).toList();
  }

  String? get downloadUrl {
    final links = sourceDownloads;
    return pdf ?? (links.isEmpty ? null : links.first);
  }

   List<String> get resolvedCoverUrls {
      final urls = <String>[];
     final explicitCover = cover?.trim();
    if (explicitCover != null && explicitCover.isNotEmpty) {
      urls.add(explicitCover);
    }
    for (final link in sourceDownloads) {
      final uri = Uri.tryParse(link);
      if (uri == null || uri.host != 'drive.google.com') continue;
      String? fileId = uri.queryParameters['id'];
      if (fileId == null || fileId.isEmpty) {
        final dIndex = uri.pathSegments.indexOf('d');
        if (dIndex != -1 && dIndex + 1 < uri.pathSegments.length) {
          fileId = uri.pathSegments[dIndex + 1];
        }
      }
      if (fileId != null && fileId.isNotEmpty) {
        urls.add(Uri.https('lh3.googleusercontent.com', '/d/$fileId=w1000').toString());
        urls.add(Uri.https('drive.google.com', '/thumbnail', {'id': fileId, 'sz': 'w1000'}).toString());
        urls.add(Uri.https('drive.google.com', '/thumbnail', {'id': fileId, 'sz': 'w600'}).toString());
      }
    }
    for (final link in sourceDownloads) {
      final uri = Uri.tryParse(link);
      if (uri == null || uri.host != 'drive.egovcloud.gov.bd') continue;
      final sIndex = uri.pathSegments.indexOf('s');
      if (sIndex != -1 && sIndex + 1 < uri.pathSegments.length) {
        final token = uri.pathSegments[sIndex + 1];
        if (token.isNotEmpty) {
          urls.add(
            Uri.https(
              'drive.egovcloud.gov.bd',
              '/index.php/apps/files_sharing/publicpreview/$token',
              {'x': '600', 'y': '800', 'a': 'true'},
            ).toString(),
          );
        }
      }
    }
    return urls;
  }
  String? get resolvedCoverUrl => resolvedCoverUrls.isEmpty ? null : resolvedCoverUrls.first;
  
  String? get offlineDownloadUrl {
    final verified = pdf;
    if (verified != null) return verified;
    for (final link in sourceDownloads) {
      if (Uri.parse(link).host == 'drive.egovcloud.gov.bd') return link;
    }
    return null;
  }

  int? get fileSize => data['file_size'] as int?;

  String subjectName(bool bn) {
    const labels = {
      'bangla': ['Bangla', 'বাংলা'],
      'english': ['English', 'ইংরেজি'],
      'mathematics': ['Mathematics', 'গণিত'],
    };
    return data[bn ? 'subject_bn' : 'subject_en'] as String? ??
        labels[subject]?[bn ? 1 : 0] ??
        subject;
  }

  bool matches(String input) {
    final query = normalizeSearch(input);
    if (query.isEmpty) return true;
    final terms = query.split(' ');
    final haystack = normalizeSearch([
      title, data['alternative_title'], subjectName(false), subjectName(true),
      for (var grade = level; grade <= lastLevel; grade++) 'Class $grade শ্রেণি $grade',
      year, edition, track,
    ].whereType<Object>().join(' '));
    final words = haystack.split(' ');
    return terms.every((term) => haystack.contains(term) ||
        words.any((word) => oneEdit(term, word)));
  }
}

String normalizeSearch(String value) {
  const banglaDigits = '০১২৩৪৫৬৭৮৯';
  return value.toLowerCase()
      .replaceAll('\u09a1\u09bc', '\u09dc')
      .replaceAll('\u09a2\u09bc', '\u09dd')
      .replaceAll('\u09af\u09bc', '\u09df')
      .replaceAll(RegExp(r'[\u200c\u200d]'), '')
      .replaceAllMapped(RegExp('[$banglaDigits]'), (match) =>
          banglaDigits.indexOf(match[0]!).toString())
      .replaceAll(RegExp(r'[^a-z0-9\u0980-\u09ff]+'), ' ').trim();
}

bool oneEdit(String word, String other) {
  if (word.length < 4 || (word.length - other.length).abs() > 1) return false;
  if (word.length == other.length) {
    var different = 0;
    for (var index = 0; index < word.length; index++) {
      if (word[index] != other[index] && ++different > 1) return false;
    }
    return true;
  }
  final shorter = word.length < other.length ? word : other;
  final longer = word.length < other.length ? other : word;
  var index = 0;
  while (index < shorter.length && shorter[index] == longer[index]) {
    index++;
  }
  return shorter.substring(index) == longer.substring(index + 1);
}
