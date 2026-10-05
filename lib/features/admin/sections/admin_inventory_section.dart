import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/bw_colors.dart';
import '../../../core/theme/bw_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/bw_card.dart';
import '../../../data/models/menu.dart';
import '../../../state/catalog_provider.dart';
import '../admin_dashboard_screen.dart';
import 'admin_overview_section.dart';
import 'admin_sheet_actions.dart';

/// Inventory management: the full menu with stock levels, plus add/edit.
///
/// The table lives inside a horizontal scroll because five columns do not fit a
/// 360dp phone; fixed column widths keep every cell from being squashed into
/// ellipsis soup.
class AdminInventorySection extends StatefulWidget {
  const AdminInventorySection({super.key});

  @override
  State<AdminInventorySection> createState() => _AdminInventorySectionState();
}

class _AdminInventorySectionState extends State<AdminInventorySection> {
  /// Null means "no filter"; otherwise only that category is shown.
  String? _categoryId;

  @override
  Widget build(BuildContext context) {
    final CatalogProvider catalog = context.watch<CatalogProvider>();

    final List<MenuItem> items = _categoryId == null
        ? catalog.allItems
        : catalog.allItems
            .where((MenuItem i) => i.categoryId == _categoryId)
            .toList(growable: false);

    return Scaffold(
      backgroundColor: BwColors.bg,
      floatingActionButton: BwFab(
        label: 'Add item',
        icon: Icons.add_rounded,
        onPressed: () => _openItemSheet(context, null),
      ),
      body: Column(
        children: <Widget>[
          _CategoryFilterBar(
            categories: catalog.categories,
            selected: _categoryId,
            onChanged: (String? id) => setState(() => _categoryId = id),
          ),
          const SizedBox(height: BwSpacing.sm),
          Expanded(
            child: items.isEmpty
                ? const AdminEmptyState(
                    message: 'No items in this category yet.',
                    icon: Icons.inventory_2_outlined,
                  )
                : SingleChildScrollView(
                    // Horizontal scroll only — the table manages its own
                    // vertical extent via shrink-wrapped rows.
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: BwSpacing.gutter),
                      child: _InventoryTable(
                        items: items,
                        catalog: catalog,
                        onEdit: (MenuItem item) => _openItemSheet(context, item),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _openItemSheet(BuildContext context, MenuItem? existing) async {
    final CatalogProvider catalog = context.read<CatalogProvider>();

    final _ItemDraft? draft = await showModalBottomSheet<_ItemDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ItemFormSheet(
        existing: existing,
        categories: catalog.categories,
      ),
    );

    if (draft == null) return;

    catalog.upsertItem(
      MenuItem(
        id: existing?.id ?? 'm-${DateTime.now().millisecondsSinceEpoch}',
        categoryId: draft.categoryId,
        name: draft.name,
        price: draft.price,
        description: draft.description,
        isAvailable: draft.isAvailable,
        isBestseller: existing?.isBestseller ?? false,
        prepMinutes: existing?.prepMinutes ?? 5,
        sortOrder: existing?.sortOrder ?? catalog.allItems.length,
        stock: draft.stock,
        reorderLevel: draft.reorderLevel,
      ),
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(existing == null ? 'Added ${draft.name}' : 'Updated ${draft.name}')),
      );
  }
}

/// Category filter pills, with a leading "All" chip.
class _CategoryFilterBar extends StatelessWidget {
  const _CategoryFilterBar({
    required this.categories,
    required this.selected,
    required this.onChanged,
  });

  final List<MenuCategory> categories;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: BwSpacing.gutter),
        children: <Widget>[
          _CategoryChip(
            label: 'All',
            isSelected: selected == null,
            onTap: () => onChanged(null),
          ),
          for (final MenuCategory c in categories)
            _CategoryChip(
              label: c.label,
              isSelected: selected == c.id,
              onTap: () => onChanged(c.id),
            ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.isSelected, required this.onTap});

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

/// The stock table.
///
/// Every column is wrapped in a fixed-width box with an ellipsising label;
/// without that, [DataTable] sizes cells to their content and long item names
/// push the table arbitrarily wide.
class _InventoryTable extends StatelessWidget {
  const _InventoryTable({
    required this.items,
    required this.catalog,
    required this.onEdit,
  });

  final List<MenuItem> items;
  final CatalogProvider catalog;
  final ValueChanged<MenuItem> onEdit;

  static const double _nameWidth = 168;
  static const double _categoryWidth = 96;
  static const double _priceWidth = 84;
  static const double _stockWidth = 72;
  static const double _statusWidth = 124;
  static const double _actionWidth = 64;

  @override
  Widget build(BuildContext context) {
    return BwCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: DataTable(
          headingRowHeight: 42,
          dataRowMinHeight: 48,
          dataRowMaxHeight: 56,
          columnSpacing: BwSpacing.md,
          horizontalMargin: BwSpacing.md,
          dividerThickness: BwStroke.hairline,
          headingTextStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: BwColors.textMuted,
          ),
          dataTextStyle: const TextStyle(fontSize: 13.5, color: BwColors.text),
          columns: const <DataColumn>[
            DataColumn(label: Text('ITEM')),
            DataColumn(label: Text('CATEGORY')),
            DataColumn(label: Text('PRICE'), numeric: true),
            DataColumn(label: Text('STOCK'), numeric: true),
            DataColumn(label: Text('STATUS')),
            DataColumn(label: Text('')),
          ],
          rows: items
              .map((MenuItem item) => DataRow(
                    onSelectChanged: (_) => onEdit(item),
                    cells: <DataCell>[
                      DataCell(
                        SizedBox(
                          width: _nameWidth,
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: BwColors.text,
                                  ),
                                ),
                              ),
                              if (!item.isAvailable)
                                const Icon(
                                  Icons.visibility_off_outlined,
                                  size: 14,
                                  color: BwColors.textMuted,
                                ),
                            ],
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: _categoryWidth,
                          child: Text(
                            catalog.labelForCategory(item.categoryId),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: BwColors.textMuted),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: _priceWidth,
                          child: Text(
                            Fmt.pesoWhole(item.price),
                            textAlign: TextAlign.right,
                            maxLines: 1,
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: _stockWidth,
                          child: Text(
                            '${item.stock}',
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: item.status == StockStatus.outOfStock
                                  ? BwColors.textMuted
                                  : BwColors.text,
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: _statusWidth,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: StockStatusBadge(status: item.status),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: _actionWidth,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: <Widget>[
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 17),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                onPressed: () => onEdit(item),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ))
              .toList(growable: false),
        ),
      ),
    );
  }
}

/// Result of the add/edit form.
@immutable
class _ItemDraft {
  const _ItemDraft({
    required this.name,
    required this.price,
    required this.stock,
    required this.categoryId,
    required this.reorderLevel,
    required this.isAvailable,
    required this.description,
  });

  final String name;
  final num price;
  final int stock;
  final String categoryId;
  final int reorderLevel;
  final bool isAvailable;
  final String description;
}

/// Add / edit sheet.
///
/// `isScrollControlled` plus an explicit bottom inset keeps the fields above
/// the keyboard on short screens, which a plain bottom sheet does not.
class _ItemFormSheet extends StatefulWidget {
  const _ItemFormSheet({required this.existing, required this.categories});

  final MenuItem? existing;
  final List<MenuCategory> categories;

  @override
  State<_ItemFormSheet> createState() => _ItemFormSheetState();
}

class _ItemFormSheetState extends State<_ItemFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _name = TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _price =
      TextEditingController(text: widget.existing == null ? '' : '${widget.existing!.price}');
  late final TextEditingController _stock =
      TextEditingController(text: widget.existing == null ? '' : '${widget.existing!.stock}');
  late final TextEditingController _reorder =
      TextEditingController(text: '${widget.existing?.reorderLevel ?? 10}');
  late final TextEditingController _description =
      TextEditingController(text: widget.existing?.description ?? '');

  late String _categoryId = widget.existing?.categoryId ?? widget.categories.first.id;
  late bool _isAvailable = widget.existing?.isAvailable ?? true;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _stock.dispose();
    _reorder.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    Navigator.of(context).pop(
      _ItemDraft(
        name: _name.text.trim(),
        price: num.tryParse(_price.text.trim()) ?? 0,
        stock: int.tryParse(_stock.text.trim()) ?? 0,
        categoryId: _categoryId,
        reorderLevel: int.tryParse(_reorder.text.trim()) ?? 10,
        isAvailable: _isAvailable,
        description: _description.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool editing = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Padding(
                padding: const EdgeInsets.all(BwSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      editing ? 'Edit item' : 'Add item',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: BwColors.text,
                      ),
                    ),
                    const SizedBox(height: BwSpacing.xl),

                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(fontSize: 15, color: BwColors.text),
                      decoration: const InputDecoration(labelText: 'Item name'),
                      validator: (String? v) =>
                          (v ?? '').trim().isEmpty ? 'Enter an item name.' : null,
                    ),
                    const SizedBox(height: BwSpacing.md),

                    DropdownButtonFormField<String>(
                      initialValue: _categoryId,
                      isExpanded: true,
                      style: const TextStyle(fontSize: 15, color: BwColors.text),
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: widget.categories
                          .map((MenuCategory c) => DropdownMenuItem<String>(
                                value: c.id,
                                child: Text(c.label, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(growable: false),
                      onChanged: (String? v) => setState(() => _categoryId = v ?? _categoryId),
                    ),
                    const SizedBox(height: BwSpacing.md),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: TextFormField(
                            controller: _price,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(fontSize: 15, color: BwColors.text),
                            decoration: const InputDecoration(
                              labelText: 'Price',
                              prefixText: '₱ ',
                            ),
                            validator: (String? v) {
                              final num? parsed = num.tryParse((v ?? '').trim());
                              if (parsed == null || parsed <= 0) return 'Enter a price.';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: BwSpacing.sm),
                        Expanded(
                          child: TextFormField(
                            controller: _stock,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 15, color: BwColors.text),
                            decoration: const InputDecoration(labelText: 'Stock count'),
                            validator: (String? v) {
                              final int? parsed = int.tryParse((v ?? '').trim());
                              if (parsed == null || parsed < 0) return 'Enter a count.';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: BwSpacing.md),

                    TextFormField(
                      controller: _reorder,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 15, color: BwColors.text),
                      decoration: const InputDecoration(
                        labelText: 'Reorder level',
                        helperText: 'Flagged as low stock at or below this count',
                      ),
                      validator: (String? v) {
                        final int? parsed = int.tryParse((v ?? '').trim());
                        if (parsed == null || parsed < 0) return 'Enter a level.';
                        return null;
                      },
                    ),
                    const SizedBox(height: BwSpacing.md),

                    TextFormField(
                      controller: _description,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 15, color: BwColors.text),
                      decoration: const InputDecoration(labelText: 'Description (optional)'),
                    ),
                    const SizedBox(height: BwSpacing.md),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: BwSpacing.md,
                        vertical: BwSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(BwRadius.field),
                        border: Border.all(color: BwColors.border),
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const Text(
                                  'Listed on the shop',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: BwColors.text,
                                  ),
                                ),
                                Text(
                                  _isAvailable ? 'Visible to customers' : 'Hidden from the menu',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: BwColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _isAvailable,
                            onChanged: (bool v) => setState(() => _isAvailable = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: BwSpacing.xl),

                    AdminSheetActions(
                      submitLabel: editing ? 'Save changes' : 'Add item',
                      onSubmit: _submit,
                      deleteTooltip: 'Remove item',
                      onDelete: editing ? () => _confirmDelete(context) : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final MenuItem? item = widget.existing;
    if (item == null) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: BwColors.surface,
        surfaceTintColor: BwColors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BwRadius.card),
          side: const BorderSide(color: BwColors.border),
        ),
        title: const Text(
          'Remove item',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: BwColors.text),
        ),
        content: Text(
          'Take ${item.name} off the menu? Existing orders keep their lines.',
          style: const TextStyle(fontSize: 14, height: 1.45, color: BwColors.textMuted),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    context.read<CatalogProvider>().removeItem(item.id);
    Navigator.of(context).pop();
  }
}

/// Compact status chip, re-exported so the sheet and table agree on styling.
class InventoryStatusChip extends StatelessWidget {
  const InventoryStatusChip({super.key, required this.status});

  final StockStatus status;

  @override
  Widget build(BuildContext context) {
    return StockStatusBadge(status: status);
  }
}