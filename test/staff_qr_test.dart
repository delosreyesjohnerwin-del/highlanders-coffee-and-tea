import 'package:flutter_test/flutter_test.dart';
import 'package:highlanders_coffee/data/models/staff.dart';
import 'package:highlanders_coffee/services/staff_qr.dart';

/// The badge payload is the one thing an attacker controls end to end: they can
/// print any QR they like. These tests pin the two properties that stop a
/// screenshot or a hand-made code from clocking someone in — an opaque,
/// unguessable token, and a parser that refuses anything not shaped like one of
/// ours.
void main() {
  StaffMember member({String? token, DateTime? issued}) => StaffMember(
        id: 's-7',
        name: 'Mara Ilagan',
        role: StaffRole.barista,
        shift: ShiftStatus.offShift,
        qrToken: token,
        qrIssuedAt: issued,
      );

  group('mintStaffToken', () {
    test('is 32 lowercase hex characters', () {
      final String token = mintStaffToken();
      expect(token, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('does not repeat across many draws', () {
      final Set<String> seen = <String>{
        for (int i = 0; i < 500; i++) mintStaffToken(),
      };
      expect(seen, hasLength(500));
    });
  });

  group('parseStaffQr', () {
    test('round-trips a badge back to its parts', () {
      final DateTime issued = DateTime.utc(2026, 10, 4, 12);
      final Uri uri = staffQrUriFor(staffId: 's-7', token: 'abc123', issuedAt: issued);

      final StaffQrPayload? payload = parseStaffQr(uri.toString());

      expect(payload?.staffId, 's-7');
      expect(payload?.token, 'abc123');
      expect(payload?.issuedAt?.toUtc(), issued);
    });

    test('builds from a member only when they have a token', () {
      expect(staffQrUri(member()), isNull);
      expect(staffQrUri(member(token: 'abc123')), isNotNull);
    });

    test('refuses a foreign scheme', () {
      expect(parseStaffQr('https://example.test/staff?sid=s-7&t=abc'), isNull);
    });

    test('refuses our scheme with the wrong host', () {
      expect(parseStaffQr('highlanders://customer?sid=s-7&t=abc'), isNull);
    });

    test('refuses a missing or empty token', () {
      expect(parseStaffQr('highlanders://staff?sid=s-7'), isNull);
      expect(parseStaffQr('highlanders://staff?sid=s-7&t='), isNull);
    });

    test('refuses a missing staff id', () {
      expect(parseStaffQr('highlanders://staff?t=abc'), isNull);
    });

    test('refuses a non-URI string', () {
      expect(parseStaffQr('not a qr'), isNull);
    });
  });

  group('verifyStaffToken', () {
    test('accepts the current token', () {
      expect(verifyStaffToken(member(token: 'abc123'), 'abc123'), isTrue);
    });

    test('rejects a different token', () {
      expect(verifyStaffToken(member(token: 'abc123'), 'xyz789'), isFalse);
    });

    test('rejects everything for a member with no badge', () {
      expect(verifyStaffToken(member(), 'abc123'), isFalse);
    });
  });
}
