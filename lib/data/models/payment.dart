import 'package:flutter/material.dart';

/// The network a linked [PaymentAccount] belongs to.
///
/// Kept deliberately separate from `PaymentMethod` (the enum recorded on an
/// [Order]): that one says how a *specific order* was paid, while this one is
/// the reusable vault a customer links once in their profile. A single order
/// can never mix the two concepts — it records a method; the profile holds
/// accounts, one of which may be marked default.
enum PaymentNetwork {
  /// GCash — the café's most-used wallet.
  gcash,

  /// Maya (formerly PayMaya).
  maya,

  /// Debit and credit cards (Visa / Mastercard / Amex…).
  card,

  /// E-banking / bank transfer.
  bankTransfer,
}

extension PaymentNetworkX on PaymentNetwork {
  String get label => switch (this) {
        PaymentNetwork.gcash => 'GCash',
        PaymentNetwork.maya => 'Maya',
        PaymentNetwork.card => 'Debit/Credit Card',
        PaymentNetwork.bankTransfer => 'Bank Transfer',
      };

  /// The closest monochrome Material glyph. Stands in for the real brand logo
  /// until licensed artwork exists; rendered in a fixed chip so swapping to an
  /// image later is a one-line change.
  IconData get icon => switch (this) {
        PaymentNetwork.gcash => Icons.account_balance_wallet_outlined,
        PaymentNetwork.maya => Icons.phone_iphone_outlined,
        PaymentNetwork.card => Icons.credit_card_outlined,
        PaymentNetwork.bankTransfer => Icons.account_balance_outlined,
      };

  /// E-wallets are reached at a Philippine mobile number; cards and bank
  /// accounts carry a plain account number.
  bool get isMobileWallet => this == PaymentNetwork.gcash || this == PaymentNetwork.maya;
}

/// A payment method a customer has linked in their profile.
///
/// ## What is stored — and what deliberately is not
///
/// The full number typed into the link form never reaches persistence. It is
/// handed to the payment gateway (PayMongo / Xendit, when one is wired up),
/// which returns `gatewayId`; what ships to the database is only:
///
///  * `accountLabel` — the number as it is safe to display (`0917****123`,
///    `**** **** 4321`).
///  * `tail` — the last four digits, used to spot a duplicate link.
///
/// A leaked `paymentMethods` collection must not hand anyone a reusable card
/// number, and this model is shaped so that it cannot. Card CVC and expiry
/// exist only in the air between the form and the gateway call.
@immutable
class PaymentAccount {
  const PaymentAccount({
    required this.id,
    required this.network,
    required this.holderName,
    required this.accountLabel,
    required this.tail,
    this.email,
    this.isDefault = false,
    required this.linkedAt,
    this.gatewayId,
    this.cardBrand,
  });

  final String id;
  final PaymentNetwork network;
  final String holderName;

  /// The number as masked for display, e.g. `0917****123` or `**** **** 4321`.
  final String accountLabel;

  /// Last four digits of the underlying number.
  final String tail;

  /// E-wallet accounts may carry an email for receipts.
  final String? email;

  final bool isDefault;

  /// When the account was linked, for the "Linked d MMM yyyy" caption.
  final DateTime linkedAt;

  /// Token/id returned by the payment gateway. `mock-pm-…` until a real
  /// gateway exists.
  final String? gatewayId;

  /// Display-only brand guess for cards (Visa, Mastercard, Amex) — never a
  /// correctness boundary, the gateway decides for real.
  final String? cardBrand;

  PaymentAccount copyWith({bool? isDefault}) => PaymentAccount(
        id: id,
        network: network,
        holderName: holderName,
        accountLabel: accountLabel,
        tail: tail,
        email: email,
        isDefault: isDefault ?? this.isDefault,
        linkedAt: linkedAt,
        gatewayId: gatewayId,
        cardBrand: cardBrand,
      );

  // --- format + validation helpers ----------------------------------------
  //
  // Domain logic rides on the model, like `SavedAddress.distanceKm`, so the
  // form validators, the gateway mock and the tests all share one definition.

  /// True for `0917 123 4567`, `+639171234567`, `0917-123-4567`, etc.
  static bool isValidPhMobile(String raw) {
    final String compact = raw.replaceAll(RegExp(r'[^\d+]'), '');
    return RegExp(r'^09\d{9}$').hasMatch(compact) || RegExp(r'^\+639\d{9}$').hasMatch(compact);
  }

  /// Display-safe preview of [raw] for [network]:
  ///
  ///  * e-wallets: `0917****123` — first four digits, four stars, last three.
  ///  * cards: `**** **** 4321` — last four only.
  ///  * bank accounts: `****1234` — last four only.
  static String maskOf(PaymentNetwork network, String raw) {
    switch (network) {
      case PaymentNetwork.gcash:
      case PaymentNetwork.maya:
        String digits = raw.replaceAll(RegExp(r'\D'), '');
        // E.164 (`+63917…`) normalises back to the 0-prefixed local form so
        // both spellings mask identically.
        if (digits.startsWith('63') && digits.length == 12) {
          digits = '0${digits.substring(2)}';
        }
        if (digits.length < 7) return digits;
        return '${digits.substring(0, 4)}****${digits.substring(digits.length - 3)}';
      case PaymentNetwork.card:
        final String tail = tailOf(raw);
        return tail.length == 4 ? '**** **** $tail' : '****$tail';
      case PaymentNetwork.bankTransfer:
        return '****${tailOf(raw)}';
    }
  }

  /// Last four digits of [raw], the value [PaymentAccount.tail] stores.
  static String tailOf(String raw) {
    final String digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 4) return digits;
    return digits.substring(digits.length - 4);
  }

  /// Rough brand guess from the card number's leading digit. Display only —
  /// the gateway's brand is the one that matters.
  static String? brandOfCard(String raw) {
    final String digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    return switch (digits[0]) {
      '4' => 'Visa',
      '5' || '2' => 'Mastercard',
      '3' => 'Amex',
      '6' => 'Discover',
      _ => null,
    };
  }
}