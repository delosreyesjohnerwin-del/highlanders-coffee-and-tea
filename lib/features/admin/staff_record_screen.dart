import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/bw_colors.dart';
import '../../core/theme/bw_metrics.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/bw_badge.dart';
import '../../data/models/staff.dart';
import '../../data/models/staff_record.dart';
import '../../state/admin_provider.dart';
import 'admin_dashboard_screen.dart';
import 'sections/admin_overview_section.dart';

/// Opens the staff attendance record on top of the admin panel.
Future<void> openStaffRecord(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (BuildContext _) => const StaffRecordScreen()),
  );
}

/// The time-in / time-out ledger for every staff member.
///
/// A live board: while the panel is bound the provider streams `staffRecords`,
/// so a scan on another kiosk appears as a new row — or repaints a row's Time
/// Out — without a manual refresh.
///
/// A session is one row, not two events: a clock-in opens it with a Time In, the
/// matching clock-out fills in the same row's Time Out and flips its status. That
/// is why the table reads left-to-right as a shift rather than as a log.
class StaffRecordScreen extends StatefulWidget {
  const StaffRecordScreen({super.key});

  @override
  State<StaffRecordScreen> createState() => _StaffRecordScreenState();
}

class _StaffRecordScreenState extends State<StaffRecordScreen> {
  /// True shows only today's sessions; false shows the whole history.
  bool _todayOnly = true;

  @override
  void initState() {
    super.initState();
    // Prime from the repository in case the live stream has not emitted yet (the
    // in-memory repository only emits on write). Deferred to after the first
    // frame so the read cannot notify listeners mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<AdminProvider>().loadStaffRecordsOnce());
    });
  }

  @override
  Widget build(BuildContext context) {
    final AdminProvider admin = context.watch<AdminProvider>();
    final String todayKey = StaffRecord.dateKeyFor(DateTime.now());

    final List<StaffRecord> all = admin.staffRecords;
    final List<StaffRecord> today = all
        .where((StaffRecord r) => r.dateKey == todayKey)
        .toList(growable: false);
    final List<StaffRecord> shown = _todayOnly ? today : all;

    return Scaffold(
      backgroundColor: BwColors.bg,
      appBar: AppBar(
        backgroundColor: BwColors.bg,
        foregroundColor: BwColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Staff Record',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: BwColors.text),
        ),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              BwSpacing.gutter,
              BwSpacing.sm,
              BwSpacing.gutter,
              BwSpacing.sm,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: AdminStat(
                    label: 'Active shifts',
                    value: '${all.where((StaffRecord r) => r.isOpen).length}',
                    icon: Icons.timelapse_rounded,
                  ),
                ),
                const SizedBox(width: BwSpacing.sm),
                Expanded(
                  child: AdminStat(
                    label: 'Sessions today',
                    value: '${today.length}',
                    icon: Icons.fact_check_outlined,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BwSpacing.gutter),
            child: Row(
              children: <Widget>[
                _FilterPill(
                  label: 'Today (${today.length})',
                  isSelected: _todayOnly,
                  onTap: () => setState(() => _todayOnly = true),
                ),
                _FilterPill(
                  label: 'All (${all.length})',
                  isSelected: !_todayOnly,
                  onTap: () => setState(() => _todayOnly = false),
                ),
              ],
            ),
          ),
          const SizedBox(height: BwSpacing.md),
          Expanded(
            child: shown.isEmpty
                ? AdminEmptyState(
                    message: _todayOnly
                        ? 'No shifts recorded today yet.\nScan a badge at the counter to log one.'
                        : 'No shifts recorded yet.\nScan a badge at the counter to log one.',
                    icon: Icons.assignment_outlined,
                  )
                : _RecordTable(records: shown),
          ),
        ],
      ),
    );
  }
}

/// The table itself, horizontally scrollable so all seven columns stay legible
/// on a phone.
class _RecordTable extends StatelessWidget {
  const _RecordTable({required this.records});

  final List<StaffRecord> records;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          BwSpacing.gutter,
          0,
          BwSpacing.gutter,
          BwSpacing.xxl,
        ),
        child: DataTable(
          headingRowHeight: 40,
          dataRowMinHeight: 44,
          dataRowMaxHeight: 60,
          columnSpacing: 20,
          horizontalMargin: 0,
          headingRowColor: const WidgetStatePropertyAll<Color>(BwColors.subtle),
          border: TableBorder(
            horizontalInside: BorderSide(color: BwColors.border),
          ),
          columns: const <DataColumn>[
            DataColumn(label: _Heading('Staff ID')),
            DataColumn(label: _Heading('Staff Name')),
            DataColumn(label: _Heading('Role')),
            DataColumn(label: _Heading('Date')),
            DataColumn(label: _Heading('Time In')),
            DataColumn(label: _Heading('Time Out')),
            DataColumn(label: _Heading('Status')),
          ],
          rows: <DataRow>[
            for (final StaffRecord r in records) _row(r),
          ],
        ),
      ),
    );
  }

  DataRow _row(StaffRecord r) => DataRow(
        cells: <DataCell>[
          DataCell(_Cell(r.staffId)),
          DataCell(_Cell(r.staffName, bold: true)),
          DataCell(_Cell(r.role.label)),
          DataCell(_Cell(Fmt.date(r.timeIn))),
          DataCell(_Cell(Fmt.time(r.timeIn))),
          DataCell(_Cell(r.timeOut == null ? '—' : Fmt.time(r.timeOut!))),
          DataCell(
            BwBadge(
              label: r.status.label,
              variant: r.isOpen ? BwBadgeVariant.solid : BwBadgeVariant.outline,
              dense: true,
            ),
          ),
        ],
      );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        color: BwColors.textMuted,
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.text, {this.bold = false});

  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        color: BwColors.text,
      ),
    );
  }
}

/// Two-state pill matching the roster's role chips.
class _FilterPill extends StatelessWidget {
  const _FilterPill({required this.label, required this.isSelected, required this.onTap});

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
