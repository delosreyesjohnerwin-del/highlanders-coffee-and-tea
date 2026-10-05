import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/firebase/firebase_bootstrap.dart';
import '../../../core/theme/bw_colors.dart';
import '../../../core/theme/bw_metrics.dart';
import '../../../core/widgets/bw_badge.dart';
import '../../../core/widgets/bw_button.dart';
import '../../../core/widgets/bw_card.dart';
import '../../../data/firestore/firestore_errors.dart';
import '../../../data/models/settings.dart';
import '../../../state/admin_provider.dart';
import '../../../state/catalog_provider.dart';
import '../../../state/session_provider.dart';
import '../admin_dashboard_screen.dart';

/// Store configuration and the auth backend's live state.
///
/// Fee tiers here are placeholders pending real numbers from the owner — the
/// same figures [MockData]'s delivery pricing uses, so changing them here
/// changes what the customer is quoted.
class AdminSettingsSection extends StatefulWidget {
  const AdminSettingsSection({super.key});

  @override
  State<AdminSettingsSection> createState() => _AdminSettingsSectionState();
}

class _AdminSettingsSectionState extends State<AdminSettingsSection> {
  /// True while a seed write is in flight. The button is disabled rather than
  /// hidden so its position does not shift the Sign out button below it.
  bool _seeding = false;

