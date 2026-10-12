// card_view.dart: server profile card -> what the screens show.
// No UI here (the drawing is in widgets/ar_card.dart and widgets/profile_sheet.dart).
//
// On the camera (AR card) we show only: name, current status, LinkedIn.
//   student:       "Student · <course/year>"  +  college
//   professional:  "<job title>"              +  company
// The expanded card (tap) adds skills and every shared link.
// Fields the person left empty or chose not to share are simply skipped.

import '../../widgets/ar_card.dart';
import '../../widgets/profile_sheet.dart';

/// Reads one text field from the card; empty text counts as missing.
String? _field(Map<String, dynamic> card, String key) {
  final v = (card[key] as String?)?.trim();
  return (v == null || v.isEmpty) ? null : v;
}

/// The status lines shared by both card sizes.
({String? status, String? sub, bool isStudent}) _statusOf(Map<String, dynamic> card) {
  final course = _field(card, 'course_year');
  final college = _field(card, 'college');
  final job = _field(card, 'job_title');
  final company = _field(card, 'company');
  final isStudent =
      card['student_status'] == 'student' ||
      (card['student_status'] == null && job == null && (course ?? college) != null);

  if (isStudent) {
    return (status: course == null ? 'Student' : 'Student · $course', sub: college, isStudent: true);
  }
  if (job != null) return (status: job, sub: company, isStudent: false);
  if (company != null) return (status: company, sub: null, isStudent: false);
  return (status: null, sub: null, isStudent: false);
}

/// Small card on the camera.
ArCardData cardToView(Map<String, dynamic> card) {
  final name = (card['name'] as String?)?.trim() ?? '';
  final s = _statusOf(card);
  return ArCardData(
    initials: initialsOf(name),
    name: name,
    status: s.status,
    statusSub: s.sub,
    linkedInLabel: linkedInLabel(_field(card, 'linkedin_url')),
    isStudent: s.isStudent,
  );
}

/// Big card in the sheet (everything the person shares).
ProfileData cardToProfile(Map<String, dynamic> card) {
  final name = (card['name'] as String?)?.trim() ?? '';
  final s = _statusOf(card);
  final skills = [
    for (final x in (card['skills'] as List?) ?? const [])
      if (x is String && x.trim().isNotEmpty) x.trim(),
  ];

  final links = <ProfileLink>[];
  void add(LinkKind kind, String key, String Function(Uri) label) {
    final uri = toUri(_field(card, key));
    if (uri != null) links.add(ProfileLink(kind, label(uri), uri));
  }

  add(LinkKind.linkedIn, 'linkedin_url', (u) => _lastPart(u) ?? 'LinkedIn');
  add(LinkKind.github, 'github_url', (u) => _lastPart(u) ?? 'GitHub');
  add(LinkKind.instagram, 'instagram_url', (u) {
    final handle = _lastPart(u);
    return handle == null ? 'Instagram' : '@$handle';
  });
  add(LinkKind.portfolio, 'portfolio_url', _siteLabel);

  // The sheet labels the block "STUDYING", so "Student · " would repeat it.
  final course = _field(card, 'course_year');
  return ProfileData(
    initials: initialsOf(name),
    name: name,
    status: s.isStudent ? (course ?? 'Student') : s.status,
    statusSub: s.sub,
    isStudent: s.isStudent,
    skills: skills,
    links: links,
  );
}

/// "Aravind K" -> "AK", "priya" -> "P".
String initialsOf(String name) {
  final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final first = parts.first[0];
  final last = parts.length > 1 ? parts.last[0] : '';
  return (first + last).toUpperCase();
}

/// "https://www.linkedin.com/in/aravind-k/" -> "in/aravind-k".
String? linkedInLabel(String? url) {
  if (url == null) return null;
  final uri = Uri.tryParse(url.startsWith('http') ? url : 'https://$url');
  final segs = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
  if (segs.length >= 2) return '${segs[0]}/${segs[1]}';
  return uri?.host.isNotEmpty == true ? uri!.host : url;
}

/// Full https link for opening LinkedIn.
Uri? linkedInUri(Map<String, dynamic> card) => toUri(_field(card, 'linkedin_url'));

/// "github.com/x" -> https://github.com/x (null if empty or broken).
Uri? toUri(String? url) {
  if (url == null || url.trim().isEmpty) return null;
  final u = url.trim();
  final uri = Uri.tryParse(u.startsWith('http') ? u : 'https://$u');
  return (uri == null || uri.host.isEmpty) ? null : uri;
}

/// Last non-empty path part: github.com/aravindk/ -> "aravindk".
String? _lastPart(Uri u) {
  final segs = u.pathSegments.where((s) => s.isNotEmpty).toList();
  return segs.isEmpty ? null : segs.last;
}

/// https://www.aravind.dev/work/ -> "aravind.dev/work".
String _siteLabel(Uri u) {
  final host = u.host.startsWith('www.') ? u.host.substring(4) : u.host;
  final path = u.path.endsWith('/') ? u.path.substring(0, u.path.length - 1) : u.path;
  return '$host$path';
}
