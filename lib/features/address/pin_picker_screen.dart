import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/bw_colors.dart';
import '../../core/theme/bw_metrics.dart';
import '../../core/widgets/bw_button.dart';
import '../../data/models/coverage.dart';

/// Phase 2 pin picker: a free OpenStreetMap-backed full-screen map where the
/// customer drops the exact delivery pin by tapping the map.
///
/// No Google API key, no billing account — tiles come from the public OSM
/// tile server. The tap position is returned as a [LatLng]; the caller stores
/// it on the saved address and the delivery fee becomes pin-to-café instead of
/// barangay-centroid. Requires an internet connection for tiles.
class PinPickerScreen extends StatefulWidget {
  const PinPickerScreen({super.key, this.initial, this.cafeLat, this.cafeLng});

  /// The pin to start at when editing an address that already has one.
  final LatLng? initial;

  /// Where to centre the map when starting fresh (defaults to the café).
  final double? cafeLat;
  final double? cafeLng;

  @override
  State<PinPickerScreen> createState() => _PinPickerScreenState();
}

class _PinPickerScreenState extends State<PinPickerScreen> {
  final MapController _mapController = MapController();
  LatLng? _pin;
  bool _locating = false;

  LatLng get _centre {
    final LatLng? initial = widget.initial;
    if (initial != null) return initial;
    return LatLng(
      widget.cafeLat ?? LumbanCoverage.cafeLat,
      widget.cafeLng ?? LumbanCoverage.cafeLng,
    );
  }

  @override
  void initState() {
    super.initState();
    _pin = widget.initial;
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _toast('Location services are off. Turn them on, then try again.');
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _toast('Location permission is needed to use your current spot.');
        return;
      }

      final Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final LatLng here = LatLng(pos.latitude, pos.longitude);
      setState(() => _pin = here);
      _mapController.move(here, _mapController.camera.zoom);
    } catch (_) {
      _toast('Could not read your location. Tap the map to set the pin.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _confirm() {
    final LatLng? pin = _pin;
    if (pin == null) {
      _toast('Tap the map where your delivery should go, then confirm.');
      return;
    }
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    final LatLng? pin = _pin;

    return Scaffold(
      backgroundColor: BwColors.bg,
      appBar: AppBar(
        title: const Text('Delivery pin'),
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
              child: Stack(
                children: <Widget>[
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _centre,
                      initialZoom: 15,
                      onTap: (TapPosition _, LatLng point) =>
                          setState(() => _pin = point),
                    ),
                    children: <Widget>[
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.highlanderscoffee.highlanders_coffee',
                        maxZoom: 19,
                      ),
                      if (pin != null)
                        MarkerLayer(
                          markers: <Marker>[
                            Marker(
                              point: pin,
                              width: 44,
                              height: 44,
                              child: const _PinDrop(),
                            ),
                          ],
                        ),
                    ],
                  ),
                  // Centered crosshair hint when no pin has been placed yet.
                  if (pin == null)
                    const Positioned.fill(
                      child: IgnorePointer(
                        child: Center(
                          child: Icon(
                            Icons.add_location_alt_outlined,
                            size: 46,
                            color: Color(0x99363F2C),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    right: BwSpacing.md,
                    top: BwSpacing.md,
                    child: BwIconButton(
                      icon: Icons.my_location,
                      size: 46,
                      foreground: BwColors.inverse,
                      onPressed: _locating ? null : _useMyLocation,
                    ),
                  ),
                ],
              ),
            ),
            _PinFooter(
              pin: pin,
              locating: _locating,
              onLocate: _useMyLocation,
              onConfirm: _confirm,
            ),
          ],
        ),
      ),
    );
  }
}

class _PinDrop extends StatelessWidget {
  const _PinDrop();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const Icon(Icons.location_on, size: 34, color: BwColors.inverse),
        const SizedBox(height: 2),
        Container(
          width: 10,
          height: 5,
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: const BorderRadius.all(Radius.elliptical(10, 5)),
            boxShadow: const <BoxShadow>[BoxShadow(blurRadius: 4, color: Colors.black26)],
          ),
        ),
      ],
    );
  }
}

class _PinFooter extends StatelessWidget {
  const _PinFooter({
    required this.pin,
    required this.locating,
    required this.onLocate,
    required this.onConfirm,
  });

  final LatLng? pin;
  final bool locating;
  final VoidCallback onLocate;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final LatLng? p = pin;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(BwSpacing.gutter, BwSpacing.md, BwSpacing.gutter, BwSpacing.lg),
      decoration: const BoxDecoration(
        color: BwColors.surface,
        border: Border(top: BorderSide(color: BwColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(BwSpacing.md),
            decoration: BoxDecoration(
              color: BwColors.subtle,
              borderRadius: BorderRadius.circular(BwRadius.card),
              border: Border.all(color: BwColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.place_outlined, size: 17, color: BwColors.textMuted),
                    const SizedBox(width: BwSpacing.sm),
                    Expanded(
                      child: Text(
                        p == null
                            ? 'Tap the map where the delivery should go.'
                            : 'Move the pin to fine-tune the delivery spot.',
                        style: const TextStyle(fontSize: 12.5, height: 1.4, color: BwColors.textMuted),
                      ),
                    ),
                  ],
                ),
                if (p != null) ...<Widget>[
                  const SizedBox(height: BwSpacing.xs),
                  Text(
                    '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: BwColors.text),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: BwSpacing.md),
          BwButton(
            label: locating ? 'Reading location…' : 'Use my current location',
            icon: Icons.my_location,
            variant: BwButtonVariant.outlined,
            onPressed: locating ? null : onLocate,
          ),
          const SizedBox(height: BwSpacing.sm),
          BwButton(
            label: 'Confirm delivery pin',
            icon: Icons.check_rounded,
            onPressed: onConfirm,
          ),
          const SizedBox(height: BwSpacing.sm),
          const Text(
            'Pin-exact delivery needs an internet connection for this map.',
            style: TextStyle(fontSize: 11, color: BwColors.textMuted),
          ),
        ],
      ),
    );
  }
}