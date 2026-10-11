import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../core/theme/bw_colors.dart';
import '../../core/theme/bw_metrics.dart';
import '../../services/staff_qr.dart';
import '../../state/admin_provider.dart';

/// Opens the kiosk scanner on top of the admin panel.
Future<void> openStaffQrScanner(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (BuildContext _) => const StaffQrScannerScreen()),
  );
}

/// Kiosk scanner: reads a staff badge and clocks that member in or out.
///
/// Runs on the admin-signed-in device only. That is not a limitation to work
/// around — it is the trust model: the roster is admin-readable under the rules,
/// so the kiosk is the one device that can verify a token against it.
///
/// A scan toggles the member between on-shift and off-shift, so the same badge
/// clocks someone in on the way in and out on the way out. The screen stays open
/// after a hit (a queue of arrivals) and simply cools down for a moment so one
/// badge is not counted twice by the same camera frame.
class StaffQrScannerScreen extends StatefulWidget {
  const StaffQrScannerScreen({super.key});

  @override
  State<StaffQrScannerScreen> createState() => _StaffQrScannerScreenState();
}

class _StaffQrScannerScreenState extends State<StaffQrScannerScreen> {
  late final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
  );

  /// Guards against a burst of frames resolving to a clock event each.
  bool _processing = false;

  StaffClockResult? _lastResult;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handle(BarcodeCapture capture) async {
    if (_processing) return;

    final String? raw = capture.barcodes
        .map((Barcode b) => b.rawValue)
        .firstWhere((String? v) => v != null && v.isNotEmpty, orElse: () => null);
    if (raw == null) return;

    _processing = true;

    final StaffClockResult result = context.read<AdminProvider>().clockByToken(raw);
    if (!mounted) return;
    setState(() => _lastResult = result);

    // Cool down, then resume accepting badges. Long enough to read the banner,
    // short enough that the next person in the queue is not waiting.
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;
    setState(() => _processing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BwColors.text,
      appBar: AppBar(
        backgroundColor: BwColors.text,
        foregroundColor: BwColors.onInverse,
        title: const Text('Scan staff badge'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Torch',
            icon: const Icon(Icons.flashlight_on_rounded),
            onPressed: () async {
              try {
                await _controller.toggleTorch();
              } catch (_) {
                // No flash unit, or the camera is not ready yet.
              }
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          MobileScanner(
            controller: _controller,
            onDetect: _handle,
            errorBuilder: (BuildContext context, MobileScannerException error) => _CameraMessage(
              message: error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? 'Camera permission is needed to scan a badge.'
                  : 'The camera could not be started.',
            ),
          ),
          _ScanFrame(),
          if (_lastResult != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(BwSpacing.gutter),
                child: _ResultBanner(result: _lastResult!),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScanFrame extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(BwRadius.card),
                border: Border.all(color: BwColors.onInverse, width: 3),
              ),
            ),
            const SizedBox(height: BwSpacing.lg),
            const Text(
              'Point the camera at a staff QR badge',
              style: TextStyle(color: BwColors.onInverse, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.result});

  final StaffClockResult result;

  @override
  Widget build(BuildContext context) {
    final bool ok = result.isSuccess;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: BwSpacing.lg, vertical: BwSpacing.md),
      decoration: BoxDecoration(
        color: ok ? BwColors.onInverse : BwColors.subtle,
        borderRadius: BorderRadius.circular(BwRadius.card),
        border: Border.all(color: BwColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            size: 20,
            color: ok ? BwColors.inverse : BwColors.textMuted,
          ),
          const SizedBox(width: BwSpacing.sm),
          Flexible(
            child: Text(
              result.message,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: ok ? BwColors.text : BwColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraMessage extends StatelessWidget {
  const _CameraMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: BwColors.text,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(BwSpacing.xxl),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: BwColors.onInverse, fontSize: 14),
          ),
        ),
      ),
    );
  }
}
