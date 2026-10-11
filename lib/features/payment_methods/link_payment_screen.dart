import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/bw_colors.dart';
import '../../core/theme/bw_metrics.dart';
import '../../core/widgets/bw_button.dart';
import '../../data/models/payment.dart';
import '../../services/payment_gateway.dart';
import '../../state/session_provider.dart';

/// Link a payment method: choose a network, type the details once, and the
/// screen stores only a masked label plus a gateway token.
///
/// Mirrors [AddressFormScreen]'s structure — ChoiceChip selectors for the
/// type, per-field validators, a default toggle and a save-and-pop button.
///
/// ## The raw number never persists
///
/// `_link()` hands the full number to the [PaymentGateway]; the result is a
/// masked [PaymentAccount] whose raw digits exist nowhere on disk.
class LinkPaymentScreen extends StatefulWidget {
  const LinkPaymentScreen({super.key, this.gateway});

  /// Injectable for tests; production builds fall back to the factory's
  /// choice (mock offline, the real Cloud-Function-backed gateway when the
  /// build opts in via `--dart-define=XENDIT_ENABLED=true`).
  final PaymentGateway? gateway;

  @override
  State<LinkPaymentScreen> createState() => _LinkPaymentScreenState();
}

class _LinkPaymentScreenState extends State<LinkPaymentScreen> {
  static const List<PaymentNetwork> _networks = <PaymentNetwork>[
    PaymentNetwork.gcash,
    PaymentNetwork.maya,
    PaymentNetwork.card,
    PaymentNetwork.bankTransfer,
  ];

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _holder = TextEditingController();
  final TextEditingController _number = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _expiry = TextEditingController();
  final TextEditingController _cvc = TextEditingController();
  late final PaymentGateway _gateway;

