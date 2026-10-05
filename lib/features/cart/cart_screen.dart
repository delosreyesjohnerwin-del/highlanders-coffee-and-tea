import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/bw_colors.dart';
import '../../core/theme/bw_metrics.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/bw_badge.dart';
import '../../core/widgets/bw_button.dart';
import '../../core/widgets/bw_card.dart';
import '../../data/models/coverage.dart';
import '../../data/models/menu.dart';
import '../../data/models/order.dart';
import '../../state/cart_provider.dart';
import '../../state/catalog_provider.dart';
import '../../state/session_provider.dart';
import '../checkout/checkout_screen.dart';
import '../shell/app_shell.dart';

/// Cart screen. The empty state is the layout called out in the design brief:
/// a monochrome line-art cart icon, a bold heading and a muted subtitle.
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final CartProvider cart = context.watch<CartProvider>();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: cart.isEmpty
            ? const EmptyCartState()
            : _FilledCart(cart: cart),
      ),
    );
  }
}

/// Centered empty cart.
class EmptyCartState extends StatelessWidget {
  const EmptyCartState({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BwSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const _CartLineArt(),
          const SizedBox(height: BwSpacing.xl),
          const Text(
            'Your cart is empty',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: BwColors.text,
            ),
          ),
          const SizedBox(height: BwSpacing.sm),
          const Text(
            'Add items from the menu to get started.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14.5, height: 1.45, color: BwColors.textMuted),
          ),
          const SizedBox(height: BwSpacing.xxl),
          BwButton(
            label: 'Browse menu',
            icon: Icons.local_cafe_outlined,
            expand: false,
            onPressed: () => ShellNav.home(),
          ),
        ],
      ),
    );
  }
}

/// Hand-drawn-style monochrome cart glyph, built from strokes so it stays crisp
/// at any size and needs no asset file.
class _CartLineArt extends StatelessWidget {
  const _CartLineArt();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      height: 132,
      child: CustomPaint(painter: _CartPainter()),
    );
  }
}

class _CartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = BwColors.border;

    final Paint line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = BwColors.text;

    // Outer ring.
    canvas.drawCircle(size.center(Offset.zero), size.width / 2 - 2, ring);

    final double w = size.width;
    final double h = size.height;

    // Handle.
    final Path handle = Path()
      ..moveTo(w * 0.28, h * 0.30)
      ..lineTo(w * 0.37, h * 0.30)
      ..lineTo(w * 0.44, h * 0.56);

    // Basket body.
    final Path basket = Path()
      ..moveTo(w * 0.42, h * 0.38)
      ..lineTo(w * 0.74, h * 0.38)
      ..lineTo(w * 0.68, h * 0.57)
      ..lineTo(w * 0.48, h * 0.57)
      ..close();

    canvas.drawPath(handle, line);
    canvas.drawPath(basket, line);

    // Wheels.
    canvas.drawCircle(Offset(w * 0.51, h * 0.66), 3.5, line);
    canvas.drawCircle(Offset(w * 0.66, h * 0.66), 3.5, line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FilledCart extends StatelessWidget {
  const _FilledCart({required this.cart});

  final CartProvider cart;

  @override
  Widget build(BuildContext context) {
    final CatalogProvider catalog = context.watch<CatalogProvider>();

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(BwSpacing.gutter, BwSpacing.lg, BwSpacing.gutter, 0),
          child: Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Your Cart',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    color: BwColors.text,
                  ),
                ),
              ),
              Text(
                Fmt.itemCount(cart.itemCount),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BwColors.textMuted),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(BwSpacing.gutter, BwSpacing.lg, BwSpacing.gutter, BwSpacing.lg),
            children: <Widget>[
              ...cart.lines.map((OrderLine line) => Padding(
                    padding: const EdgeInsets.only(bottom: BwSpacing.md),
                    child: _CartRow(line: line, cart: cart),
                  )),

              if (catalog.heroPromo != null) ...<Widget>[
                const SizedBox(height: BwSpacing.sm),
                _PromoHint(code: catalog.heroPromo!.code),
              ],

              const SizedBox(height: BwSpacing.lg),
              _FulfillmentSelector(cart: cart),

              if (cart.fulfillment == Fulfillment.delivery) ...<Widget>[
                const SizedBox(height: BwSpacing.lg),
                _AddressBlock(cart: cart),
              ],
            ],
          ),
        ),
        _CheckoutBar(cart: cart),
      ],
    );
  }
}

