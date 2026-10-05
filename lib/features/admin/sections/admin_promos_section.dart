import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/bw_colors.dart';
import '../../../core/theme/bw_metrics.dart';
import '../../../core/widgets/bw_badge.dart';
import '../../../core/widgets/bw_card.dart';
import '../../../data/models/menu.dart';
import '../../../state/catalog_provider.dart';
import '../admin_dashboard_screen.dart';
import 'admin_overview_section.dart';
import 'admin_sheet_actions.dart';

/// The promotional banners shown in the customer app's "Best Offer" carousel.
///
/// A separate section rather than part of Inventory, because the two change for
/// different reasons and on different timescales: an item's price and stock move
/// daily, a promotion runs for a fortnight and then is deleted. Burying promo
/// editing inside the stock table meant the thing a café owner edits most often
/// had the most taps in front of it.
class AdminPromosSection extends StatefulWidget {
  const AdminPromosSection({super.key});

  @override
  State<AdminPromosSection> createState() => _AdminPromosSectionState();
}

class _AdminPromosSectionState extends State<AdminPromosSection> {
  /// Null means every promo, live and paused. Worth a filter because a café runs
  /// promos in seasons: without it the current one is buried under two finished
  /// ones the owner has not deleted yet.
  bool? _activeOnly;

  @override
  Widget build(BuildContext context) {
    final CatalogProvider catalog = context.watch<CatalogProvider>();
    final List<Promo> all = catalog.allPromos;

    final List<Promo> promos = _activeOnly == null
        ? all
        : all.where((Promo p) => p.active == _activeOnly).toList(growable: false);

    final int live = all.where((Promo p) => p.active).length;

    // The FAB is not an optional extra. Creating a promotion is the whole reason
    // this section exists -- an owner who can only edit and delete what is already
    // there still has to open the Firebase console to put the next offer up, which
    // is the problem this section was added to solve. Same affordance as
    // Inventory's "Add item", so the two merchandising screens behave alike.
    return Scaffold(
      backgroundColor: BwColors.bg,
      floatingActionButton: BwFab(
        label: 'Add promotion',
        icon: Icons.add_rounded,
        onPressed: () => showPromoFormSheet(context),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: BwSpacing.md),
            child: SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: BwSpacing.gutter),
                children: <Widget>[
                  _PromoChip(
                    label: 'All (${all.length})',
                    isSelected: _activeOnly == null,
                    onTap: () => setState(() => _activeOnly = null),
                  ),
                  _PromoChip(
                    label: 'Live ($live)',
                    isSelected: _activeOnly == true,
                    onTap: () => setState(() => _activeOnly = true),
                  ),
                  _PromoChip(
                    label: 'Paused (${all.length - live})',
                    isSelected: _activeOnly == false,
                    onTap: () => setState(() => _activeOnly = false),
                  ),
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BwSpacing.gutter,
              vertical: BwSpacing.md,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: AdminStat(
                    label: 'In the carousel',
                    value: '$live',
                    icon: Icons.local_offer_outlined,
                  ),
                ),
                const SizedBox(width: BwSpacing.sm),
                Expanded(
                  child: AdminStat(
                    // "Not running" rather than "Paused", because the same word is
                    // the badge on each card and the filter chip. Three identical
                    // labels on one screen makes the stat untestable and is just
                    // as confusing to the person reading it.
                    label: 'Not running',
                    value: '${all.length - live}',
                    icon: Icons.pause_circle_outline_rounded,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: promos.isEmpty
                ? const AdminEmptyState(
                    message: 'No promotions here yet.',
                    icon: Icons.local_offer_outlined,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      BwSpacing.gutter,
                      0,
                      BwSpacing.gutter,
                      BwSpacing.xxl,
                    ),
                    itemCount: promos.length,
                    separatorBuilder: (_, _) => const SizedBox(height: BwSpacing.sm),
                    itemBuilder: (BuildContext context, int i) => _PromoCard(promo: promos[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PromoCard extends StatelessWidget {
  const _PromoCard({required this.promo});

  final Promo promo;

  @override
  Widget build(BuildContext context) {
    return BwCard(
      padding: const EdgeInsets.all(BwSpacing.md),
      child: Row(
        children: <Widget>[
          // Mirrors the customer's hero slide: black card when live, grey when
          // paused, so the operator sees the same distinction the customer does.
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: promo.active ? BwColors.inverse : BwColors.subtle,
              borderRadius: BorderRadius.circular(BwRadius.chip),
              border: Border.all(
                color: promo.active ? BwColors.inverse : BwColors.border,
              ),
            ),
            child: Icon(
              Icons.local_offer_outlined,
              size: 20,
              color: promo.active ? BwColors.onInverse : BwColors.textMuted,
            ),
          ),
          const SizedBox(width: BwSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  promo.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: BwColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  promo.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    color: BwColors.textMuted,
                  ),
                ),
                const SizedBox(height: BwSpacing.sm),
                Row(
                  children: <Widget>[
                    BwBadge(
                      label: promo.active ? 'Live' : 'Paused',
                      variant: BwBadgeVariant.solid,
                      icon: promo.active
                          ? Icons.play_circle_outline_rounded
                          : Icons.pause_circle_outline_rounded,
                      dense: true,
                    ),
                    const SizedBox(width: BwSpacing.xs),
                    Flexible(
                      child: Text(
                        promo.code,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.4,
                          fontWeight: FontWeight.w600,
                          color: BwColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: BwSpacing.sm),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Pause is a first-class button rather than something buried in the
              // edit sheet. Ending a promotion is the most frequent action on
              // this screen and it must not require opening a form.
              IconButton(
                icon: Icon(
                  promo.active ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded,
                  size: 18,
                ),
                tooltip: '${promo.active ? 'Pause' : 'Resume'} ${promo.title}',
                visualDensity: VisualDensity.compact,
                onPressed: () => context.read<CatalogProvider>().upsertPromo(
                      Promo(
                        code: promo.code,
                        title: promo.title,
                        subtitle: promo.subtitle,
                        badge: promo.badge,
                        ctaLabel: promo.ctaLabel,
                        discountPercent: promo.discountPercent,
                        buyXGetY: promo.buyXGetY,
                        active: !promo.active,
                      ),
                    ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Edit ${promo.title}',
                visualDensity: VisualDensity.compact,
                onPressed: () => showPromoFormSheet(context, existing: promo),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                tooltip: 'Remove ${promo.title}',
                visualDensity: VisualDensity.compact,
                onPressed: () => _confirmDelete(context, promo),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Promo promo) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: BwColors.surface,
        surfaceTintColor: BwColors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BwRadius.card),
          side: const BorderSide(color: BwColors.border),
        ),
        title: const Text(
          'Remove promotion',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: BwColors.text),
        ),
        content: Text(
          'Delete ${promo.title}? Customers will stop seeing it immediately.\n\n'
          'If it is only ending for now, pause it instead — a paused promo stays '
          'in the list so you can bring it back.',
          style: const TextStyle(fontSize: 14, height: 1.45, color: BwColors.textMuted),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    context.read<CatalogProvider>().removePromo(promo.code);
  }
}

class _PromoChip extends StatelessWidget {
  const _PromoChip({required this.label, required this.isSelected, required this.onTap});

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: BwSpacing.sm),
      child: Material(
        color: isSelected ? BwColors.inverse : BwColors.surface,
        borderRadius: BorderRadius.circular(BwRadius.pill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(BwRadius.pill),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: BwSpacing.md, vertical: BwSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BwRadius.pill),
              border: Border.all(
                color: isSelected ? BwColors.inverse : BwColors.borderStrong,
                width: BwStroke.strong,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: isSelected ? BwColors.onInverse : BwColors.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the form collected.
@immutable
class PromoDraft {
  const PromoDraft({
    required this.code,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.ctaLabel,
    required this.discountPercent,
    required this.active,
  });

  final String code;
  final String title;
  final String subtitle;
  final String? badge;
  final String? ctaLabel;
  final int? discountPercent;
  final bool active;
}

/// Opens the add/edit sheet and pushes the result into [CatalogProvider].
///
/// Top-level rather than a private method because the section is the only caller
/// today, but a promo editor is also the natural thing to hang off a promo's
/// detail sheet in the customer app if the owner ever asks for it.
Future<void> showPromoFormSheet(BuildContext context, {Promo? existing}) async {
  final CatalogProvider catalog = context.read<CatalogProvider>();

  final PromoDraft? draft = await showModalBottomSheet<PromoDraft>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PromoFormSheet(existing: existing),
  );

  if (draft == null) return;

  catalog.upsertPromo(
    Promo(
      code: draft.code,
      title: draft.title,
      subtitle: draft.subtitle,
      badge: draft.badge,
      ctaLabel: draft.ctaLabel,
      discountPercent: draft.discountPercent,
      // Buy-one-get-one has no dedicated field on the model, so it rides in the
      // badge like every other promo. Round-tripping through the badge rather than
      // dropping it keeps an edit from silently erasing the offer.
      buyXGetY: existing?.buyXGetY,
      active: draft.active,
    ),
  );

  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(existing == null ? 'Added ${draft.title}' : 'Updated ${draft.title}')),
    );
}

class _PromoFormSheet extends StatefulWidget {
  const _PromoFormSheet({required this.existing});

  final Promo? existing;

  @override
  State<_PromoFormSheet> createState() => _PromoFormSheetState();
}

class _PromoFormSheetState extends State<_PromoFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _code =
      TextEditingController(text: widget.existing?.code ?? _suggestCode());
  late final TextEditingController _title = TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _subtitle =
      TextEditingController(text: widget.existing?.subtitle ?? '');
  late final TextEditingController _badge =
      TextEditingController(text: widget.existing?.badge ?? '');
  late final TextEditingController _cta =
      TextEditingController(text: widget.existing?.ctaLabel ?? 'Order Now');
  late final TextEditingController _discount = TextEditingController(
    text: widget.existing?.discountPercent == null ? '' : '${widget.existing!.discountPercent}',
  );

  late bool _active = widget.existing?.active ?? true;

  /// The code is the Firestore document id, so an existing one must not be
  /// editable: changing it would write a second document and orphan the first.
  /// Only a brand-new promo's code can be typed.
  late final bool _codeLocked = widget.existing != null;

  @override
  void dispose() {
    _code.dispose();
    _title.dispose();
    _subtitle.dispose();
    _badge.dispose();
    _cta.dispose();
    _discount.dispose();
    super.dispose();
  }

  /// A code the owner is unlikely to have used, derived from the title if there
  /// is one. Better than an empty field, because an empty code would collide with
  /// every other empty promo on the first save.
  static String _suggestCode() {
    final int stamp = DateTime.now().millisecondsSinceEpoch;
    return 'PROMO${stamp.toString().substring(stamp.toString().length - 6)}';
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    Navigator.of(context).pop(
      PromoDraft(
        code: _code.text.trim().toUpperCase(),
        title: _title.text.trim(),
        subtitle: _subtitle.text.trim(),
        badge: _badge.text.trim().isEmpty ? null : _badge.text.trim(),
        ctaLabel: _cta.text.trim().isEmpty ? null : _cta.text.trim(),
        discountPercent: int.tryParse(_discount.text.trim()),
        active: _active,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool editing = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Padding(
                padding: const EdgeInsets.all(BwSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      editing ? 'Edit promotion' : 'Add promotion',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: BwColors.text,
                      ),
                    ),
                    const SizedBox(height: BwSpacing.xl),

                    TextFormField(
                      controller: _code,
                      enabled: !_codeLocked,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(fontSize: 15, color: BwColors.text),
                      decoration: InputDecoration(
                        labelText: 'Promo code',
                        helperText: _codeLocked
                            ? 'The code identifies this promotion and cannot be changed'
                            : 'Short and unique, e.g. SUMMER25',
                        helperMaxLines: 2,
                      ),
                      validator: (String? v) {
                        final String value = (v ?? '').trim();
                        if (value.isEmpty) return 'Enter a code.';
                        if (!_codeLocked &&
                            value != value.toUpperCase()) {
                          return 'Use capitals only.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: BwSpacing.md),

                    TextFormField(
                      controller: _title,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(fontSize: 15, color: BwColors.text),
                      decoration: const InputDecoration(labelText: 'Headline'),
                      validator: (String? v) =>
                          (v ?? '').trim().isEmpty ? 'Enter a headline.' : null,
                    ),
                    const SizedBox(height: BwSpacing.md),

                    TextFormField(
                      controller: _subtitle,
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 15, color: BwColors.text),
                      decoration: const InputDecoration(
                        labelText: 'Sub-copy',
                        helperText: 'The small line under the headline on the slide',
                      ),
                      validator: (String? v) =>
                          (v ?? '').trim().isEmpty ? 'Enter a sub-line.' : null,
                    ),
                    const SizedBox(height: BwSpacing.md),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: TextFormField(
                            controller: _badge,
                            textCapitalization: TextCapitalization.characters,
                            style: const TextStyle(fontSize: 15, color: BwColors.text),
                            decoration: const InputDecoration(
                              labelText: 'Badge (optional)',
                              hintText: 'NEW',
                            ),
                          ),
                        ),
                        const SizedBox(width: BwSpacing.sm),
                        Expanded(
                          child: TextFormField(
                            controller: _discount,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 15, color: BwColors.text),
                            decoration: const InputDecoration(
                              labelText: 'Discount %',
                              suffixText: '%',
                            ),
                            validator: (String? v) {
                              if ((v ?? '').trim().isEmpty) return null;
                              final int? parsed = int.tryParse(v!.trim());
                              if (parsed == null || parsed <= 0 || parsed > 100) {
                                return '0–100.';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: BwSpacing.md),

                    TextFormField(
                      controller: _cta,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(fontSize: 15, color: BwColors.text),
                      decoration: const InputDecoration(
                        labelText: 'Button label (optional)',
                        helperText: 'Shown on the white button on the slide',
                      ),
                    ),
                    const SizedBox(height: BwSpacing.md),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: BwSpacing.md,
                        vertical: BwSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(BwRadius.field),
                        border: Border.all(color: BwColors.border),
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const Text(
                                  'Show in the carousel',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: BwColors.text,
                                  ),
                                ),
                                Text(
                                  _active ? 'Live for customers' : 'Paused, still listed here',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: BwColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _active,
                            onChanged: (bool v) => setState(() => _active = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: BwSpacing.xl),

                    AdminSheetActions(
                      submitLabel: editing ? 'Save changes' : 'Add promotion',
                      onSubmit: _submit,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
