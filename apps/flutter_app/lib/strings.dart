class Words {
  const Words(this.bn);
  final bool bn;
  String call(String key) => bn ? _bangla[key] ?? key : key;
  String digits(String value) => bn
      ? value.replaceAllMapped(RegExp(r'[0-9]'), (m) => '০১২৩৪৫৬৭৮৯'[int.parse(m[0]!)])
      : value;
  String number(num value) => digits(value.toString());
  String className(int level, [int? end]) {
    final grades = end != null && end > level ? '$level–$end' : '$level';
    return '${call('Class')} ${digits(grades)}';
  }

  String academicYear(int year, String edition) =>
      RegExp(r'^[0-9]{4}[–-][0-9]{2,4}$').hasMatch(edition) ? digits(edition) : number(year);

  String version(String value) => call(value == 'bn' ? 'Bangla Version' : 'English Version');
  String status(String value) => call(const {
    'linked': 'PDF available', 'verified': 'Verified PDF', 'pending': 'PDF verification pending',
    'unavailable': 'PDF unavailable', 'draft': 'Draft', 'archived': 'Archived',
  }[value] ?? value);

  String bookCount(int count) {
    if (bn) return '${number(count)}টি বই';
    final label = count == 1 ? 'book' : 'books';
    return '$count $label';
  }

  static const _bangla = {
    'Present': 'প্রেজেন্ট', 'Downloading PDF': 'পিডিএফ ডাউনলোড হচ্ছে', 'PDF available': 'পিডিএফ পাওয়া যাচ্ছে',
    'Alternate PDF download': 'পিডিএফের বিকল্প ডাউনলোড লিংক',
    'NCTB textbook library': 'এনসিটিবি পাঠ্যবই লাইব্রেরি',
    'Color profile': 'রঙের প্রোফাইল', 'Violet': 'বেগুনি', 'Ocean': 'সমুদ্র নীল',
    'Teal': 'নীলাভ সবুজ', 'Forest': 'বন সবুজ', 'Rose': 'গোলাপি', 'Amber': 'অ্যাম্বার',
    'Clear search': 'সার্চ মুছুন', 'Sort books': 'বই সাজান',
    'Try a different title or adjust your filters.': 'অন্য শিরোনাম দিয়ে খুঁজুন অথবা ফিল্টার পরিবর্তন করুন।',
    'Open saved textbooks offline and manage active downloads.': 'সংরক্ষিত বই অফলাইনে খুলুন এবং চলমান ডাউনলোড পরিচালনা করুন।',
    'Find a textbook to download': 'ডাউনলোডের জন্য পাঠ্যবই খুঁজুন',
    'Present textbooks, mark up pages, and lead live lessons.': 'পাঠ্যবই দেখান, পাতায় দাগ দিন এবং লাইভ পাঠ পরিচালনা করুন।',
    'Present and annotate a PDF you already have.': 'নিজের পিডিএফ খুলে দেখান এবং টীকা দিন।',
    'Enter a code to follow a live lesson.': 'লাইভ পাঠে যোগ দিতে কোড লিখুন।',
    'Choose your language and appearance.': 'ভাষা ও থিম বেছে নিন।',
    'Last class': 'শেষ শ্রেণি', 'One class': 'একটি শ্রেণি',
    'Last class must be above the first class.': 'শেষ শ্রেণি শুরুর শ্রেণির চেয়ে বড় হতে হবে।',
    'Language': 'ভাষা', 'Book details': 'বইয়ের বিবরণ', 'Book information': 'বইয়ের তথ্য',
    'File size': 'ফাইলের আকার', 'Last verified': 'সর্বশেষ যাচাই',
    'You can check the official NCTB page for textbook access.': 'পাঠ্যবই পেতে এনসিটিবির অফিসিয়াল পেজ দেখুন।',
    'BoiPath': 'বইপাঠ', 'Library': 'লাইব্রেরি', 'Downloads': 'ডাউনলোড',
    'Teacher Mode': 'শিক্ষক মোড', 'Settings': 'সেটিংস', 'Class': 'শ্রেণি',
    'Every textbook. Every classroom. One platform.': 'প্রতিটি পাঠ্যবই। প্রতিটি শ্রেণিকক্ষ। একই প্ল্যাটফর্ম।',
    'Explore textbooks': 'পাঠ্যবই খুঁজুন', 'Start exploring': 'বই খোঁজা শুরু করুন', 'Skip': 'এড়িয়ে যান',
    'Find official NCTB textbooks by class, year, and version.': 'শ্রেণি, শিক্ষাবর্ষ ও সংস্করণ অনুযায়ী এনসিটিবির পাঠ্যবই খুঁজুন।',
    'Search title, subject or class': 'বই, বিষয় বা শ্রেণি দিয়ে খুঁজুন',
    'Academic year': 'শিক্ষাবর্ষ', 'All years': 'সব বছর', 'All classes': 'সব শ্রেণি',
    'All versions': 'সব সংস্করণ', 'Bangla Version': 'বাংলা ভার্সন', 'English Version': 'ইংরেজি ভার্সন',
    'Subject': 'বিষয়', 'All subjects': 'সব বিষয়', 'Title A–Z': 'শিরোনাম অনুযায়ী', 'Newest first': 'নতুন বছর আগে',
    'Catalog': 'বইয়ের তালিকা', 'Continue reading': 'পড়া চালিয়ে যান', 'Refresh catalog': 'তালিকা রিফ্রেশ করুন',
    'Showing the saved catalog.': 'সংরক্ষিত তালিকা দেখানো হচ্ছে।',
    'Grid view': 'গ্রিড ভিউ', 'List view': 'তালিকা ভিউ', 'No books match these filters.': 'এই ফিল্টারে কোনো বই পাওয়া যায়নি।',
    'Clear filters': 'ফিল্টার মুছুন', 'Verified PDF': 'যাচাইকৃত পিডিএফ', 'PDF verification pending': 'পিডিএফ যাচাই বাকি',
    'PDF unavailable': 'পিডিএফ পাওয়া যাচ্ছে না', 'Draft': 'খসড়া', 'Archived': 'আর্কাইভ করা হয়েছে',
    'NCTB source': 'এনসিটিবি উৎস', 'Open official source': 'অফিশিয়াল উৎস খুলুন', 'Read online': 'অনলাইনে পড়ুন',
    'Read offline': 'অফলাইনে পড়ুন', 'Download PDF': 'পিডিএফ ডাউনলোড', 'Open PDF in browser': 'ব্রাউজারে পিডিএফ খুলুন',
    'Share book link': 'বইয়ের লিংক শেয়ার করুন', 'Link copied': 'লিংক কপি হয়েছে',
    'Report an issue': 'সমস্যা জানান', 'Report submitted': 'রিপোর্ট পাঠানো হয়েছে', 'Describe the issue': 'সমস্যার বিবরণ লিখুন',
    'Send': 'পাঠান', 'Cancel': 'বাতিল', 'Retry': 'আবার চেষ্টা করুন', 'Close': 'বন্ধ করুন',
    'Delete download': 'ডাউনলোড মুছুন', 'Download failed. Try again.': 'ডাউনলোড ব্যর্থ হয়েছে। আবার চেষ্টা করুন।',
    'No downloads yet.': 'এখনও কোনো ডাউনলোড নেই।', 'Browser downloads appear in your browser or device files.': 'ব্রাউজার ডাউনলোড আপনার ব্রাউজার বা ডিভাইসের ফাইলে থাকবে।',
    'Downloaded': 'ডাউনলোড হয়েছে', 'Download selected': 'নির্বাচিত বই ডাউনলোড করুন',
    'Select books': 'বই নির্বাচন করুন', 'Back to library': 'লাইব্রেরিতে ফিরুন',
    'This book is unavailable.': 'এই বইটি পাওয়া যাচ্ছে না।', 'Could not open the link.': 'লিংকটি খোলা যায়নি।',
    'Unable to load this PDF.': 'পিডিএফটি লোড করা যায়নি।', 'Page': 'পৃষ্ঠা', 'Go to page': 'পৃষ্ঠায় যান',
    'Previous page': 'আগের পৃষ্ঠা', 'Next page': 'পরের পৃষ্ঠা', 'Zoom in': 'বড় করুন', 'Zoom out': 'ছোট করুন',
    'Bookmark page': 'পৃষ্ঠা বুকমার্ক করুন', 'Remove bookmark': 'বুকমার্ক সরান', 'Bookmarks': 'বুকমার্ক',
    'No bookmarks yet.': 'এখনও কোনো বুকমার্ক নেই।', 'Present': 'উপস্থাপন করুন', 'Exit presentation': 'উপস্থাপনা বন্ধ করুন',
    'Choose a textbook to present': 'উপস্থাপনার জন্য একটি পাঠ্যবই বেছে নিন', 'No verified or downloaded PDFs are available.': 'কোনো যাচাইকৃত বা ডাউনলোড করা পিডিএফ পাওয়া যায়নি।',
    'Enter full screen': 'পূর্ণ পর্দায় দেখুন',
    'Pen': 'কলম', 'Highlighter': 'হাইলাইটার', 'Eraser': 'রাবার', 'Pan': 'সরান',
    'Undo': 'পূর্বাবস্থায় ফেরান', 'Redo': 'আবার করুন', 'Hide annotations': 'আঁকা লুকান', 'Show annotations': 'আঁকা দেখান',
    'Ink color': 'কলমের রং', 'Ink width': 'কলমের পুরুত্ব',
    'Open PDF from device': 'ডিভাইস থেকে পিডিএফ খুলুন',
    'Find in PDF': 'পিডিএফে খুঁজুন', 'Previous match': 'আগের ফল', 'Next match': 'পরের ফল',
    'No text matches. Scanned PDFs may not contain selectable text.': 'কোনো লেখা মেলেনি। স্ক্যান করা পিডিএফে নির্বাচনযোগ্য লেখা নাও থাকতে পারে।',
    'Lesson notes': 'পাঠের নোট', 'Save': 'সংরক্ষণ', 'Export notes and ink as JSON': 'নোট ও আঁকা JSON হিসেবে কপি করুন',
    'Copied to clipboard': 'ক্লিপবোর্ডে কপি হয়েছে', 'Lesson QR': 'পাঠের কিউআর',
    'Set PUBLIC_APP_URL to share links from the mobile app.': 'মোবাইল থেকে লিংক শেয়ার করতে PUBLIC_APP_URL সেট করুন।',
    'English': 'ইংরেজি', 'Dark appearance': 'ডার্ক মোড', 'Independent platform linking to official NCTB resources.': 'এনসিটিবির অফিসিয়াল রিসোর্সের লিংক ব্যবহারকারী স্বাধীন প্ল্যাটফর্ম।',
    'Request unsuccessful. Check the connection and try again.': 'অনুরোধটি সফল হয়নি। সংযোগ পরীক্ষা করে আবার চেষ্টা করুন।',
    'Live classroom': 'লাইভ শ্রেণিকক্ষ', 'Join classroom': 'শ্রেণিকক্ষে যোগ দিন', 'Session code': 'সেশন কোড',
    'Teacher sign-in': 'শিক্ষক সাইন-ইন', 'Start classroom': 'শ্রেণিকক্ষ শুরু করুন', 'End session': 'সেশন শেষ করুন',
    'Follow teacher': 'শিক্ষকের পৃষ্ঠা অনুসরণ করুন', 'Session ended': 'সেশন শেষ হয়েছে', 'Reconnecting…': 'আবার সংযোগ হচ্ছে…',
    'Catalog administration': 'ক্যাটালগ প্রশাসন', 'Reports': 'রিপোর্ট', 'Audit history': 'পরিবর্তনের ইতিহাস',
    'Add textbook': 'পাঠ্যবই যোগ করুন', 'No records.': 'কোনো তথ্য নেই।', 'Edit': 'সম্পাদনা',
    'Verify and publish': 'যাচাই করে প্রকাশ করুন', 'Archive': 'আর্কাইভ করুন', 'Resolve': 'সমাধান করুন',
    'Official title': 'অফিশিয়াল শিরোনাম', 'Alternative title': 'বিকল্প শিরোনাম',
    'Curriculum track': 'শিক্ষাধারা', 'Edition': 'সংস্করণ', 'Direct PDF URL': 'সরাসরি পিডিএফ লিংক',
    'Cover URL': 'প্রচ্ছদের লিংক', 'Required field': 'এই ঘরটি পূরণ করুন',
    'Enter a year between 2000 and 2100': '২০০০ থেকে ২১০০-এর মধ্যে বছর লিখুন',
    'Version': 'ভার্সন', 'Status': 'অবস্থা',
    'Email': 'ইমেইল', 'Password': 'পাসওয়ার্ড', 'Sign in': 'সাইন-ইন', 'Sign out': 'সাইন-আউট',
  };
}