  /// Writes the sample data, then reports the outcome in a dialog.
  ///
  /// The dialog is not decoration. Seeding can legitimately refuse (orders
  /// already exist), and a refusal the operator cannot see reads as a button that
  /// does nothing.
  Future<void> _seed() async {
    setState(() => _seeding = true);

    final WriteFailure? failure =
        await context.read<AdminProvider>().seedFromMock();

    if (!mounted) return;
    setState(() => _seeding = false);

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: BwColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BwRadius.card)),
        title: Text(
          failure == null ? 'Sample data written' : 'Seed skipped',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: BwColors.text),
        ),
        content: Text(
          failure == null
              ? 'The sample menu, categories, promos and staff roster are now in Firestore. '
                  'Open the collections in the console and replace the contents with the '
                  "café's real menu."
              : failure.message,
          style: const TextStyle(fontSize: 14, height: 1.45, color: BwColors.textMuted),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close', style: TextStyle(color: BwColors.text)),
          ),
        ],
      ),
    );
  }

  /// [StoreSettings] is immutable, so an edit is expressed as a transform of
  /// the current value rather than a mutation. The old `copyWith` call was also
  /// redundant — `copyWith` already omits null fields, so passing every field
  /// back in bought nothing.
  void _update(StoreSettings Function(StoreSettings current) transform) {
    final AdminProvider admin = context.read<AdminProvider>();
    admin.updateSettings(transform(admin.settings));
  }

  @override
  Widget build(BuildContext context) {
    final AdminProvider admin = context.watch<AdminProvider>();
    final SessionProvider session = context.watch<SessionProvider>();
    final StoreSettings s = admin.settings;

    return ListView(
      padding: const EdgeInsets.only(bottom: BwSpacing.xxl),
      children: <Widget>[
        // --- open / closed -------------------------------------------------
        Padding(
          padding: const EdgeInsets.fromLTRB(
            BwSpacing.gutter,
            BwSpacing.lg,
            BwSpacing.gutter,
            0,
          ),
          child: BwCard(
            color: s.isOpen ? BwColors.surface : BwColors.subtle,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        s.isOpen ? 'Shop is open' : 'Shop is closed',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: BwColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${s.opensAt} – ${s.closesAt}',
                        style: const TextStyle(fontSize: 12.5, color: BwColors.textMuted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: s.isOpen,
                  onChanged: (bool v) => _update((StoreSettings s) => s.copyWith(isOpen: v)),
                ),
              ],
            ),
          ),
        ),

        const AdminSectionHeader(title: 'Shop details'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: BwSpacing.gutter),
          child: BwCard(
            child: Column(
              children: <Widget>[
                _LabeledField(
                  label: 'Café name',
                  value: s.cafeName,
                  onChanged: (String v) => _update((StoreSettings s) => s.copyWith(cafeName: v)),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: BwSpacing.sm),
                  child: Divider(height: 1),
                ),
                _LabeledField(
                  label: 'Address',
                  value: s.address,
                  onChanged: (String v) => _update((StoreSettings s) => s.copyWith(address: v)),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: BwSpacing.sm),
                  child: Divider(height: 1),
                ),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _LabeledField(
                        label: 'Opens',
                        value: s.opensAt,
                        onChanged: (String v) => _update((StoreSettings s) => s.copyWith(opensAt: v)),
                      ),
                    ),
                    const SizedBox(width: BwSpacing.sm),
                    Expanded(
                      child: _LabeledField(
                        label: 'Closes',
                        value: s.closesAt,
                        onChanged: (String v) => _update((StoreSettings s) => s.copyWith(closesAt: v)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const AdminSectionHeader(
          title: 'Delivery',
          subtitle: 'Placeholder tiers — confirm with the owner before launch',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: BwSpacing.gutter),
          child: BwCard(
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _NumberField(
                        label: 'Base fee',
                        prefix: '₱ ',
                        value: s.baseFee,
                        onChanged: (num v) => _update((StoreSettings s) => s.copyWith(baseFee: v)),
                      ),
                    ),
                    const SizedBox(width: BwSpacing.sm),
                    Expanded(
                      child: _NumberField(
                        label: 'Free over',
                        prefix: '₱ ',
                        value: s.freeOver,
                        onChanged: (num v) => _update((StoreSettings s) => s.copyWith(freeOver: v)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: BwSpacing.md),
                _NumberField(
                  label: 'Coverage radius',
                  suffix: ' km',
                  value: s.coverageRadiusKm,
                  onChanged: (num v) => _update((StoreSettings s) => s.copyWith(coverageRadiusKm: v.toDouble())),
                ),
                const SizedBox(height: BwSpacing.md),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Free delivery kicks in at ₱${s.freeOver}. Radius ${s.coverageRadiusKm} km '
                    'from the café.',
                    style: const TextStyle(fontSize: 12, height: 1.4, color: BwColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ),

        const AdminSectionHeader(title: 'Menu'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: BwSpacing.gutter),
          child: BwCard(
            child: Row(
              children: <Widget>[
                const Icon(Icons.inventory_2_outlined, size: 18, color: BwColors.textMuted),
                const SizedBox(width: BwSpacing.md),
                Expanded(
                  child: Text(
                    '${context.watch<CatalogProvider>().allItems.length} items listed',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: BwColors.text,
                    ),
                  ),
                ),
                BwBadge(
                  label: '${AdminProvider.needsRestock(context.watch<CatalogProvider>().allItems).length} need restock',
                  variant: BwBadgeVariant.outline,
                  dense: true,
                ),
              ],
            ),
          ),
        ),

        const AdminSectionHeader(title: 'Data'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: BwSpacing.gutter),
          child: BwCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      admin.isLive ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                      size: 16,
                      color: BwColors.textMuted,
                    ),
                    const SizedBox(width: BwSpacing.sm),
                    Expanded(
                      child: Text(
                        admin.isLive
                            ? (admin.hasLoaded ? 'Reading from Firestore' : 'Connecting…')
                            : 'Sample data — nothing is saved',
                        style: const TextStyle(fontSize: 13, color: BwColors.textMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: BwSpacing.md),
                Text(
                  admin.isLive
                      ? 'Menu, orders, staff and settings are read from Firestore and every '
                          'edit is written back. Seeding writes the sample menu and staff '
                          'roster once; it refuses if any order already exists.'
                      : 'No Firebase configuration, so the panel is showing sample data. '
                          'Edits work for this session and are gone when the app closes.',
                  style: const TextStyle(fontSize: 12, height: 1.45, color: BwColors.textMuted),
                ),
                if (admin.isLive) ...<Widget>[
                  const SizedBox(height: BwSpacing.md),
                  BwButton(
                    label: 'Seed sample data',
                    icon: Icons.download_outlined,
                    variant: BwButtonVariant.outlined,
                    height: 46,
                    onPressed: _seeding ? null : _seed,
                  ),
                ],
              ],
            ),
          ),
        ),

        const AdminSectionHeader(title: 'Session & backend'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: BwSpacing.gutter),
          child: BwCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        session.user.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: BwColors.text,
                        ),
                      ),
                    ),
                    BwBadge(
                      label: session.user.role.name,
                      variant: BwBadgeVariant.solid,
                      dense: true,
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: BwSpacing.sm),
                  child: Divider(height: 1),
                ),
                Row(
                  children: <Widget>[
                    Icon(
                      FirebaseBootstrap.isReady
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_off_outlined,
                      size: 16,
                      color: BwColors.textMuted,
                    ),
                    const SizedBox(width: BwSpacing.sm),
                    Expanded(
                      child: Text(
                        FirebaseBootstrap.isReady
                            ? 'Firebase connected'
                            : session.authService.unavailableReason,
                        style: const TextStyle(fontSize: 13, color: BwColors.textMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: BwSpacing.md),
                Text(
                  'Roles live in Firestore users/{uid}. To promote someone, edit that '
                  "document's role field to \"admin\" in the console and have them "
                  'sign out and back in.',
                  style: const TextStyle(fontSize: 12, height: 1.45, color: BwColors.textMuted),
                ),
                const SizedBox(height: BwSpacing.lg),
                BwButton(
                  label: 'Sign out',
                  icon: Icons.logout_rounded,
                  variant: BwButtonVariant.outlined,
                  height: 46,
                  onPressed: () => context.read<SessionProvider>().signOut(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Labelled single-line editor.
class _LabeledField extends StatefulWidget {
  const _LabeledField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_LabeledField> createState() => _LabeledFieldState();
}

class _LabeledFieldState extends State<_LabeledField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: BwColors.textMuted,
          ),
        ),
        const SizedBox(height: 2),
        TextField(
          controller: _c,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: BwColors.text),
          // Echo every keystroke straight to the store: this is a settings
          // screen, not a form with a Save button.
          onChanged: widget.onChanged,
        ),
      ],
    );
  }
}

/// Numeric variant, with an optional peso sign or unit suffix.
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.prefix,
    this.suffix,
  });

  final String label;
  final num value;
  final ValueChanged<num> onChanged;
  final String? prefix;
  final String? suffix;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _c = TextEditingController(text: _format(widget.value));

  static String _format(num v) =>
      v is int ? '$v' : v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: BwColors.textMuted,
          ),
        ),
        const SizedBox(height: 2),
        TextField(
          controller: _c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: BwColors.text),
          decoration: InputDecoration(
            prefixText: widget.prefix,
            suffixText: widget.suffix,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          ),
          onChanged: (String raw) {
            final num? parsed = num.tryParse(raw.trim());
            if (parsed == null || parsed < 0) return;
            widget.onChanged(parsed);
          },
        ),
      ],
    );
  }
}