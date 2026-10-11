import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/bw_colors.dart';
import '../../core/theme/bw_metrics.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/bw_badge.dart';
import '../../core/widgets/bw_button.dart';
import '../../data/models/shift_event.dart';
import '../../data/models/staff.dart';
import '../../services/staff_qr.dart';
import '../../state/admin_provider.dart';

/// The QR badge preview shown in a staff row.
///
/// Renders the member's stored token, and on first build asks the provider to
/// mint one if the roster predates badges — which is why it must be a
/// [StatefulWidget]: the request is deferred to a post-frame callback so it
/// never notifies listeners mid-build.
class StaffQrThumbnail extends StatefulWidget {
  const StaffQrThumbnail({super.key, required this.member, this.size = 58});

  final StaffMember member;
  final double size;

  @override
  State<StaffQrThumbnail> createState() => _StaffQrThumbnailState();
}

class _StaffQrThumbnailState extends State<StaffQrThumbnail> {
  @override
  void initState() {
    super.initState();
    if (widget.member.qrToken == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<AdminProvider>().ensureStaffQr(widget.member.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Uri? uri = staffQrUri(widget.member);

    final Widget face = uri == null
        ? const Icon(Icons.qr_code_2_rounded, size: 26, color: BwColors.disabled)
        : QrImageView(
            data: uri.toString(),
            version: QrVersions.auto,
            size: widget.size - 10,
            padding: EdgeInsets.zero,
            backgroundColor: BwColors.onInverse,
            errorCorrectionLevel: QrErrorCorrectLevel.M,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: BwColors.text,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: BwColors.text,
            ),
          );

    return Tooltip(
      message: 'Staff QR badge',
      child: Material(
        color: BwColors.onInverse,
        borderRadius: BorderRadius.circular(BwRadius.chip),
        child: InkWell(
          onTap: () => showStaffQrSheet(context, widget.member.id),
          borderRadius: BorderRadius.circular(BwRadius.chip),
          child: Container(
            width: widget.size,
            height: widget.size,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BwRadius.chip),
              border: Border.all(color: BwColors.border),
            ),
            child: face,
          ),
        ),
      ),
    );
  }
}

/// Opens the large badge view for [staffId].
Future<void> showStaffQrSheet(BuildContext context, String staffId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: BwColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(BwRadius.card)),
    ),
    builder: (BuildContext ctx) => _StaffQrSheet(staffId: staffId),
  );
}

class _StaffQrSheet extends StatefulWidget {
  const _StaffQrSheet({required this.staffId});

  final String staffId;

  @override
  State<_StaffQrSheet> createState() => _StaffQrSheetState();
}

class _StaffQrSheetState extends State<_StaffQrSheet> {
  final GlobalKey _qrKey = GlobalKey();

  late Future<List<ShiftEvent>> _history;

  @override
  void initState() {
    super.initState();
    _history = context.read<AdminProvider>().loadShiftEvents(widget.staffId);
  }

  /// Rasterises the on-screen QR at 8× so a saved or printed badge is sharp
  /// enough to scan after being shrunk into an ID-sized frame.
  Future<Uint8List?> _captureQr() async {
    final RenderObject? object = _qrKey.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return null;

    final ui.Image image = await object.toImage(pixelRatio: 8);
    final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }

