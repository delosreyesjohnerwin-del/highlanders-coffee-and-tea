import 'package:cloud_functions/cloud_functions.dart';

import '../data/models/payment.dart';
import 'payment_gateway.dart';

/// Sends a link payload to the `linkPaymentMethod` Cloud Function and returns
/// its raw result.
///
/// A function instead of a widget class so tests can inject a fake with a
/// one-liner (the real `HttpsCallable` has a private constructor).
typedef LinkCallable = Future<Object?> Function(Map<String, Object?> payload);

/// The real gateway, backed by the `linkPaymentMethod` Cloud Function.
///
/// The function is the only party that holds the Xendit secret key. The app
/// sends the raw number/CVC over the authenticated callable channel; what comes
/// back — a reusable payment-method id, a masked label, a last-four tail and a
/// card brand — is the only thing the app ever persists.
///
/// [PaymentGatewayFactory] selects this implementation only when the build opts
/// in with `--dart-define=XENDIT_ENABLED=true` **and** Firebase is available;
/// otherwise the app rides [MockPaymentGateway].
class XenditPaymentGateway implements PaymentGateway {
  XenditPaymentGateway({LinkCallable? callable})
      : _callable = callable ?? _defaultCallable;

  final LinkCallable _callable;

  static Future<Object?> _defaultCallable(Map<String, Object?> payload) async {
    final HttpsCallableResult<Object?> response = await FirebaseFunctions.instance
        .httpsCallable('linkPaymentMethod')
        .call<Object?>(payload);
    return response.data;
  }

  @override
  Future<PaymentLinkResult> link(PaymentLinkRequest request) async {
    final Object? raw;
    try {
      raw = await _callable(<String, Object?>{
        'network': request.network.name,
        'holderName': request.holderName,
        'accountNumber': request.accountNumber,
        'email': request.email,
        'expiry': request.expiry,
        'cvc': request.cvc,
      });
    } on FirebaseFunctionsException catch (error) {
      throw GatewayException(_messageFrom(error));
    } catch (_) {
      // Includes transport-level failures (no connectivity, SDK errors).
      throw const GatewayException(
        'Could not reach the payment service. Check your connection and '
        'try again.',
      );
    }

    if (raw is! Map) {
      throw const GatewayException(
        'The payment service returned an unexpected response.',
      );
    }
    final Map<Object?, Object?> map = raw;
    final String? gatewayId = map['gatewayId'] as String?;
    final String? label = map['accountLabel'] as String?;
    final String? tail = map['tail'] as String?;

    if (gatewayId == null || gatewayId.isEmpty) {
      throw const GatewayException(
        'The payment service did not link this account. Try again.',
      );
    }

    // The Cloud Function is the authority on the mask; the local fallbacks
    // below keep the client honest if an older function returns fewer fields.
    return PaymentLinkResult(
      gatewayId: gatewayId,
      accountLabel: (label == null || label.isEmpty)
          ? PaymentAccount.maskOf(request.network, request.accountNumber)
          : label,
      tail: (tail == null || tail.isEmpty)
          ? PaymentAccount.tailOf(request.accountNumber)
          : tail,
    );
  }

  /// Picks the most human-readable message out of a functions call failure.
  ///
  /// `HttpsError` details carry `{message}`; a plain string message also works;
  /// falling back to the framework message keeps the SnackBar populated no
  /// matter which shape the runtime hands back.
  String _messageFrom(FirebaseFunctionsException error) {
    final Object? details = error.details;
    if (details is String && details.trim().isNotEmpty) {
      return details.trim();
    }
    if (details is Map) {
      final Object? message = details['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    }
    final String? message = error.message;
    if (message != null && message.isNotEmpty) {
      return message;
    }
    return 'The payment service declined this request.';
  }
}