class _CartRow extends StatelessWidget {
  const _CartRow({required this.line, required this.cart});

  final OrderLine line;
  final CartProvider cart;

  @override
  Widget build(BuildContext context) {
    final CatalogProvider catalog = context.watch<CatalogProvider>();
    final MenuItem? item = catalog.itemById(line.itemId);

    return BwCard(
      padding: const EdgeInsets.all(BwSpacing.md),
      child: Row(
        children: <Widget>[
          BwThumb(imageUrl: item?.imageUrl, size: 54),
          const SizedBox(width: BwSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  line.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: BwColors.text),
                ),
                const SizedBox(height: 2),
                Text(
                  Fmt.peso(line.price),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: BwColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: BwSpacing.sm),
          Container(
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BwRadius.pill),
              border: Border.all(color: BwColors.borderStrong, width: BwStroke.strong),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _StepButton(icon: Icons.remove_rounded, onTap: () => cart.remove(line.itemId)),
                SizedBox(
                  width: 22,
                  child: Text(
                    '${line.quantity}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: BwColors.text),
                  ),
                ),
                _StepButton(icon: Icons.add_rounded, onTap: () => cart.add(line.itemId)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BwColors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(width: 32, height: 32, child: Icon(icon, size: 16, color: BwColors.text)),
      ),
    );
  }
}

class _PromoHint extends StatelessWidget {
  const _PromoHint({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(BwSpacing.lg),
      decoration: BoxDecoration(
        color: BwColors.bg,
        borderRadius: BorderRadius.circular(BwRadius.card),
        border: Border.all(color: BwColors.border),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.local_offer_outlined, size: 19, color: BwColors.text),
          const SizedBox(width: BwSpacing.md),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 13, color: BwColors.textMuted, height: 1.4),
                children: const <InlineSpan>[
                  TextSpan(text: 'Promo '),
                  TextSpan(
                    text: 'DAMPOTIST',
                    style: TextStyle(fontWeight: FontWeight.w700, color: BwColors.text),
                  ),
                  TextSpan(text: ' applied at checkout for free delivery.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FulfillmentSelector extends StatelessWidget {
  const _FulfillmentSelector({required this.cart});

  final CartProvider cart;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.only(bottom: BwSpacing.md),
          child: Text(
            'How would you like it?',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BwColors.text),
          ),
        ),
        Row(
          children: Fulfillment.values.map((Fulfillment f) {
            final bool selected = cart.fulfillment == f;

            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: f == Fulfillment.pickup ? BwSpacing.sm : 0),
                child: Material(
                  color: selected ? BwColors.inverse : BwColors.surface,
                  borderRadius: BorderRadius.circular(BwRadius.card),
                  child: InkWell(
                    onTap: () => cart.setFulfillment(f),
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
                          Icon(
                            f == Fulfillment.delivery ? Icons.delivery_dining_outlined : Icons.shopping_basket_outlined,
                            size: 21,
                            color: selected ? BwColors.onInverse : BwColors.text,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            f.label,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: selected ? BwColors.onInverse : BwColors.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(growable: false),
        ),
      ],
    );
  }
}

class _AddressBlock extends StatelessWidget {
  const _AddressBlock({required this.cart});

  final CartProvider cart;

  @override
  Widget build(BuildContext context) {
    final List<SavedAddress> addresses = context.watch<SessionProvider>().addresses;
    final AddressSnapshot? selected = cart.addressSnapshot;

    if (addresses.isEmpty) {
      return const _NoAddressWarning();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.only(bottom: BwSpacing.md),
          child: Text(
            'Deliver to',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BwColors.text),
          ),
        ),
        ...addresses.map((SavedAddress a) {
          final bool isSelected = a.id == cart.addressId;
          final double? km = a.distanceKm();

          return Padding(
            padding: const EdgeInsets.only(bottom: BwSpacing.sm),
            child: Material(
              color: isSelected ? BwColors.subtle : BwColors.surface,
              borderRadius: BorderRadius.circular(BwRadius.card),
              child: InkWell(
                onTap: () => cart.selectAddress(a.id),
                borderRadius: BorderRadius.circular(BwRadius.card),
                child: Container(
                  padding: const EdgeInsets.all(BwSpacing.lg),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(BwRadius.card),
                    border: Border.all(
                      color: isSelected ? BwColors.borderStrong : BwColors.border,
                      width: isSelected ? BwStroke.strong : BwStroke.hairline,
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                        size: 19,
                        color: isSelected ? BwColors.inverse : BwColors.textMuted,
                      ),
                      const SizedBox(width: BwSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              a.label,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BwColors.text),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${a.street}, ${_barangayName(a.barangayCode)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, color: BwColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      if (km != null)
                        Text(
                          Fmt.distance(km),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BwColors.textMuted),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
        if (selected != null && !context.watch<CatalogProvider>().pricing.covers(selected.distanceKm ?? 0))
          const Padding(
            padding: EdgeInsets.only(top: BwSpacing.sm),
            child: _NoAddressWarning(
              message: 'That address is outside our Lumban delivery radius. '
                  'Please choose a nearer barangay or switch to pick up.',
            ),
          ),
      ],
    );
  }

  static String _barangayName(String code) => LumbanCoverage.byCode(code)?.name ?? code;
}

class _NoAddressWarning extends StatelessWidget {
  const _NoAddressWarning({this.message = 'Add a delivery address to continue, or switch to pick up.'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BwSpacing.md),
      decoration: BoxDecoration(
        color: BwColors.subtle,
        borderRadius: BorderRadius.circular(BwRadius.card),
        border: Border.all(color: BwColors.borderStrong, width: BwStroke.strong),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline_rounded, size: 18, color: BwColors.text),
          const SizedBox(width: BwSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, height: 1.4, color: BwColors.text),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({required this.cart});

  final CartProvider cart;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(BwSpacing.gutter, BwSpacing.lg, BwSpacing.gutter, BwSpacing.lg),
      decoration: const BoxDecoration(
        color: BwColors.surface,
        border: Border(top: BorderSide(color: BwColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _SummaryRow(label: 'Subtotal', value: Fmt.peso(cart.subtotal)),
            const SizedBox(height: 6),
            _SummaryRow(
              label: cart.fulfillment == Fulfillment.pickup
                  ? 'Pickup'
                  : cart.isFreeDelivery
                      ? 'Delivery (waived)'
                      : 'Delivery',
              value: cart.isFreeDelivery ? 'FREE' : Fmt.peso(cart.deliveryFee),
              highlight: cart.isFreeDelivery,
            ),
            const SizedBox(height: 6),
            _SummaryRow(label: 'Total', value: Fmt.peso(cart.total), total: true),
            const SizedBox(height: BwSpacing.lg),
            BwButton(
              label: 'Checkout',
              trailingIcon: Icons.arrow_forward_rounded,
              onPressed: cart.canCheckout
                  ? () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const CheckoutScreen()),
                      )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.total = false,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool total;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: total ? 15.5 : 13.5,
              fontWeight: total ? FontWeight.w700 : FontWeight.w500,
              color: total ? BwColors.text : BwColors.textMuted,
            ),
          ),
        ),
        const SizedBox(width: BwSpacing.sm),
        const Spacer(),
        if (highlight)
          const Padding(
            padding: EdgeInsets.only(right: 6),
            child: BwBadge(label: 'FREE', variant: BwBadgeVariant.solid, dense: true),
          ),
        Text(
          value,
          style: TextStyle(
            fontSize: total ? 18 : 13.5,
            fontWeight: FontWeight.w800,
            letterSpacing: total ? -0.4 : 0,
            color: BwColors.text,
          ),
        ),
      ],
    );
  }
}