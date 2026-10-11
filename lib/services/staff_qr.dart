import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/models/staff.dart';

/// Staff badge QR: minting, encoding, parsing and verification.
///
/// ## The payload
///
/// A badge encodes a URI rather than a bare blob —
/// `highlanders://staff?sid=<id>&t=<token>&d=<issued>` — for two reasons. It is
/// self-describing, so a scanner can reject any QR that is not ours by scheme
/// and host alone; and it survives being read by a generic scanner app, which
/// shows the staff id and issue date instead of a wall of hex.
///
/// ## The trust model
///
/// Verification is a lookup against the roster the admin panel already streams:
/// the scanner is signed in as an admin, the roster is admin-readable under the
/// rules, and a badge is valid when its `t` equals the member's stored
/// [StaffMember.qrToken]. There is no server in this path, and none is needed —
/// the kiosk is the only verifier, and it holds the same secret the badge does.
/// The token is what stops a screenshot of an old badge from clocking someone in
/// after a rotation, which is why "regenerate" re-mints rather than reuses.
class StaffQr {
  const StaffQr._();

  /// URI scheme for a Highlanders staff badge.
  static const String scheme = 'highlanders';

  /// URI host for a staff badge.
  static const String host = 'staff';

  /// Bytes of entropy behind a token. 16 bytes = 128 bits, which is far past
  /// guessable and still short enough to keep the QR sparse.
  static const int tokenBytes = 16;
}

/// Random source for tokens and event ids.
///
/// `Random.secure()` because a predictable badge token is the whole attack:
/// anyone who can guess the next value can print their own badge. The fallback
/// is unreachable on Android but keeps a stripped-down environment from
/// throwing at the type level.
final Random _rng = Random.secure();

String _toHex(List<int> bytes) =>
    bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();

/// A fresh, opaque badge token: 32 lowercase hex characters.
String mintStaffToken() => _toHex(
      List<int>.generate(StaffQr.tokenBytes, (_) => _rng.nextInt(256)),
    );

/// A fresh id for a [ShiftEvent] document.
///
/// Time-prefixed so a natural sort is roughly chronological even before the
/// `at` field is parsed, and suffixed with randomness so two events in the same
/// microsecond cannot collide.
String mintShiftEventId() =>
    'ev-${DateTime.now().microsecondsSinceEpoch}-${_rng.nextInt(1 << 32).toRadixString(16)}';

/// The URI a badge should encode, or null when the member has no token yet.
Uri? staffQrUri(StaffMember member) {
  final String? token = member.qrToken;
  if (token == null || token.isEmpty) return null;
  return staffQrUriFor(staffId: member.id, token: token, issuedAt: member.qrIssuedAt);
}

/// Builds a badge URI from its parts. Exposed for tests and for callers that
/// hold the pieces rather than a whole [StaffMember].
Uri staffQrUriFor({
  required String staffId,
  required String token,
  DateTime? issuedAt,
}) =>
    Uri(
      scheme: StaffQr.scheme,
      host: StaffQr.host,
      queryParameters: <String, String>{
        'sid': staffId,
        't': token,
        if (issuedAt != null) 'd': issuedAt.toUtc().toIso8601String(),
      },
    );

/// The decoded contents of a scanned badge.
@immutable
class StaffQrPayload {
  const StaffQrPayload({required this.staffId, required this.token, this.issuedAt});

  final String staffId;
  final String token;
  final DateTime? issuedAt;
}

/// Parses a scanned string into a badge payload, or null when it is not one of
/// ours. Rejects on scheme, host and the two required parameters, so a random
/// QR at the counter is refused rather than treated as an unknown staff member.
StaffQrPayload? parseStaffQr(String raw) {
  final Uri? uri = Uri.tryParse(raw.trim());
  if (uri == null) return null;
  if (uri.scheme != StaffQr.scheme || uri.host != StaffQr.host) return null;

  final String? staffId = uri.queryParameters['sid'];
  final String? token = uri.queryParameters['t'];
  if (staffId == null || staffId.isEmpty || token == null || token.isEmpty) {
    return null;
  }

  final String? issued = uri.queryParameters['d'];
  return StaffQrPayload(
    staffId: staffId,
    token: token,
    issuedAt: issued == null ? null : DateTime.tryParse(issued)?.toLocal(),
  );
}

/// True when [token] is the member's current badge secret.
///
/// A member with no token verifies nothing: an un-minted badge cannot be
/// scanned into a shift until it has been displayed once and persisted.
bool verifyStaffToken(StaffMember member, String token) {
  final String? held = member.qrToken;
  return held != null && held.isNotEmpty && held == token;
}

/// How a scan resolved.
enum StaffClockOutcome {
  clockedIn,
  clockedOut,

  /// The badge was well-formed but names a staff id not on the roster.
  unknownStaff,

  /// The badge's token did not match the member's current token — an old,
  /// revoked badge, or a forgery.
  staleBadge,

  /// The scanned string was not a Highlanders badge at all.
  notABadge,
}

/// The result of a scan, shaped for the scanner's feedback banner.
@immutable
class StaffClockResult {
  const StaffClockResult(this.outcome, {this.staffName, this.at});

  final StaffClockOutcome outcome;
  final String? staffName;
  final DateTime? at;

  bool get isSuccess =>
      outcome == StaffClockOutcome.clockedIn || outcome == StaffClockOutcome.clockedOut;

  /// The line the scanner shows the operator.
  String get message => switch (outcome) {
        StaffClockOutcome.clockedIn => '$staffName clocked in',
        StaffClockOutcome.clockedOut => '$staffName clocked out',
        StaffClockOutcome.unknownStaff => 'That badge is not on the roster',
        StaffClockOutcome.staleBadge => 'That badge is out of date — print a new one',
        StaffClockOutcome.notABadge => 'Not a Highlanders staff badge',
      };
}
