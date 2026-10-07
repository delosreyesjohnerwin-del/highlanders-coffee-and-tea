import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/theme/bw_colors.dart';
import '../../core/theme/bw_metrics.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/bw_button.dart';
import '../../data/models/coverage.dart';
import '../../data/models/order.dart';
import '../../state/catalog_provider.dart';
import '../../state/session_provider.dart';
import 'pin_picker_screen.dart';

/// Add or edit a saved delivery address.
///
/// Phase 1 is the barangay form — it works fully offline and needs no Google
/// billing account. Phase 2 layers a Google Maps pin picker on top of this
/// screen; the pin then supplies the real GPS coordinates and `lat`/`lng` ride
/// along, replacing the barangay-centroid distance with a true pin-to-café
/// haversine distance while the barangay stays as the delivery-area label.
///
/// Pops with the saved address on success so the caller can select it in the
/// cart immediately.
class AddressFormScreen extends StatefulWidget {
  const AddressFormScreen({super.key, this.initial});

  /// When set, the form edits this address; otherwise it creates a new one.
  final SavedAddress? initial;

  @override
  State<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends State<AddressFormScreen> {
  static const List<String> _labelChoices = <String>['Home', 'Work', 'Other'];

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _street = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final TextEditingController _customLabel = TextEditingController();

  late String _label;
  late String _barangayCode;
  late bool _isDefault;
  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    final SavedAddress? a = widget.initial;
    _label = a?.label ?? 'Home';
    _street.text = a?.street ?? '';
    _barangayCode = a?.barangayCode ?? '';
    _note.text = a?.note ?? '';
    _isDefault = a?.isDefault ?? false;
    _lat = a?.lat;
    _lng = a?.lng;
  }

  @override
  void dispose() {
    _street.dispose();
    _note.dispose();
    _customLabel.dispose();
    super.dispose();
  }

  String get _resolvedLabel {
    if (_label != 'Other') return _label;
    final String custom = _customLabel.text.trim();
    return custom.isEmpty ? 'Other' : custom;
  }