  Future<void> _download(StaffMember member, ScaffoldMessengerState messenger) async {
    final Uint8List? bytes = await _captureQr();
    if (bytes == null) return;

    try {
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile.fromData(
              bytes,
              mimeType: 'image/png',
              name: 'highlanders-staff-${member.id}.png',
            ),
          ],
          subject: 'Highlanders staff badge — ${member.name}',
          text: 'Highlanders staff badge for ${member.name} (${member.id}).',
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the share sheet on this device.')),
      );
    }
  }

  Future<void> _print(StaffMember member, ScaffoldMessengerState messenger) async {
    final Uint8List? bytes = await _captureQr();
    if (bytes == null) return;

    try {
      final pw.Document document = pw.Document();
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a6,
          build: (pw.Context ctx) => pw.Center(
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: <pw.Widget>[
                pw.Text(
                  'Highlanders Coffee & Tea',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  member.name,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 17),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  '${member.role.label} · ${member.id}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
                pw.SizedBox(height: 16),
                pw.Image(pw.MemoryImage(bytes), width: 250, height: 250),
                pw.SizedBox(height: 12),
                pw.Text(
                  'Scan at the counter to clock in or out.',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
          ),
        ),
      );
      await Printing.layoutPdf(onLayout: (PdfPageFormat format) => document.save());
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Printing is not available on this device.')),
      );
    }
  }

  Future<void> _regenerate(StaffMember member) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Regenerate QR badge?'),
        content: Text(
          'A new code is issued for ${member.name}. Any badge already printed or '
          'saved stops working immediately.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep current'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await context.read<AdminProvider>().regenerateStaffQr(member.id);
    if (!mounted) return;
    setState(() {
      _history = context.read<AdminProvider>().loadShiftEvents(widget.staffId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AdminProvider admin = context.watch<AdminProvider>();
    final StaffMember? member = admin.staffById(widget.staffId);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    if (member == null) {
      return const Padding(
        padding: EdgeInsets.all(BwSpacing.xxl),
        child: Text('This staff member is no longer on the roster.'),
      );
    }

    final Uri? uri = staffQrUri(member);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          BwSpacing.gutter,
          0,
          BwSpacing.gutter,
          BwSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: BwSpacing.sm),
            Text(
              'Staff badge',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: BwColors.text,
              ),
            ),
            const SizedBox(height: BwSpacing.xs),
            Text(
              member.name,
              style: const TextStyle(fontSize: 13.5, color: BwColors.textMuted),
            ),
            const SizedBox(height: BwSpacing.md),

            Center(
              child: RepaintBoundary(
                key: _qrKey,
                child: Container(
                  padding: const EdgeInsets.all(BwSpacing.lg),
                  decoration: BoxDecoration(
                    color: BwColors.onInverse,
                    borderRadius: BorderRadius.circular(BwRadius.card),
                    border: Border.all(color: BwColors.border),
                  ),
                  child: uri == null
                      ? const SizedBox(
                          width: 240,
                          height: 240,
                          child: Center(
                            child: Icon(
                              Icons.qr_code_2_rounded,
                              size: 72,
                              color: BwColors.disabled,
                            ),
                          ),
                        )
                      : QrImageView(
                          data: uri.toString(),
                          version: QrVersions.auto,
                          size: 240,
                          padding: EdgeInsets.zero,
                          backgroundColor: BwColors.onInverse,
                          errorCorrectionLevel: QrErrorCorrectLevel.M,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: BwColors.text,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: BwColors.text,
                          ),
                        ),
                ),
              ),
            ),

            const SizedBox(height: BwSpacing.md),
            Row(
              children: <Widget>[
                BwBadge(
                  label: member.role.label,
                  variant: BwBadgeVariant.solid,
                  icon: member.role.icon,
                  dense: true,
                ),
                const SizedBox(width: BwSpacing.sm),
                Expanded(
                  child: Text(
                    'ID ${member.id}',
                    style: const TextStyle(fontSize: 12.5, color: BwColors.textMuted),
                  ),
                ),
              ],
            ),
            if (member.qrIssuedAt != null) ...<Widget>[
              const SizedBox(height: BwSpacing.xs),
              Text(
                'Issued ${Fmt.dateTime(member.qrIssuedAt!)}',
                style: const TextStyle(fontSize: 12, color: BwColors.textMuted),
              ),
            ],

            const SizedBox(height: BwSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: BwButton(
                    label: 'Download',
                    icon: Icons.download_rounded,
                    variant: BwButtonVariant.outlined,
                    height: 46,
                    onPressed: uri == null ? null : () => _download(member, messenger),
                  ),
                ),
                const SizedBox(width: BwSpacing.sm),
                Expanded(
                  child: BwButton(
                    label: 'Print',
                    icon: Icons.print_outlined,
                    variant: BwButtonVariant.outlined,
                    height: 46,
                    onPressed: uri == null ? null : () => _print(member, messenger),
                  ),
                ),
              ],
            ),
            const SizedBox(height: BwSpacing.sm),
            BwButton(
              label: 'Regenerate QR',
              icon: Icons.autorenew_rounded,
              variant: BwButtonVariant.ghost,
              height: 44,
              onPressed: () => _regenerate(member),
            ),

            const SizedBox(height: BwSpacing.lg),
            const Divider(height: 1),
            const SizedBox(height: BwSpacing.md),
            const Text(
              'Recent shifts',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: BwColors.text,
              ),
            ),
            const SizedBox(height: BwSpacing.sm),
            FutureBuilder<List<ShiftEvent>>(
              future: _history,
              builder: (BuildContext ctx, AsyncSnapshot<List<ShiftEvent>> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: BwSpacing.md),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }

                final List<ShiftEvent> events = snapshot.data ?? const <ShiftEvent>[];
                if (events.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: BwSpacing.md),
                    child: Text(
                      'No shifts recorded yet. Scan this badge to clock in.',
                      style: TextStyle(fontSize: 12.5, color: BwColors.textMuted),
                    ),
                  );
                }

                return Column(
                  children: <Widget>[
                    for (final ShiftEvent event in events.take(8))
                      _ShiftRow(event: event),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ShiftRow extends StatelessWidget {
  const _ShiftRow({required this.event});

  final ShiftEvent event;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Icon(event.type.icon, size: 16, color: BwColors.textMuted),
          const SizedBox(width: BwSpacing.sm),
          Expanded(
            child: Text(
              event.type.label,
              style: const TextStyle(fontSize: 13, color: BwColors.text),
            ),
          ),
          Text(
            Fmt.dateTime(event.at),
            style: const TextStyle(fontSize: 12, color: BwColors.textMuted),
          ),
        ],
      ),
    );
  }
}
