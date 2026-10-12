// Checks what the camera's AR card shows: only name, current status and
// LinkedIn, and empty fields are skipped (never "not found").

import 'package:aaina/features/camera_ar/card_view.dart';
import 'package:aaina/features/camera_ar/contact_saver.dart';
import 'package:aaina/widgets/profile_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('student: course/year + college, skills are not shown', () {
    final v = cardToView({
      'name': 'Aravind K',
      'linkedin_url': 'https://www.linkedin.com/in/aravind-k/',
      'student_status': 'student',
      'course_year': 'BCA, 3rd year',
      'college': 'Christ University',
      'skills': ['Flutter', 'Python'],
    });
    expect(v.initials, 'AK');
    expect(v.status, 'Student · BCA, 3rd year');
    expect(v.statusSub, 'Christ University');
    expect(v.linkedInLabel, 'in/aravind-k');
  });

  test('professional: job title + company', () {
    final v = cardToView({
      'name': 'Priya Sharma',
      'linkedin_url': 'linkedin.com/in/priya-s',
      'student_status': 'professional',
      'job_title': 'Product Designer',
      'company': 'Zoho',
    });
    expect(v.status, 'Product Designer');
    expect(v.statusSub, 'Zoho');
    expect(v.linkedInLabel, 'in/priya-s');
  });

  test('minimum card (name + LinkedIn): no status line at all', () {
    final v = cardToView({'name': 'Sam', 'linkedin_url': 'https://linkedin.com/in/sam'});
    expect(v.initials, 'S');
    expect(v.status, isNull);
    expect(v.statusSub, isNull);
  });

  // ---- Milestone 6: expanded card and Save contact ----

  final full = {
    'user_id': 'u1',
    'name': 'Aravind K',
    'linkedin_url': 'https://www.linkedin.com/in/aravind-k/',
    'student_status': 'student',
    'course_year': 'BCA, 3rd year',
    'college': 'Christ University',
    'skills': ['Flutter', ' Python ', ''],
    'github_url': 'https://github.com/aravindk',
    'instagram_url': 'https://instagram.com/aravind.k/',
    'portfolio_url': 'https://www.aravind.dev/',
  };

  test('expanded card: skills cleaned, links get short labels in a fixed order', () {
    final p = cardToProfile(full);
    expect(p.skills, ['Flutter', 'Python']);
    expect(p.isStudent, isTrue);
    expect([for (final l in p.links) l.kind],
        [LinkKind.linkedIn, LinkKind.github, LinkKind.instagram, LinkKind.portfolio]);
    expect([for (final l in p.links) l.label],
        ['aravind-k', 'aravindk', '@aravind.k', 'aravind.dev']);
  });

  test('expanded card: fields that are not shared simply do not appear', () {
    final p = cardToProfile({'name': 'Sam', 'linkedin_url': 'linkedin.com/in/sam'});
    expect(p.skills, isEmpty);
    expect(p.links.single.kind, LinkKind.linkedIn);
    expect(p.status, isNull);
  });

  test('save contact: name split, college as organisation, links and note', () {
    final c = contactFromCard(full);
    expect(c.name?.first, 'Aravind');
    expect(c.name?.last, 'K');
    expect(c.organizations.single.name, 'Christ University');
    expect(c.organizations.single.jobTitle, 'Student · BCA, 3rd year');
    expect(c.websites.length, 4);
    expect(c.notes.single.note, contains('Met on Aaina'));
    expect(c.notes.single.note, contains('Flutter, Python'));
  });
}