  Future<void> _openPinPicker() async {
    final LatLng? picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute<LatLng>(
        builder: (_) => PinPickerScreen(
          initial: (_lat != null && _lng != null) ? LatLng(_lat!, _lng!) : null,
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _lat = picked.latitude;
        _lng = picked.longitude;
      });
    }
  }

  void _save(BuildContext context) {
    if (!_formKey.currentState!.validate()) return;
    if (_barangayCode.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Choose a barangay first.')));
      return;
    }

    final SavedAddress address = SavedAddress(
      // Editing keeps the id, so the save-updates in-place instead of
      // duplicating. New addresses get a microsecond id that cannot collide.
      id: widget.initial?.id ?? 'a-${DateTime.now().microsecondsSinceEpoch}',
      label: _resolvedLabel,
      street: _street.text.trim(),
      barangayCode: _barangayCode,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      isDefault: _isDefault,
      // Phase 2: the map pin supplies real GPS coordinates, so the fee is
      // pin-to-café rather than barangay-centroid.
      lat: _lat,
      lng: _lng,
    );

    context.read<SessionProvider>().addAddress(address);
    Navigator.of(context).pop(address);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'Add address' : 'Edit address'),
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
              const _SectionTitle(title: 'Label'),
              const SizedBox(height: BwSpacing.sm),
              Wrap(
                spacing: BwSpacing.sm,
                children: _labelChoices.map((String choice) {
                  final bool selected = _label == choice;
                  return ChoiceChip(
                    label: Text(choice),
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
                    onSelected: (bool _) => setState(() => _label = choice),
                  );
                }).toList(growable: false),
              ),
              if (_label == 'Other') ...<Widget>[
                const SizedBox(height: BwSpacing.md),
                TextFormField(
                  controller: _customLabel,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 14,
                  style: const TextStyle(fontSize: 15, color: BwColors.text),
                  decoration: const InputDecoration(
                    labelText: 'Custom label',
                    hintText: "e.g. Grandma's house",
                    counterText: '',
                  ),
                  validator: (String? value) =>
                      (value ?? '').trim().isEmpty ? 'Give this address a label.' : null,
                ),
              ],
              const SizedBox(height: BwSpacing.lg),
              _SectionTitle(
                title: 'Street address',
                subtitle: 'House number, street or landmark. The barangay below '
                    'pins the approximate delivery area for now.',
              ),
              const SizedBox(height: BwSpacing.sm),
              TextFormField(
                controller: _street,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(fontSize: 15, color: BwColors.text),
                decoration: const InputDecoration(
                  labelText: 'Street / landmark',
                  hintText: '123 Poblacion Road',
                ),
                validator: (String? value) =>
                    (value ?? '').trim().isEmpty ? 'Enter the street or landmarks.' : null,
              ),
              const SizedBox(height: BwSpacing.lg),
              const _SectionTitle(title: 'Barangay'),
              const SizedBox(height: BwSpacing.sm),
              DropdownButtonFormField<String>(
                key: ValueKey<String>(_barangayCode),
                initialValue: _barangayCode.isEmpty ? null : _barangayCode,
                isExpanded: true,
                style: const TextStyle(fontSize: 15, color: BwColors.text),
                decoration: const InputDecoration(
                  labelText: 'Barangay, Lumban',
                  prefixIcon: Icon(Icons.map_outlined, size: 19),
                ),
                items: <DropdownMenuItem<String>>[
                  for (final Barangay b in LumbanCoverage.barangays)
                    DropdownMenuItem<String>(
                      value: b.code,
                      child: Text(b.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (String? code) {
                  if (code != null) setState(() => _barangayCode = code);
                },
              ),
              const SizedBox(height: BwSpacing.md),
              _PinTile(
                lat: _lat,
                lng: _lng,
                onTap: _openPinPicker,
              ),
              const SizedBox(height: BwSpacing.lg),
              const _SectionTitle(title: 'Delivery note'),
              const SizedBox(height: BwSpacing.sm),
              TextFormField(
                controller: _note,
                minLines: 1,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 15, color: BwColors.text),
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'Blue gate, second floor, near the church…',
                ),
              ),
              const SizedBox(height: BwSpacing.lg),
              _DefaultToggle(
                value: _isDefault,
                onChanged: (bool v) => setState(() => _isDefault = v),
              ),
              const SizedBox(height: BwSpacing.lg),
              _EstimatePreview(
                barangayCode: _barangayCode,
                lat: _lat,
                lng: _lng,
              ),
              const SizedBox(height: BwSpacing.xl),
              BwButton(
                label: 'Save address',
                icon: Icons.check_rounded,
                onPressed: () => _save(context),
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

/// Tappable card that opens the OSM pin picker and shows the current pin.
class _PinTile extends StatelessWidget {
  const _PinTile({required this.lat, required this.lng, required this.onTap});

  final double? lat;
  final double? lng;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool hasPin = lat != null && lng != null;

    return Material(
      color: BwColors.surface,
      borderRadius: BorderRadius.circular(BwRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BwRadius.card),
        child: Container(
          padding: const EdgeInsets.all(BwSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BwRadius.card),
            border: Border.all(
              color: hasPin ? BwColors.inverse : BwColors.border,
              width: hasPin ? BwStroke.strong : BwStroke.hairline,
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                hasPin ? Icons.location_on : Icons.my_location_outlined,
                size: 22,
                color: hasPin ? BwColors.inverse : BwColors.textMuted,
              ),
              const SizedBox(width: BwSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      hasPin ? 'Delivery pin set' : 'Set exact delivery pin',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: BwColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasPin
                          ? '${lat!.toStringAsFixed(6)}, ${lng!.toStringAsFixed(6)}'
                          : 'Tap to open the map and drop a pin on your spot.',
                      style: const TextStyle(fontSize: 12.5, height: 1.4, color: BwColors.textMuted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 22, color: BwColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _DefaultToggle extends StatelessWidget {
  const _DefaultToggle({required this.value, required this.onChanged});

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
              const Icon(Icons.home_work_outlined, size: 19, color: BwColors.text),
              const SizedBox(width: BwSpacing.md),
              const Expanded(
                child: Text(
                  'Use as my default address',
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

/// Live delivery estimate for the chosen barangay (or the exact pin when one
/// is set), computed against the same pricing snapshot the cart uses.
class _EstimatePreview extends StatelessWidget {
  const _EstimatePreview({required this.barangayCode, this.lat, this.lng});

  final String barangayCode;
  final double? lat;
  final double? lng;

  @override
  Widget build(BuildContext context) {
    final DeliveryPricing pricing = context.watch<CatalogProvider>().pricing;
    final Barangay? b = LumbanCoverage.byCode(barangayCode);

    if (lat == null || lng == null) {
      if (b == null) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(BwSpacing.md),
          decoration: BoxDecoration(
            color: BwColors.surface,
            borderRadius: BorderRadius.circular(BwRadius.card),
            border: Border.all(color: BwColors.border),
          ),
          child: const Text(
            'Choose a barangay or set a pin to see the delivery estimate.',
            style: TextStyle(fontSize: 12.5, color: BwColors.textMuted),
          ),
        );
      }

      final double km = haversineKm(
        lat1: pricing.cafeLat,
        lng1: pricing.cafeLng,
        lat2: b.lat,
        lng2: b.lng,
      );
      return _buildEstimate(context, pricing, km, pinExact: false);
    }

    // A pin beats the barangay centroid: this is where the rider actually goes.
    final double km = haversineKm(
      lat1: pricing.cafeLat,
      lng1: pricing.cafeLng,
      lat2: lat!,
      lng2: lng!,
    );
    return _buildEstimate(context, pricing, km, pinExact: true);
  }

  Widget _buildEstimate(
    BuildContext context,
    DeliveryPricing pricing,
    double km, {
    required bool pinExact,
  }) {
    final num fee = pricing.feeFor(km: km, subtotal: 0);
    final bool covered = pricing.covers(km);
    final num? freeOver = pricing.freeOver;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(BwSpacing.md),
          decoration: BoxDecoration(
            color: BwColors.surface,
            borderRadius: BorderRadius.circular(BwRadius.card),
            border: Border.all(color: BwColors.border),
          ),
          child: Column(
            children: <Widget>[
              _EstimateRow(
                label: pinExact ? 'Distance (pin)' : 'Distance',
                value: Fmt.distance(km),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: BwSpacing.sm),
                child: Divider(height: 1),
              ),
              _EstimateRow(
                label: 'Delivery fee',
                value: '≈ ${Fmt.peso(fee)}',
                caption: freeOver == null ? null : 'waived on orders ≥ ${Fmt.pesoWhole(freeOver)}',
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: BwSpacing.sm),
                child: Divider(height: 1),
              ),
              _EstimateRow(label: 'Estimated arrival', value: Fmt.eta(Duration(minutes: pricing.etaMinutes(km)))),
            ],
          ),
        ),
        if (!covered) ...<Widget>[
          const SizedBox(height: BwSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(BwSpacing.md),
            decoration: BoxDecoration(
              color: BwColors.subtle,
              borderRadius: BorderRadius.circular(BwRadius.card),
              border: Border.all(color: BwColors.borderStrong, width: BwStroke.strong),
            ),
            child: Text(
              'Beyond the ${pricing.coverableMaxKm.toStringAsFixed(0)} km delivery radius — '
              'we cannot deliver this far yet.',
              style: const TextStyle(fontSize: 12.5, height: 1.4, color: BwColors.text),
            ),
          ),
        ],
      ],
    );
  }
}

class _EstimateRow extends StatelessWidget {
  const _EstimateRow({required this.label, required this.value, this.caption});

  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: BwColors.textMuted),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              value,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: BwColors.text),
            ),
            if (caption != null)
              Text(
                caption!,
                style: const TextStyle(fontSize: 11, color: BwColors.textMuted),
              ),
          ],
        ),
      ],
    );
  }
}