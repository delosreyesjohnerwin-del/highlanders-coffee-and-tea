import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/bw_colors.dart';
import '../../core/theme/bw_metrics.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/bw_badge.dart';
import '../../core/widgets/bw_button.dart';
import '../../core/widgets/bw_card.dart';
import '../../data/models/payment.dart';
import '../../state/session_provider.dart';
import 'link_payment_screen.dart';

/// Profile's "Payment Methods": the customer's linked wallets, cards and bank
/// accounts with masked numbers, a Default badge, set-default and unlink
/// controls.
///
/// Mirrors [SavedAddressesScreen] end-to-end: the same card/list rhythm, the
/// same `ListView` + bottom action button pattern and the same confirm-dialog
/// deletion. The add flow lives in [LinkPaymentScreen].
class PaymentMethodsScreen extends StatelessWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final SessionProvider session = context.watch<SessionProvider>();
    final List<PaymentAccount> accounts = session.paymentAccounts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Methods'),
        leading: BwIconButton(
          icon: Icons.arrow_back_rounded,
          onPressed: () => Navigator.of(context).pop(),
          bordered: false,
          background: BwColors.transparent,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: accounts.isEmpty
                  ? _EmptyState(onAdd: () => _openLink(context))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        BwSpacing.gutter,
                        BwSpacing.lg,
                        BwSpacing.gutter,
                        BwSpacing.lg,
                      ),
                      children: <Widget>[
                        for (final PaymentAccount account in accounts)
                          Padding(
                            padding: const EdgeInsets.only(bottom: BwSpacing.md),
                            child: _PaymentAccountCard(
                              account: account,
                              onSetDefault: () => _setDefault(context, account),
                              onUnlink: () => _confirmUnlink(context, account),
                            ),
                          ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(BwSpacing.gutter, 0, BwSpacing.gutter, BwSpacing.lg),
              child: BwButton(
                label: 'Add payment method',
                icon: Icons.add_card_outlined,
                onPressed: () => _openLink(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openLink(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const LinkPaymentScreen()),
    );
  }

  void _setDefault(BuildContext context, PaymentAccount account) {
    context.read<SessionProvider>().setDefaultPaymentAccount(account.id);
  }

  Future<void> _confirmUnlink(BuildContext context, PaymentAccount account) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: BwColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BwRadius.card)),
        title: Text(
          'Unlink ${account.network.label}?',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: BwColors.text),
        ),
        content: Text(
          '${account.accountLabel} will be removed from your saved payment methods.',
          style: const TextStyle(fontSize: 14, height: 1.45, color: BwColors.textMuted),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: BwColors.text)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Unlink', style: TextStyle(color: BwColors.text, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      context.read<SessionProvider>().removePaymentAccount(account.id);
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: BwSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.account_balance_wallet_outlined, size: 46, color: BwColors.borderStrong),
            const SizedBox(height: BwSpacing.lg),
            const Text(
              'No payment methods yet',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: BwColors.text),
            ),
            const SizedBox(height: BwSpacing.sm),
            const Text(
              'Link a wallet, card or bank account once and skip retyping '
              'your details every time you order.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, height: 1.45, color: BwColors.textMuted),
            ),
            const SizedBox(height: BwSpacing.xl),
            BwButton(
              label: 'Link your first payment method',
              icon: Icons.add_card_outlined,
              expand: false,
              onPressed: onAdd,
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentAccountCard extends StatelessWidget {
  const _PaymentAccountCard({
    required this.account,
    required this.onSetDefault,
    required this.onUnlink,
  });

  final PaymentAccount account;
  final VoidCallback onSetDefault;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    return BwCard(
      padding: const EdgeInsets.all(BwSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _NetworkMark(network: account.network),
              const SizedBox(width: BwSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      account.holderName,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: BwColors.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      account.accountLabel,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: BwColors.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // Cards carry a display-only brand guess (Visa, …); the
                      // e-wallets and bank accounts show their network name.
                      '${account.cardBrand ?? account.network.label} · Linked ${Fmt.date(account.linkedAt)}',
                      style: const TextStyle(fontSize: 12, color: BwColors.textMuted),
                    ),
                  ],
                ),
              ),
              if (account.isDefault)
                const Padding(
                  padding: EdgeInsets.only(left: BwSpacing.sm),
                  child: BwBadge(label: 'Default', variant: BwBadgeVariant.outline, dense: true),
                ),
            ],
          ),
          const SizedBox(height: BwSpacing.sm),
          Divider(height: 1, color: BwColors.border),
          const SizedBox(height: BwSpacing.xs),
          Wrap(
            spacing: BwSpacing.sm,
            runSpacing: 0,
            children: <Widget>[
              if (!account.isDefault)
                TextButton.icon(
                  onPressed: onSetDefault,
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                  label: const Text('Set as default'),
                  style: TextButton.styleFrom(
                    foregroundColor: BwColors.text,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              TextButton.icon(
                onPressed: onUnlink,
                icon: const Icon(Icons.link_off_rounded, size: 16),
                label: const Text('Unlink'),
                style: TextButton.styleFrom(
                  foregroundColor: BwColors.textMuted,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Fixed chip that stands in for the network's brand logo; a real artwork
/// swap later is a one-line change (an `Image` in place of the [Icon]).
class _NetworkMark extends StatelessWidget {
  const _NetworkMark({required this.network});

  final PaymentNetwork network;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: BwColors.subtle,
        borderRadius: BorderRadius.circular(BwRadius.card),
        border: Border.all(color: BwColors.border),
      ),
      child: Icon(network.icon, size: 22, color: BwColors.text),
    );
  }
}