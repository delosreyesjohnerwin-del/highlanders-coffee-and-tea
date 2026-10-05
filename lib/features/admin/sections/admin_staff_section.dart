import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/bw_colors.dart';
import '../../../core/theme/bw_metrics.dart';
import '../../../core/widgets/bw_badge.dart';
import '../../../core/widgets/bw_button.dart';
import '../../../core/widgets/bw_card.dart';
import '../../../data/models/staff.dart';
import '../../../state/admin_provider.dart';
import '../admin_dashboard_screen.dart';
import 'admin_overview_section.dart';

/// Who is on the floor, what they can reach, and whether their shift is
/// running.
class AdminStaffSection extends StatefulWidget {
  const AdminStaffSection({super.key});

  @override
  State<AdminStaffSection> createState() => _AdminStaffSectionState();
}

class _AdminStaffSectionState extends State<AdminStaffSection> {
  /// Null means every role.
  StaffRole? _filter;

  @override
  Widget build(BuildContext context) {
    final AdminProvider admin = context.watch<AdminProvider>();

    final List<StaffMember> staff = _filter == null
        ? admin.staff
        : admin.staff.where((StaffMember s) => s.role == _filter).toList(growable: false);

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: BwSpacing.md),
          child: SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: BwSpacing.gutter),
              children: <Widget>[
                _RoleChip(
                  label: 'All (${admin.staff.length})',
                  isSelected: _filter == null,
                  onTap: () => setState(() => _filter = null),
                ),
                for (final StaffRole role in StaffRole.values)
                  _RoleChip(
                    label: '${role.label} (${admin.staff.where((StaffMember s) => s.role == role).length})',
                    isSelected: _filter == role,
                    onTap: () => setState(() => _filter = role),
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
                  label: 'On shift now',
                  value: '${admin.onShift.length}',
                  icon: Icons.how_to_reg_outlined,
                ),
              ),
              const SizedBox(width: BwSpacing.sm),
              Expanded(
                child: AdminStat(
                  label: 'Riders free',
                  value: '${admin.riderNames.length}',
                  icon: Icons.delivery_dining_outlined,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: staff.isEmpty
              ? const AdminEmptyState(message: 'No staff in this role.', icon: Icons.badge_outlined)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    BwSpacing.gutter,
                    0,
                    BwSpacing.gutter,
                    BwSpacing.xxl,
                  ),
                  itemCount: staff.length,
                  separatorBuilder: (_, _) => const SizedBox(height: BwSpacing.sm),
                  itemBuilder: (BuildContext context, int i) => _StaffCard(member: staff[i]),
                ),
        ),
      ],
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.member});

  final StaffMember member;

  @override
  Widget build(BuildContext context) {
    final AdminProvider admin = context.read<AdminProvider>();

    return BwCard(
      padding: const EdgeInsets.all(BwSpacing.md),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: member.shift.isWorking ? BwColors.inverse : BwColors.subtle,
                  borderRadius: BorderRadius.circular(BwRadius.chip),
                  border: Border.all(
                    color: member.shift.isWorking ? BwColors.inverse : BwColors.border,
                  ),
                ),
                child: Text(
                  staffInitials(member.name),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: member.shift.isWorking ? BwColors.onInverse : BwColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: BwSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      member.name,
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
                      member.phone ?? 'No number on file',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: BwColors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: BwSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  BwBadge(
                    label: member.role.label,
                    variant: BwBadgeVariant.solid,
                    icon: member.role.icon,
                    dense: true,
                  ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        member.shift.icon,
                        size: 12,
                        color: BwColors.textMuted,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        member.shift.label,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: BwColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: BwSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: BwSpacing.md),

          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      'Handled today',
                      style: TextStyle(fontSize: 11.5, color: BwColors.textMuted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${member.completedToday}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: BwColors.text,
                      ),
                    ),
                  ],
                ),
              ),
              BwButton(
                label: member.shift.isWorking ? 'End shift' : 'Start shift',
                variant: member.shift.isWorking
                    ? BwButtonVariant.outlined
                    : BwButtonVariant.solid,
                height: 40,
                // Sits beside the stat block, so it must size to content;
                // `expand` would ask for an infinite width inside this Row.
                expand: false,
                onPressed: () => admin.toggleShift(member.id),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label, required this.isSelected, required this.onTap});

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

/// "Aiko Ramos" becomes "AR"; "Carla" becomes "C".
///
/// Falls back to the first character rather than throwing, because a staff
/// record with a blank name is data the panel should still render.
String staffInitials(String name) {
  final List<String> parts = name.trim().split(RegExp(r'\s+'))
      .where((String p) => p.isNotEmpty)
      .toList();

  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();

  return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
}