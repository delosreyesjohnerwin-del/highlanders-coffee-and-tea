import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/bw_colors.dart';
import '../../core/theme/bw_metrics.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/bw_badge.dart';
import '../../core/widgets/bw_button.dart';
import '../../core/widgets/bw_card.dart';
import '../../data/models/order.dart';
import '../../state/cart_provider.dart';
import '../../state/catalog_provider.dart';
import '../../state/session_provider.dart';
import '../order_tracking/order_success_screen.dart';

/// Checkout: address summary, payment method picker, fee breakdown, place order.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  bool _placing = false;

  @override
  Widget build(BuildContext context) {
    final CartProvider cart = context.watch<CartProvider>();
    final CatalogProvider catalog = context.watch<CatalogProvider>();
    final AddressSnapshot? address = cart.addressSnapshot;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(BwSpacing.gutter, BwSpacing.lg, BwSpacing.gutter, BwSpacing.xl),
              children: <Widget>[
                // Fulfillment + address.
                _Block(
                  title: cart.fulfillment == Fulfillment.pickup ? 'Pick up at' : 'Deliver to',
                  trailing: BwBadge(
                    label: cart.fulfillment.label,
                    variant: BwBadgeVariant.subtle,
                    icon: cart.fulfillment == Fulfillment.pickup
                        ? Icons.shopping_basket_outlined
                        : Icons.delivery_dining_outlined,
                  ),
                  child: cart.fulfillment == Fulfillment.pickup
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              catalog.cafeName,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BwColors.text),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              catalog.locationLabel,
                              style: const TextStyle(fontSize: 13, color: BwColors.textMuted),
                            ),
                          ],
                        )
                      : address == null
                          ? const Text(
                              'No address selected. Go back to the cart to choose one.',
                              style: TextStyle(fontSize: 13.5, color: BwColors.textMuted),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: Text(
                                        address.label,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: BwColors.text,
                                        ),
                                      ),
                                    ),
                                    if (address.distanceKm != null)
                                      BwBadge(
                                        label: Fmt.distance(address.distanceKm!),
                                        variant: BwBadgeVariant.subtle,
                                        dense: true,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  address.oneLine,
                                  style: const TextStyle(fontSize: 13, color: BwColors.textMuted),
                                ),
                                if (address.note != null) ...<Widget>[
                                  const SizedBox(height: 3),
                                  Text(
                                    address.note!,
                                    style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, color: BwColors.textMuted),
                                  ),
                                ],
                              ],
                            ),
                ),

                if (cart.fulfillment == Fulfillment.delivery && address?.distanceKm != null) ...<Widget>[
                  const SizedBox(height: BwSpacing.lg),
                  _EtaRow(minutes: cart.etaMinutes),
                ],

                // Payment method.
                const SizedBox(height: BwSpacing.xl),
                _Block(
                  title: 'Payment method',
                  child: Column(
                    children: PaymentMethod.values.map((PaymentMethod m) {
                      return _PaymentOption(
                        method: m,
                        selected: cart.paymentMethod == m,
                        onTap: () => cart.setPaymentMethod(m),
                      );
                    }).toList(growable: false),
                  ),
                ),

                // Item summary.
                const SizedBox(height: BwSpacing.xl),
                _Block(
                  title: 'Order summary',
                  trailing: BwBadge(label: Fmt.itemCount(cart.itemCount), variant: BwBadgeVariant.subtle),
                  child: Column(
                    children: <Widget>[
                      ...cart.lines.map(
                        (OrderLine l) => Padding(
                          padding: const EdgeInsets.only(bottom: BwSpacing.sm),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                '${l.quantity}×',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: BwColors.text,
                                ),
                              ),
                              const SizedBox(width: BwSpacing.sm),
                              Expanded(
                                child: Text(
                                  l.name,
                                  style: const TextStyle(fontSize: 13.5, color: BwColors.text),
                                ),
                              ),
                              Text(
                                Fmt.peso(l.lineTotal),
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: BwColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: BwSpacing.sm),
                        child: Divider(height: 1),
                      ),
                      _Row(label: 'Subtotal', value: Fmt.peso(cart.subtotal)),
                      const SizedBox(height: 6),
                      _Row(
                        label: 'Delivery',
                        value: cart.fulfillment == Fulfillment.pickup || cart.isFreeDelivery
                            ? 'FREE'
                            : Fmt.peso(cart.deliveryFee),
                      ),
                      const SizedBox(height: BwSpacing.sm),
                      _Row(label: 'Total', value: Fmt.peso(cart.total), total: true),
                    ],
                  ),
                ),

                const SizedBox(height: BwSpacing.lg),
                const Text(
                  'Payment is processed by PayMongo. Cash on delivery is collected by '
                  'the driver at handover.',
                  style: TextStyle(fontSize: 12, height: 1.45, color: BwColors.textMuted),
                ),
              ],
            ),
          ),

          _PlaceBar(
            total: cart.total,
            placing: _placing,
            onTap: () => _place(cart),
          ),
        ],
      ),
    );
  }

  Future<void> _place(CartProvider cart) async {
    setState(() => _placing = true);

    // Stands in for the PayMongo redirect + webhook round trip.
    await Future<void>.delayed(const Duration(milliseconds: 900));

    if (!mounted) return;

    final String pickupCode = (1000 + DateTime.now().millisecondsSinceEpoch % 9000).toString();
    final int eta = cart.etaMinutes;

    // `customerUid` is stamped here rather than inferred by the repository,
    // because the repository has no way to know who is signed in — and the rules
    // require the field to equal the caller's uid. Setting it from the session
    // keeps the two in step by construction.
    final Order order = Order(
      customerUid: context.read<SessionProvider>().user.uid,
      id: Fmt.orderId(pickupCode),
      lines: cart.lines,
      status: cart.paymentMethod.isPrepaid ? OrderStatus.confirmed : OrderStatus.pending,
      fulfillment: cart.fulfillment,
      paymentMethod: cart.paymentMethod,
      createdAt: DateTime.now(),
      subtotal: cart.subtotal,
      deliveryFee: cart.deliveryFee,
      distanceKm: cart.distanceKm,
      address: cart.addressSnapshot,
      pickupCode: pickupCode,
      promoCode: cart.promoCode,
      paymentRef: cart.paymentMethod.isPrepaid ? 'PAY-$pickupCode' : null,
    );

    context.read<SessionProvider>().placeOrder(order);

    final List<OrderLine> lines = List<OrderLine>.from(cart.lines);
    final num subtotal = cart.subtotal;
    final num fee = cart.deliveryFee;
    final String? code = cart.promoCode;
    final PaymentMethod method = cart.paymentMethod;
    final double? km = cart.distanceKm;

    cart.clear();

    setState(() => _placing = false);

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => OrderSuccessScreen(
          order: order,
          lines: lines,
          subtotal: subtotal,
          deliveryFee: fee,
          distanceKm: km,
          promoCode: code,
          paymentMethod: method,
          etaMinutes: eta,
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return BwCard(
      padding: const EdgeInsets.all(BwSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: BwColors.text),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: BwSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _PaymentOption extends StatelessWidget {
  const _PaymentOption({required this.method, required this.selected, required this.onTap});

  final PaymentMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BwSpacing.sm),
      child: Material(
        color: selected ? BwColors.subtle : BwColors.surface,
        borderRadius: BorderRadius.circular(BwRadius.field),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(BwRadius.field),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: BwSpacing.md, vertical: BwSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BwRadius.field),
              border: Border.all(
                color: selected ? BwColors.borderStrong : BwColors.border,
                width: selected ? BwStroke.strong : BwStroke.hairline,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  method.icon,
                  size: 19,
                  color: selected ? BwColors.inverse : BwColors.textMuted,
                ),
                const SizedBox(width: BwSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        method.label,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BwColors.text),
                      ),
                      Text(
                        method.isPrepaid ? 'Paid in app' : 'Pay the driver on handover',
                        style: const TextStyle(fontSize: 12, color: BwColors.textMuted),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  size: 19,
                  color: selected ? BwColors.inverse : BwColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EtaRow extends StatelessWidget {
  const _EtaRow({required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    return BwCard(
      padding: const EdgeInsets.all(BwSpacing.lg),
      color: BwColors.bg,
      child: Row(
        children: <Widget>[
          const Icon(Icons.schedule_outlined, size: 20, color: BwColors.text),
          const SizedBox(width: BwSpacing.md),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 13.5, color: BwColors.textMuted),
                children: <InlineSpan>[
                  const TextSpan(text: 'Estimated delivery in '),
                  TextSpan(
                    text: Fmt.eta(Duration(minutes: minutes)),
                    style: const TextStyle(fontWeight: FontWeight.w700, color: BwColors.text),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.total = false});

  final String label;
  final String value;
  final bool total;

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

class _PlaceBar extends StatelessWidget {
  const _PlaceBar({required this.total, required this.placing, required this.onTap});

  final num total;
  final bool placing;
  final VoidCallback onTap;

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
        child: BwButton(
          label: placing ? 'Placing order…' : 'Place order · ${Fmt.peso(total)}',
          onPressed: placing ? null : onTap,
          trailingIcon: placing ? null : Icons.arrow_forward_rounded,
        ),
      ),
    );
  }
}