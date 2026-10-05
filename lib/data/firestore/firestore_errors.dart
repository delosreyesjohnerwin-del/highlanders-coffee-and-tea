import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// A write that failed, in a form the UI can show.
///
/// The admin panel must never silently lose an edit. Firestore writes fail for
/// boring, recoverable reasons — no signal, a token that expired mid-session,
/// an offline phone in a basement — and in every one of those cases the operator
/// believes the change went through and rebuilds the menu from memory. So a
/// failed write is turned into this and surfaced, rather than being swallowed.
@immutable
class WriteFailure {
  const WriteFailure({
    required this.operation,
    required this.message,
    this.code,
  });

  /// What was being attempted, e.g. "update order HL-2601-6372".
  final String operation;

  /// Operator-facing explanation. Never a raw exception dump.
  final String message;

  /// `FirebaseException.code`, when there was one.
  final String? code;

  @override
  String toString() => 'WriteFailure($operation: $message)';
}

/// Turns a thrown [Object] into a [WriteFailure].
///
/// Deliberately does not surface the exception's own `toString()`. A
/// `FirebaseException` embeds the full request URI and sometimes the payload,
/// which is noise in a UI and leaks the project id to anyone who screenshots
/// the toast.
WriteFailure describeFailure(String operation, Object error) {
  if (error is WriteFailure) return error;

  if (error is FirebaseException) {
    return WriteFailure(
      operation: operation,
      code: error.code,
      message: switch (error.code) {
        'permission-denied' =>
          'Not allowed. Your account may not have permission for this.',
        'unavailable' =>
          'No connection. The change is saved locally but not yet sent to the shop.',
        'deadline-exceeded' => 'Timed out. Check the connection and try again.',
        'failed-precondition' =>
          'A required index is missing. An engineer needs to create it.',
        'not-found' => 'That record no longer exists.',
        _ => 'Could not save (${error.code}).',
      },
    );
  }

  if (error is StateError) {
    return WriteFailure(operation: operation, message: error.message);
  }

  return WriteFailure(
    operation: operation,
    message: 'Could not save. ${error.runtimeType.toString()}.',
  );
}

/// A log line for the developer, kept out of user-facing text.
void logWriteFailure(WriteFailure failure) {
  if (kDebugMode) {
    // ignore: avoid_print
    print('[firestore] ${failure.operation} -> ${failure.code ?? failure.message}');
  }
}