  late PaymentNetwork _network;
  late bool _isDefault;
  bool _defaultInitialised = false;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? PaymentGatewayFactory.create();
    _network = PaymentNetwork.gcash;
    _isDefault = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Provider lookups are unsafe in initState; running once here, after the
    // element is in the tree, is the canonical safe spot.
    if (!_defaultInitialised) {
      _defaultInitialised = true;
      // The very first linked account becomes the default so the café always
      // has a fallback to bill against.
      _isDefault = context.read<SessionProvider>().paymentAccounts.isEmpty;
    }
  }

  @override
  void dispose() {
    _holder.dispose();
    _number.dispose();
    _email.dispose();
    _expiry.dispose();
    _cvc.dispose();
    super.dispose();
  }

  // --- validators ---------------------------------------------------------

  String? _validateHolder(String? v) =>
      (v ?? '').trim().isEmpty ? 'Enter the account holder name.' : null;

  String? _validateNumber(String? v) {
    final String raw = (v ?? '').trim();
    if (raw.isEmpty) return 'Enter the required details.';
    if (_network.isMobileWallet) {
      return PaymentAccount.isValidPhMobile(raw)
          ? null
          : 'Enter a valid PH mobile number (e.g. 0917 123 4567 or +63917 123 4567).';
    }
    final String digits = raw.replaceAll(RegExp(r'\D'), '');
    if (_network == PaymentNetwork.card) {
      return digits.length >= 13 ? null : 'Enter a valid card number.';
    }
    return digits.length >= 8 ? null : 'Enter the full account number.';
  }

  String? _validateEmail(String? v) {
    final String raw = (v ?? '').trim();
    if (raw.isEmpty) return null;
    return RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(raw) ? null : 'Enter a valid email address.';
  }

  String? _validateExpiry(String? v) {
    final String raw = (v ?? '').trim();
    if (!RegExp(r'^(0[1-9]|1[0-2])/\d{2}$').hasMatch(raw)) {
      return 'Use MM/YY.';
    }
    final int month = int.parse(raw.substring(0, 2));
    final int year = 2000 + int.parse(raw.substring(3));
    final DateTime now = DateTime.now();
    final int nowMonth = (now.year * 12) + now.month;
    final int cardMonth = (year * 12) + month;
    return cardMonth >= nowMonth ? null : 'This card has expired.';
  }

  String? _validateCvc(String? v) {
    final String digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
    return (digits.length == 3 || digits.length == 4) ? null : 'Enter 3–4 digits.';
  }

  // --- link ---------------------------------------------------------------

  Future<void> _link() async {
    if (!_formKey.currentState!.validate()) return;

    final SessionProvider session = context.read<SessionProvider>();
    final bool firstAccount = session.paymentAccounts.isEmpty;

    final PaymentLinkResult result;
    try {
      result = await _gateway.link(PaymentLinkRequest(
        network: _network,
        holderName: _holder.text.trim(),
        accountNumber: _number.text.trim(),
        email: _network.isMobileWallet ? _email.text.trim() : null,
        expiry: _network == PaymentNetwork.card ? _expiry.text.trim() : null,
        cvc: _network == PaymentNetwork.card ? _cvc.text.trim() : null,
      ));
    } on GatewayException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
      return;
    } catch (_) {
      // The real gateway already wraps failures; this is the belt-and-braces
      // path in case a future implementation throws something unexpected.
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Could not link the payment method. Please try again.'),
        ));
      return;
    }
    if (!mounted) return;

    final String email = _email.text.trim();
    final PaymentAccount account = PaymentAccount(
      id: 'pm-${DateTime.now().microsecondsSinceEpoch}',
      network: _network,
      holderName: _holder.text.trim(),
      accountLabel: result.accountLabel,
      tail: result.tail,
      email: _network.isMobileWallet && email.isNotEmpty ? email : null,
      isDefault: _isDefault || firstAccount,
      linkedAt: DateTime.now(),
      gatewayId: result.gatewayId,
      cardBrand: _network == PaymentNetwork.card
          ? PaymentAccount.brandOfCard(_number.text)
          : null,
    );

    // Uses the State's `context` after the `mounted` guard above — the lint
    // requires exactly this pairing for uses across the await gap.
    context.read<SessionProvider>().addPaymentAccount(account);
    Navigator.of(context).pop(account);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add payment method'),
        leading: BwIconButton(
          icon: Icons.arrow_back_rounded,
          onPressed: () => Navigator.of(context).pop(),
          bordered: false,
          background: BwColors.transparent,
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              BwSpacing.gutter,
              BwSpacing.lg,
              BwSpacing.gutter,
              BwSpacing.xxl,
            ),
            children: <Widget>[
              const _SectionTitle(title: 'Payment type'),
              const SizedBox(height: BwSpacing.sm),
              Wrap(
                spacing: BwSpacing.sm,
                runSpacing: BwSpacing.sm,
                children: _networks.map((PaymentNetwork network) {
                  final bool selected = _network == network;
                  return ChoiceChip(
                    avatar: Icon(
                      network.icon,
                      size: 16,
                      color: selected ? BwColors.onInverse : BwColors.text,
                    ),
                    label: Text(network.label),
                    selected: selected,
                    showCheckmark: false,
                    selectedColor: BwColors.inverse,
                    backgroundColor: BwColors.surface,
                    side: BorderSide(
                      color: selected ? BwColors.inverse : BwColors.borderStrong,
                      width: selected ? BwStroke.strong : BwStroke.hairline,
                    ),
                    labelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected ? BwColors.onInverse : BwColors.text,
                    ),
                    onSelected: (bool _) => setState(() => _network = network),
                  );
                }).toList(growable: false),
              ),
              const SizedBox(height: BwSpacing.lg),
              const _SectionTitle(title: 'Account holder'),
              const SizedBox(height: BwSpacing.sm),
              TextFormField(
                controller: _holder,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(fontSize: 15, color: BwColors.text),
                decoration: const InputDecoration(
                  labelText: 'Name on the account',
                  hintText: 'Marco Reyes',
                  prefixIcon: Icon(Icons.person_outline_rounded, size: 19),
                ),
                validator: _validateHolder,
              ),
              if (_network.isMobileWallet) ...<Widget>[
                const SizedBox(height: BwSpacing.lg),
                _SectionTitle(
                  title: 'Mobile number',
                  subtitle: 'The number ${_network.label} is registered to.',
                ),
                const SizedBox(height: BwSpacing.sm),
                TextFormField(
                  controller: _number,
                  keyboardType: TextInputType.phone,
                  maxLength: 13,
                  style: const TextStyle(fontSize: 15, color: BwColors.text),
                  decoration: InputDecoration(
                    labelText: 'PH mobile number',
                    hintText: _network == PaymentNetwork.gcash ? '0917 123 4567' : '+63917 123 4567',
                    prefixIcon: const Icon(Icons.phone_iphone_outlined, size: 19),
                    counterText: '',
                  ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
                  ],
                  validator: _validateNumber,
                ),
                const SizedBox(height: BwSpacing.lg),
                const _SectionTitle(title: 'Email (optional)'),
                const SizedBox(height: BwSpacing.sm),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(fontSize: 15, color: BwColors.text),
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'For receipts and payment confirmations',
                    prefixIcon: Icon(Icons.mail_outline_rounded, size: 19),
                  ),
                  validator: _validateEmail,
                ),
              ] else if (_network == PaymentNetwork.card) ...<Widget>[
                const SizedBox(height: BwSpacing.lg),
                const _SectionTitle(title: 'Card details'),
                const SizedBox(height: BwSpacing.sm),
                TextFormField(
                  controller: _number,
                  keyboardType: TextInputType.number,
                  maxLength: 19,
                  style: const TextStyle(fontSize: 15, color: BwColors.text),
                  decoration: const InputDecoration(
                    labelText: 'Card number',
                    hintText: '4242 4242 4242 4242',
                    prefixIcon: Icon(Icons.credit_card_outlined, size: 19),
                    counterText: '',
                  ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: _validateNumber,
                ),
                const SizedBox(height: BwSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: TextFormField(
                        controller: _expiry,
                        keyboardType: TextInputType.datetime,
                        maxLength: 5,
                        style: const TextStyle(fontSize: 15, color: BwColors.text),
                        decoration: const InputDecoration(
                          labelText: 'Expiry',
                          hintText: 'MM/YY',
                          counterText: '',
                        ),
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
                        ],
                        validator: _validateExpiry,
                      ),
                    ),
                    const SizedBox(width: BwSpacing.md),
                    Expanded(
                      child: TextFormField(
                        controller: _cvc,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        obscureText: true,
                        style: const TextStyle(fontSize: 15, color: BwColors.text),
                        decoration: const InputDecoration(
                          labelText: 'CVC',
                          hintText: '123',
                          counterText: '',
                        ),
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: _validateCvc,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: BwSpacing.sm),
                const Text(
                  'Your card is validated by the payment gateway; we never '
                  'store the number or CVC.',
                  style: TextStyle(fontSize: 12, height: 1.4, color: BwColors.textMuted),
                ),
              ] else ...<Widget>[
                const SizedBox(height: BwSpacing.lg),
                const _SectionTitle(title: 'Bank account'),
                const SizedBox(height: BwSpacing.sm),
                TextFormField(
                  controller: _number,
                  keyboardType: TextInputType.number,
                  maxLength: 20,
                  style: const TextStyle(fontSize: 15, color: BwColors.text),
                  decoration: const InputDecoration(
                    labelText: 'Account number',
                    hintText: 'e.g. 1234 5678 9012 3456',
                    prefixIcon: Icon(Icons.account_balance_outlined, size: 19),
                    counterText: '',
                  ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: _validateNumber,
                ),
              ],
              const SizedBox(height: BwSpacing.lg),
              _DefaultPaymentToggle(
                value: _isDefault,
                onChanged: (bool v) => setState(() => _isDefault = v),
              ),
              const SizedBox(height: BwSpacing.lg),
              const _PrivacyNote(),
              const SizedBox(height: BwSpacing.xl),
              BwButton(
                label: 'Link payment method',
                icon: Icons.check_rounded,
                onPressed: _link,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BwColors.text),
        ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: const TextStyle(fontSize: 12.5, height: 1.4, color: BwColors.textMuted),
          ),
        ],
      ],
    );
  }
}

class _DefaultPaymentToggle extends StatelessWidget {
  const _DefaultPaymentToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BwColors.surface,
      borderRadius: BorderRadius.circular(BwRadius.card),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(BwRadius.card),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: BwSpacing.md, vertical: BwSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BwRadius.card),
            border: Border.all(color: BwColors.border),
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.account_balance_wallet_outlined, size: 19, color: BwColors.text),
              const SizedBox(width: BwSpacing.md),
              const Expanded(
                child: Text(
                  'Use as my default payment method',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BwColors.text),
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeTrackColor: BwColors.inverse,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Prominent reassurance that the full number never touches storage.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BwSpacing.md),
      decoration: BoxDecoration(
        color: BwColors.subtle,
        borderRadius: BorderRadius.circular(BwRadius.card),
        border: Border.all(color: BwColors.border),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.lock_outline_rounded, size: 18, color: BwColors.textMuted),
          SizedBox(width: BwSpacing.sm),
          Expanded(
            child: Text(
              'Your full number is sent straight to the payment gateway. We '
              'store only the masked version shown in your list.',
              style: TextStyle(fontSize: 12.5, height: 1.45, color: BwColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}