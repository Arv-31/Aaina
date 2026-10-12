// contact_saver.dart: "Save contact" on the expanded card (extra D). No UI here.
//
// Opens the phone's own "new contact" screen, already filled in with what the
// person shares (name, work/college, links, skills). The user taps Save there.
// Because the phone's contacts app does the saving, Aaina needs NO contacts
// permission and never reads your address book. Uses the free
// flutter_contacts package. Android only (the stall laptop hides the button).

import 'package:flutter_contacts/flutter_contacts.dart';

import 'card_view.dart' show toUri;

/// Builds the contact from a server card. Kept separate so it can be tested.
Contact contactFromCard(Map<String, dynamic> card) {
  String? f(String key) {
    final v = (card[key] as String?)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  // "Aravind Kumar R" -> first "Aravind", last "Kumar R".
  final parts = (f('name') ?? '').split(RegExp(r'\s+'));
  final first = parts.first;
  final last = parts.length > 1 ? parts.sublist(1).join(' ') : null;

  final isStudent = card['student_status'] == 'student' ||
      (card['student_status'] == null && f('job_title') == null && f('college') != null);
  final org = isStudent
      ? (f('college') == null && f('course_year') == null
          ? null
          : Organization(name: f('college'), jobTitle: _join(['Student', f('course_year')])))
      : (f('company') == null && f('job_title') == null
          ? null
          : Organization(name: f('company'), jobTitle: f('job_title')));

  Website? site(String key, String label) {
    final uri = toUri(f(key));
    return uri == null
        ? null
        : Website(url: uri.toString(), label: Label(WebsiteLabel.custom, label));
  }

  final skills = [
    for (final s in (card['skills'] as List?) ?? const [])
      if (s is String && s.trim().isNotEmpty) s.trim(),
  ];

  return Contact(
    name: Name(first: first, last: last),
    organizations: [?org], // "?" = only added when not null
    // Missing links come back as null and are dropped by whereType.
    websites: [
      site('linkedin_url', 'LinkedIn'),
      site('github_url', 'GitHub'),
      site('instagram_url', 'Instagram'),
      site('portfolio_url', 'Portfolio'),
    ].whereType<Website>().toList(),
    notes: [
      Note(note: _join(['Met on Aaina', if (skills.isNotEmpty) 'Skills: ${skills.join(', ')}'], '\n')!),
    ],
  );
}

/// Opens the phone's "new contact" screen. Returns true if the user saved it.
Future<bool> saveContact(Map<String, dynamic> card) async {
  final id = await FlutterContacts.native.showCreator(contact: contactFromCard(card));
  return id != null;
}

String? _join(List<String?> parts, [String sep = ' · ']) {
  final kept = parts.whereType<String>().where((p) => p.isNotEmpty).toList();
  return kept.isEmpty ? null : kept.join(sep);
}
