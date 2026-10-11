import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlanders_coffee/app.dart';
import 'package:highlanders_coffee/core/firebase/firebase_bootstrap.dart';
import 'package:highlanders_coffee/core/widgets/bw_card.dart';
import 'package:highlanders_coffee/data/models/payment.dart';
import 'package:highlanders_coffee/features/payment_methods/link_payment_screen.dart';
import 'package:highlanders_coffee/features/payment_methods/payment_methods_screen.dart';
import 'package:highlanders_coffee/features/shell/app_shell.dart';
import 'package:highlanders_coffee/features/shell/bw_bottom_nav.dart';
import 'package:highlanders_coffee/services/payment_gateway.dart';
import 'package:highlanders_coffee/state/session_provider.dart';

/// A gateway whose link always fails, standing in for the real Cloud Function
/// declining a payment method. Exercises the form's SnackBar error path.
class _FailingGateway implements PaymentGateway {
  const _FailingGateway();

  @override
  Future<PaymentLinkResult> link(PaymentLinkRequest request) async {
    throw const GatewayException('The bank declined this account.');
  }
}

/// The payment-methods feature: PH-mobile masking/validation, the session
/// vault (default handling, set-default, unlink) and the Profile list + link
/// flows that drive it.
///
/// Widget flows ride the real provider graph (via [HighlandersApp]) so the
/// mock gateway and the session store are exercised together, not stubbed.
void main() {
  /// A Pixel-ish portrait surface: 360 x 780 logical.
  Future<void> usePhone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpApp(WidgetTester tester, {Widget? home}) async {
    ShellNav.reset();
    FirebaseBootstrap.resetForTest();
    await tester.pumpWidget(HighlandersApp(home: home));
    await tester.pumpAndSettle();
  }

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(of: find.byType(BwBottomNav), matching: find.text(label)),
    );
    await tester.pumpAndSettle();
  }

  /// Profile tab -> the payment methods list screen.
  Future<void> openPaymentMethods(WidgetTester tester) async {
    await tapTab(tester, 'Profile');
    await tester.ensureVisible(find.text('Payment Methods'));
    await tester.tap(find.text('Payment Methods'));
    await tester.pumpAndSettle();
  }

  /// Drags the form's ListView until [target] exists, then taps it.
  Future<void> revealForTap(WidgetTester tester, Finder target) async {
    final Finder list = find.byType(ListView).first;
    for (int i = 0; i < 10 && !tester.any(target); i++) {
      await tester.drag(list, const Offset(0, -240));
      await tester.pumpAndSettle();
    }
    if (!tester.any(target)) return;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
  }

  PaymentAccount seedAccount({
    String id = 'pm-seed',
    String holderName = 'Marco Reyes',
    PaymentNetwork network = PaymentNetwork.gcash,
    bool isDefault = false,
  }) {
    return PaymentAccount(
      id: id,
      network: network,
      holderName: holderName,
      accountLabel: network.isMobileWallet ? '0917****000' : '**** 0000',
      tail: '0000',
      isDefault: isDefault,
      linkedAt: DateTime(2026, 9, 2),
      gatewayId: 'mock-pm-1',
    );
  }

  group('payment format helpers', () {
    test('isValidPhMobile accepts the 09 and +639 spellings only', () {
      expect(PaymentAccount.isValidPhMobile('0917 123 4567'), isTrue);
      expect(PaymentAccount.isValidPhMobile('+639171234567'), isTrue);
      expect(PaymentAccount.isValidPhMobile('0917-123-4567'), isTrue);
      expect(PaymentAccount.isValidPhMobile('0917123456'), isFalse);
      expect(PaymentAccount.isValidPhMobile('12345678901'), isFalse);
      expect(PaymentAccount.isValidPhMobile(''), isFalse);
    });

    test('mobile numbers mask as 0917****last3 and stick to one shape', () {
      // Both the long and the +63 spelling collapse to the same 0-prefixed
      // label, so two wallets owned by one person never look different.
      expect(PaymentAccount.maskOf(PaymentNetwork.gcash, '09179123123'), '0917****123');
      expect(PaymentAccount.maskOf(PaymentNetwork.maya, '+639171234567'), '0917****567');
      expect(PaymentAccount.maskOf(PaymentNetwork.maya, '0917 777 8888'), '0917****888');
    });

    test('cards and bank accounts expose only the last four digits', () {
      expect(PaymentAccount.maskOf(PaymentNetwork.card, '4242424242424242'), '**** **** 4242');
      expect(
        PaymentAccount.maskOf(PaymentNetwork.bankTransfer, '1234567890123456'),
        '****3456',
      );
      expect(PaymentAccount.tailOf('4242424242421111'), '1111');
    });

    test('card brand encodes the leading digit, unknown otherwise', () {
      expect(PaymentAccount.brandOfCard('4242424242424242'), 'Visa');
      expect(PaymentAccount.brandOfCard('5356 1234 5678 9012'), 'Mastercard');
      expect(PaymentAccount.brandOfCard('0000000000000000'), isNull);
    });
  });

  group('session payment store', () {
    // A fresh SessionProvider seeds the two MockData wallets — pm-gcash
    // (default) and pm-maya — so these assertions are written against that,
    // exactly like the address-store tests.
    test('addPaymentAccount links a new account', () {
      final SessionProvider session = SessionProvider();

      session.addPaymentAccount(
        seedAccount(id: 'pm-new', network: PaymentNetwork.bankTransfer),
      );

      expect(session.paymentAccounts, hasLength(3));
      expect(session.paymentAccountById('pm-new')?.network, PaymentNetwork.bankTransfer);
      // The seeded default is untouched by a non-default link.
      expect(session.defaultPaymentAccount?.id, 'pm-gcash');
    });

    test('addPaymentAccount replaces an existing id instead of duplicating', () {
      final SessionProvider session = SessionProvider();

      session.addPaymentAccount(seedAccount(id: 'pm-gcash', isDefault: true, holderName: 'New Name'));

      expect(session.paymentAccounts, hasLength(2));
      expect(session.paymentAccountById('pm-gcash')?.holderName, 'New Name');
      expect(session.paymentAccountById('pm-gcash')?.isDefault, isTrue);
    });

    test('a new default clears the previous default', () {
      final SessionProvider session = SessionProvider();
      final PaymentAccount maya = session.paymentAccountById('pm-maya')!;

      session.addPaymentAccount(maya.copyWith(isDefault: true));

      expect(session.paymentAccounts.where((PaymentAccount a) => a.isDefault), hasLength(1));
      expect(session.defaultPaymentAccount?.id, 'pm-maya');
      expect(session.paymentAccountById('pm-gcash')?.isDefault, isFalse);
    });

    test('setDefaultPaymentAccount promotes and demotes exactly one', () {
      final SessionProvider session = SessionProvider();

      session.setDefaultPaymentAccount('pm-maya');
      expect(session.defaultPaymentAccount?.id, 'pm-maya');
      expect(
        session.paymentAccounts.where((PaymentAccount a) => a.isDefault),
        hasLength(1),
      );

      // Already-default is a no-op, and an unknown id is ignored.
      session.setDefaultPaymentAccount('pm-maya');
      session.setDefaultPaymentAccount('pm-nobody');
      expect(session.defaultPaymentAccount?.id, 'pm-maya');
    });

    test('removing the default falls back to the first remaining account', () {
      final SessionProvider session = SessionProvider();

      session.removePaymentAccount('pm-gcash');
      expect(session.paymentAccounts, hasLength(1));
      expect(session.defaultPaymentAccount?.id, 'pm-maya');
    });
  });

  group('payment methods screens', () {
    testWidgets('profile opens the list with masked numbers and one default badge',
        (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester);

      await openPaymentMethods(tester);

      expect(find.byType(PaymentMethodsScreen), findsOneWidget);
      // The two seeded wallets show their masked labels and holder.
      expect(find.text('0917****000'), findsOneWidget);
      expect(find.text('0917****123'), findsOneWidget);
      expect(find.text('Marco Reyes'), findsNWidgets(2));
      // Only the seeded GCash carries the badge.
      expect(find.text('Default'), findsOneWidget);
    });

    testWidgets('an invalid PH mobile is rejected without leaving the form',
        (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester);

      await openPaymentMethods(tester);
      await tester.tap(find.text('Add payment method'));
      await tester.pumpAndSettle();
      expect(find.byType(LinkPaymentScreen), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name on the account'),
        'Marco Reyes',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'PH mobile number'),
        '12345',
      );
      await revealForTap(tester, find.text('Link payment method'));
      await tester.pumpAndSettle();

      // Still on the form, with the PH-specific message.
      expect(find.byType(LinkPaymentScreen), findsOneWidget);
      expect(find.textContaining('valid PH mobile number'), findsOneWidget);
      expect(find.byType(PaymentMethodsScreen), findsNothing);
    });

    testWidgets('adding a GCash wallet links it and shows the masked number',
        (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester);

      await openPaymentMethods(tester);
      await tester.tap(find.text('Add payment method'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name on the account'),
        'Marco Reyes',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'PH mobile number'),
        '0917 777 8888',
      );
      await revealForTap(tester, find.text('Link payment method'));
      await tester.pumpAndSettle();

      // Back on the list: the new mask is there, and the default badge stayed
      // on the original account (a brand-new default is not forced when a
      // default already exists).
      expect(find.byType(PaymentMethodsScreen), findsOneWidget);
      expect(find.text('0917****888'), findsOneWidget);
      expect(find.text('0917****000'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);
    });

    testWidgets('linking a card masks the PAN and shows its brand',
        (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester);

      await openPaymentMethods(tester);
      await tester.tap(find.text('Add payment method'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Debit/Credit Card'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name on the account'),
        'Marco Reyes',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Card number'),
        '4242 4242 4242 4242',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Expiry'),
        '12/29',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'CVC'),
        '123',
      );
      await revealForTap(tester, find.text('Link payment method'));
      await tester.pumpAndSettle();

      expect(find.byType(PaymentMethodsScreen), findsOneWidget);
      expect(find.text('**** **** 4242'), findsOneWidget);
      // The display-only brand guess is surfaced in the card's caption.
      expect(find.textContaining('Visa'), findsOneWidget);
    });

    testWidgets('a declined link surfaces the gateway message without leaving the form',
        (WidgetTester tester) async {
      await usePhone(tester);
      // The injected gateway plays the real Cloud Function refusing the link;
      // the form must stay put and show the provider's message in a SnackBar.
      await pumpApp(
        tester,
        home: LinkPaymentScreen(gateway: const _FailingGateway()),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name on the account'),
        'Marco Reyes',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'PH mobile number'),
        '0917 123 4567',
      );
      await revealForTap(tester, find.text('Link payment method'));
      await tester.pumpAndSettle();

      expect(find.byType(LinkPaymentScreen), findsOneWidget);
      expect(find.text('The bank declined this account.'), findsOneWidget);
      expect(find.byType(PaymentMethodsScreen), findsNothing);
    });

    testWidgets('set as default moves the badge to the chosen account',
        (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester);

      await openPaymentMethods(tester);

      final Finder mayaCard = find
          .ancestor(of: find.text('0917****123'), matching: find.byType(BwCard))
          .first;
      await tester.tap(find.descendant(of: mayaCard, matching: find.text('Set as default')));
      await tester.pumpAndSettle();

      expect(find.text('Default'), findsOneWidget);
      final Finder badgeCard = find
          .ancestor(of: find.text('Default'), matching: find.byType(BwCard))
          .first;
      expect(
        find.descendant(of: badgeCard, matching: find.text('0917****123')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: badgeCard, matching: find.text('0917****000')),
        findsNothing,
      );
    });

    testWidgets('unlink removes the account only after confirmation',
        (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester);

      await openPaymentMethods(tester);

      // Cancel keeps the account.
      final Finder gcashCard = find
          .ancestor(of: find.text('0917****000'), matching: find.byType(BwCard))
          .first;
      await tester.tap(find.descendant(of: gcashCard, matching: find.text('Unlink')));
      await tester.pumpAndSettle();
      expect(find.text('Unlink GCash?'), findsOneWidget);

      final Finder dialog = find.byType(AlertDialog);
      await tester.tap(find.descendant(of: dialog, matching: find.text('Cancel')));
      await tester.pumpAndSettle();
      expect(find.text('0917****000'), findsOneWidget);

      // Confirm removes it, and the remaining account becomes the default.
      await tester.tap(find.descendant(of: gcashCard, matching: find.text('Unlink')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Unlink')));
      await tester.pumpAndSettle();

      expect(find.text('0917****000'), findsNothing);
      expect(find.text('0917****123'), findsOneWidget);
      // No account carries the default flag after the only default was
      // unlinked — same semantics as the Saved Addresses list — so no badge,
      // and the remaining account offers to become default.
      expect(find.text('Default'), findsNothing);
      expect(find.text('Set as default'), findsOneWidget);
    });
  });
}