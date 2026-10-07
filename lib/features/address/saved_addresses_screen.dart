import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/bw_colors.dart';
import '../../core/theme/bw_metrics.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/bw_badge.dart';
import '../../core/widgets/bw_button.dart';
import '../../core/widgets/bw_card.dart';
import '../../data/models/coverage.dart';
import '../../data/models/order.dart';
import '../../state/catalog_provider.dart';
import '../../state/session_provider.dart';
import 'address_form_screen.dart';

/// Profile's "Saved Addresses": the customer's saved Home/Work/Other addresses
/// with add, edit, delete and set-default controls.
///
/// The same [AddressFormScreen] backs both this screen and the cart's quick-add
/// flow; the difference is only what the caller does with the returned address.
class SavedAddressesScreen extends StatelessWidget {
  const SavedAddressesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final SessionProvider session = context.watch<SessionProvider>();
    final DeliveryPricing pricing = context.watch<CatalogProvider>().pricing;
    final List<SavedAddress> addresses = session.addresses;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Addresses'),
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
              child: addresses.isEmpty
                  ? _EmptyState(onAdd: () => _openForm(context))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        BwSpacing.gutter,
                        BwSpacing.lg,
                        BwSpacing.gutter,
                        BwSpacing.lg,
                      ),
                      children: <Widget>[
                        for (final SavedAddress a in addresses)
                          Padding(
                            padding: const EdgeInsets.only(bottom: BwSpacing.md),
                            child: _AddressCard(
                              address: a,
                              pricing: pricing,
                              onEdit: () => _openForm(context, initial: a),
                              onDelete: () => _confirmDelete(context, a),
                            ),
                          ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(BwSpacing.gutter, 0, BwSpacing.gutter, BwSpacing.lg),
              child: BwButton(
                label: 'Add new address',
                icon: Icons.add_location_alt_outlined,
                onPressed: () => _openForm(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, {SavedAddress? initial}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => AddressFormScreen(initial: initial)),
    );
  }

  Future<void> _confirmDelete(BuildContext context, SavedAddress address) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: BwColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BwRadius.card)),
        title: Text(
          'Delete ${address.label}?',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: BwColors.text),
        ),
        content: Text(
          '${address.street}, ${LumbanCoverage.byCode(address.barangayCode)?.name ?? address.barangayCode} '
          'will be removed from your saved delivery addresses.',
          style: const TextStyle(fontSize: 14, height: 1.45, color: BwColors.textMuted),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: BwColors.text)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: BwColors.text, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      context.read<SessionProvider>().removeAddress(address.id);
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
            const Icon(Icons.location_off_outlined, size: 46, color: BwColors.borderStrong),
            const SizedBox(height: BwSpacing.lg),
            const Text(
              'No saved addresses yet',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: BwColors.text),
            ),
            const SizedBox(height: BwSpacing.sm),
            const Text(
              'Save your home or work address once, and pick it in seconds '
              'every time you order.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, height: 1.45, color: BwColors.textMuted),
            ),
            const SizedBox(height: BwSpacing.xl),
            BwButton(
              label: 'Add your first address',
              icon: Icons.add_location_alt_outlined,
              expand: false,
              onPressed: onAdd,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.address,
    required this.pricing,
    required this.onEdit,
    required this.onDelete,
  });

  final SavedAddress address;
  final DeliveryPricing pricing;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final double? km = address.distanceKm(cafeLat: pricing.cafeLat, cafeLng: pricing.cafeLng);
    final Barangay? barangay = LumbanCoverage.byCode(address.barangayCode);

    return BwCard(
      padding: const EdgeInsets.all(BwSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                switch (address.label) {
                  'Home' => Icons.home_outlined,
                  'Work' => Icons.business_outlined,
                  _ => Icons.place_outlined,
                },
                size: 18,
                color: BwColors.text,
              ),
              const SizedBox(width: BwSpacing.sm),
              Expanded(
                child: Text(
                  address.label,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: BwColors.text),
                ),
              ),
              if (address.isDefault)
                const Padding(
                  padding: EdgeInsets.only(right: BwSpacing.sm),
                  child: BwBadge(label: 'Default', variant: BwBadgeVariant.outline, dense: true),
                ),
              _RowAction(icon: Icons.edit_outlined, tooltip: 'Edit ${address.label}', onTap: onEdit),
              const SizedBox(width: BwSpacing.xs),
              _RowAction(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Delete ${address.label}',
                color: BwColors.textMuted,
                onTap: onDelete,
              ),
            ],
          ),
          const SizedBox(height: BwSpacing.sm),
          Text(
            address.street,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: BwColors.text),
          ),
          Text(
            barangay?.name ?? address.barangayCode,
            style: const TextStyle(fontSize: 12.5, color: BwColors.textMuted),
          ),
          if (km != null) ...<Widget>[
            const SizedBox(height: BwSpacing.sm),
            Text(
              '${Fmt.distance(km)} from the café · ≈ ${Fmt.peso(pricing.feeFor(km: km, subtotal: 0))} delivery',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BwColors.textMuted),
            ),
          ],
          if (address.note != null && address.note!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              'Note: ${address.note}',
              style: const TextStyle(fontSize: 12, color: BwColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _RowAction extends StatelessWidget {
  const _RowAction({required this.icon, required this.tooltip, required this.onTap, this.color = BwColors.text});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: BwColors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(width: 32, height: 32, child: Icon(icon, size: 18, color: color)),
        ),
      ),
    );
  }
}