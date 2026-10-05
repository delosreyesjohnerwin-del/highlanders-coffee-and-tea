import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/bw_colors.dart';
import '../../core/theme/bw_metrics.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/bw_badge.dart';
import '../../core/widgets/bw_button.dart';
import '../../core/widgets/bw_card.dart';
import '../../data/models/menu.dart';
import '../../state/cart_provider.dart';
import '../../state/catalog_provider.dart';

/// Item detail: large image, name, price, description, optional sizes and a
/// sticky add-to-cart bar.
class MenuItemDetailScreen extends StatefulWidget {
  const MenuItemDetailScreen({super.key, required this.item});

  final MenuItem item;

  @override
  State<MenuItemDetailScreen> createState() => _MenuItemDetailScreenState();
}

class _MenuItemDetailScreenState extends State<MenuItemDetailScreen> {
  int _qty = 1;
  String _size = 'Regular';

  static const List<({String label, num delta})> _sizes = <({num delta, String label})>[
    (label: 'Regular', delta: 0),
    (label: 'Large', delta: 15),
  ];

  num get _unitPrice =>
      widget.item.price + _sizes.firstWhere((({String label, num delta}) s) => s.label == _size).delta;

  @override
  Widget build(BuildContext context) {
    final MenuItem item = widget.item;
    final String categoryLabel = context.read<CatalogProvider>().labelForCategory(item.categoryId);
    final int inCart = context.select<CartProvider, int>((CartProvider c) => c.quantityOf(item.id));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: BwSpacing.gutter),
            child: Center(
              child: BwBadge(label: categoryLabel, variant: BwBadgeVariant.outline),
            ),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(BwSpacing.gutter, 0, BwSpacing.gutter, BwSpacing.xl),
              children: <Widget>[
                _ImagePanel(item: item),
                const SizedBox(height: BwSpacing.xl),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          height: 1.15,
                          color: BwColors.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: BwSpacing.md),
                    Text(
                      Fmt.peso(_unitPrice),
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: BwColors.text,
                      ),
                    ),
                  ],
                ),

                if (item.isBestseller) ...<Widget>[
                  const SizedBox(height: BwSpacing.md),
                  // Wrap, not Row: chips flow to the next line on narrow screens instead of
                  // overflowing.
                  Wrap(
                    spacing: BwSpacing.sm,
                    runSpacing: BwSpacing.sm,
                    children: <Widget>[
                      const BwBadge(
                        label: 'BESTSELLER',
                        icon: Icons.local_fire_department_outlined,
                      ),
                      BwBadge(
                        label: 'READY IN ${item.prepMinutes} MIN',
                        variant: BwBadgeVariant.subtle,
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: BwSpacing.lg),
                Text(
                  item.description,
                  style: const TextStyle(fontSize: 14.5, height: 1.55, color: BwColors.textMuted),
                ),

                const SizedBox(height: BwSpacing.xl),
                const Text(
                  'Choose a size',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BwColors.text),
                ),
                const SizedBox(height: BwSpacing.md),
                Row(
                  children: _sizes.map((({String label, num delta}) s) {
                    final bool selected = _size == s.label;

                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: s.label == _sizes.last.label ? 0 : BwSpacing.sm),
                        child: Material(
                          color: selected ? BwColors.inverse : BwColors.surface,
                          borderRadius: BorderRadius.circular(BwRadius.card),
                          child: InkWell(
                            onTap: () => setState(() => _size = s.label),
                            borderRadius: BorderRadius.circular(BwRadius.card),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: BwSpacing.lg),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(BwRadius.card),
                                border: Border.all(
                                  color: selected ? BwColors.inverse : BwColors.borderStrong,
                                  width: BwStroke.strong,
                                ),
                              ),
                              child: Column(
                                children: <Widget>[
                                  Text(
                                    s.label,
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      color: selected ? BwColors.onInverse : BwColors.text,
                                    ),
                                  ),
                                  if (s.delta != 0) ...<Widget>[
                                    const SizedBox(height: 2),
                                    Text(
                                      '+${Fmt.pesoWhole(s.delta)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: selected
                                            ? BwColors.onInverse.withValues(alpha: 0.7)
                                            : BwColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(growable: false),
                ),

                if (inCart > 0) ...<Widget>[
                  const SizedBox(height: BwSpacing.xl),
                  BwCard(
                    padding: const EdgeInsets.all(BwSpacing.md),
                    color: BwColors.subtle,
                    borderColor: BwColors.border,
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.shopping_bag_outlined, size: 18, color: BwColors.text),
                        const SizedBox(width: BwSpacing.sm),
                        Expanded(
                          child: Text(
                            '$inCart already in your cart',
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: BwColors.text),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          _AddBar(
            qty: _qty,
            unitPrice: _unitPrice,
            onMinus: () => setState(() => _qty = _qty > 1 ? _qty - 1 : 1),
            // Never let the stepper promise more than the shop can make.
            onPlus: _qty >= item.stock ? null : () => setState(() => _qty++),
            // A rejected add (stock moved under us) keeps the user on the page
            // with a reason, instead of popping as though it worked.
            onAdd: () {
              final bool added =
                  context.read<CartProvider>().add(item.id, _qty);

              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: Text(added
                      ? '${item.name} added to cart'
                      : 'Only ${item.stock} left in stock.'),
                ));

              if (added) Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}

class _ImagePanel extends StatelessWidget {
  const _ImagePanel({required this.item});

  final MenuItem item;

  @override
  Widget build(BuildContext context) {
    final String? url = item.imageUrl;

    return AspectRatio(
      aspectRatio: 16 / 10,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(BwRadius.card),
        child: url == null || url.isEmpty
            ? Container(
                color: BwColors.subtle,
                child: const Center(
                  child: Icon(Icons.local_cafe_outlined, size: 56, color: BwColors.disabled),
                ),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: BwColors.subtle,
                  child: const Center(
                    child: Icon(Icons.local_cafe_outlined, size: 56, color: BwColors.disabled),
                  ),
                ),
              ),
      ),
    );
  }
}

class _AddBar extends StatelessWidget {
  const _AddBar({
    required this.qty,
    required this.unitPrice,
    required this.onMinus,
    required this.onPlus,
    required this.onAdd,
  });

  final int qty;
  final num unitPrice;
  final VoidCallback onMinus;
  /// Null disables the plus stepper once the cart holds all remaining stock.
  final VoidCallback? onPlus;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(BwSpacing.gutter, BwSpacing.md, BwSpacing.gutter, BwSpacing.lg),
      decoration: const BoxDecoration(
        color: BwColors.surface,
        border: Border(top: BorderSide(color: BwColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            Container(
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(BwRadius.card),
                border: Border.all(color: BwColors.borderStrong, width: BwStroke.strong),
              ),
              child: Row(
                children: <Widget>[
                  _Step(icon: Icons.remove_rounded, onTap: onMinus),
                  Text(
                    '$qty',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BwColors.text),
                  ),
                  _Step(icon: Icons.add_rounded, onTap: onPlus),
                ],
              ),
            ),
            const SizedBox(width: BwSpacing.md),
            Expanded(
              child: BwButton(
                label: 'Add · ${Fmt.peso(unitPrice * qty)}',
                onPressed: onAdd,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BwColors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 52,
          child: Icon(
            icon,
            size: 18,
            color: onTap == null ? BwColors.disabled : BwColors.text,
          ),
        ),
      ),
    );
  }
}