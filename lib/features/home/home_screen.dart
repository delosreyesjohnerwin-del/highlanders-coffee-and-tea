import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/bw_colors.dart';
import '../../core/theme/bw_metrics.dart';
import '../../core/widgets/bw_avatar.dart';
import '../../core/widgets/bw_badge.dart';
import '../../core/widgets/bw_button.dart';
import '../../core/widgets/bw_pill.dart';
import '../../core/widgets/bw_segment.dart';
import '../../data/models/menu.dart';
import '../../data/models/order.dart';
import '../../state/catalog_provider.dart';
import '../../state/session_provider.dart';
import '../menu/menu_item_detail_screen.dart';
import 'widgets/menu_item_card.dart';
import 'widgets/promo_carousel.dart';

/// Home screen: location header, a rotating "Best Offer" carousel, category
/// pills, search and the café's menu.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final CatalogProvider catalog = context.watch<CatalogProvider>();
    final List<MenuItem> items = catalog.visibleItems;
    final bool searching = catalog.searchQuery.trim().isNotEmpty;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: <Widget>[
            const SliverToBoxAdapter(child: _LocationHeader()),

            if (!searching) ...<Widget>[
              // Best Offer: one rotating strip holding every promo. The former
              // "Special Offers" header and offer tiles are gone — the carousel
              // replaces both rather than sitting above them.
              const SliverToBoxAdapter(
                child: BwSectionHeader(
                  title: 'Best Offer',
                  padding: EdgeInsets.fromLTRB(
                    BwSpacing.gutter,
                    BwSpacing.lg,
                    BwSpacing.gutter,
                    BwSpacing.md,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: PromoCarousel(
                  promos: catalog.promos,
                  onPromoTap: (Promo p) => _showPromoSheet(context, catalog, promo: p),
                ),
              ),
              const SliverToBoxAdapter(child: BwSectionHeader(title: 'Categories')),
              SliverToBoxAdapter(
                child: _CategoryCarousel(catalog: catalog),
              ),

              // Search sits below the categories, directly above the list it
              // filters. Searching hides the whole block above, which also
              // unmounts the carousel and stops its timer.
              const SliverToBoxAdapter(child: _SearchBar()),

              SliverToBoxAdapter(
                child: BwSectionHeader(
                  title: catalog.isOpen ? 'Open Now' : 'Menu',
                  actionLabel: '${catalog.allItems.length} items',
                ),
              ),
            ] else
              const SliverToBoxAdapter(child: _SearchBar()),
              const SliverToBoxAdapter(
                child: BwSectionHeader(
                  title: 'Search results',
                  padding: EdgeInsets.fromLTRB(BwSpacing.gutter, BwSpacing.xl, BwSpacing.gutter, BwSpacing.md),
                ),
              ),

            if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyResults(
                  onClear: () => context.read<CatalogProvider>().clearSearch(),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(BwSpacing.gutter, 0, BwSpacing.gutter, BwSpacing.xxl),
                sliver: SliverList.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: BwSpacing.md),
                  itemBuilder: (BuildContext context, int i) {
                    final MenuItem item = items[i];
                    return MenuItemCard(
                      item: item,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MenuItemDetailScreen(item: item),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  static void _showPromoSheet(BuildContext context, CatalogProvider catalog, {Promo? promo}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: BwColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(BwRadius.card)),
      ),
      builder: (BuildContext ctx) {
        final List<Promo> list = promo != null ? <Promo>[promo] : catalog.promos;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(BwSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: BwColors.border,
                      borderRadius: BorderRadius.circular(BwRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: BwSpacing.xl),
                const Text(
                  'Active promotions',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: BwColors.text),
                ),
                const SizedBox(height: BwSpacing.lg),
                ...list.map(
                  (Promo p) => Padding(
                    padding: const EdgeInsets.only(bottom: BwSpacing.md),
                    child: Container(
                      padding: const EdgeInsets.all(BwSpacing.lg),
                      decoration: BoxDecoration(
                        color: BwColors.bg,
                        borderRadius: BorderRadius.circular(BwRadius.card),
                        border: Border.all(color: BwColors.border),
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  p.title,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: BwColors.text,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(p.subtitle, style: const TextStyle(fontSize: 13, color: BwColors.textMuted)),
                              ],
                            ),
                          ),
                          const SizedBox(width: BwSpacing.md),
                          BwBadge(label: p.code, variant: BwBadgeVariant.outline),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: BwSpacing.sm),
                BwButton(
                  label: 'Got it',
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Location line plus avatar frame.
class _LocationHeader extends StatelessWidget {
  const _LocationHeader();

  @override
  Widget build(BuildContext context) {
    final AppUser user = context.select<SessionProvider, AppUser>((SessionProvider s) => s.user);
    final CatalogProvider catalog = context.watch<CatalogProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(BwSpacing.gutter, BwSpacing.lg, BwSpacing.gutter, BwSpacing.md),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.place_outlined, size: 15, color: BwColors.text),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        catalog.locationLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: BwColors.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: BwColors.text),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: BwColors.inverse,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    // Flexible so long status strings never overflow the row.
                    Expanded(
                      child: Text(
                        catalog.isOpen ? 'Open now · until 10 PM' : 'Closed · opens 7 AM',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: BwColors.textMuted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: BwSpacing.md),
          GestureDetector(
            onTap: () {},
            child: BwAvatar(initials: BwAvatar.initialsOf(user.fullName), size: 42),
          ),
        ],
      ),
    );
  }
}

/// Rounded search field with a light gray border and magnifying glass.
class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    final CatalogProvider catalog = context.watch<CatalogProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(BwSpacing.gutter, 0, BwSpacing.gutter, 0),
      child: TextField(
        onChanged: catalog.setSearch,
        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: BwColors.text),
        decoration: InputDecoration(
          hintText: 'Search coffee, food, drinks...',
          fillColor: BwColors.bg,
          prefixIcon: const Icon(Icons.search_rounded, size: 21),
          suffixIcon: catalog.searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 19),
                  onPressed: catalog.clearSearch,
                ),
          enabledBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(BwRadius.card)),
            borderSide: BorderSide(color: BwColors.border, width: BwStroke.hairline),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(BwRadius.card)),
            borderSide: BorderSide(color: BwColors.borderStrong, width: BwStroke.strong),
          ),
        ),
      ),
    );
  }
}

class _CategoryCarousel extends StatelessWidget {
  const _CategoryCarousel({required this.catalog});

  final CatalogProvider catalog;

  @override
  Widget build(BuildContext context) {
    final List<String> labels = <String>[
      'All',
      ...catalog.categories.map((MenuCategory c) => c.label),
    ];

    final int index = labels.indexOf(catalog.labelForCategory(catalog.selectedCategoryId));

    return BwPillRow(
      items: labels,
      selectedIndex: index < 0 ? 0 : index,
      onSelected: (int i) => catalog.selectCategory(i == 0 ? 'all' : catalog.categories[i - 1].id),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(BwSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.search_off_rounded, size: 56, color: BwColors.disabled),
          const SizedBox(height: BwSpacing.lg),
          const Text(
            'No matches',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: BwColors.text),
          ),
          const SizedBox(height: 6),
          const Text(
            'Nothing on the menu matches that search.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: BwColors.textMuted),
          ),
          const SizedBox(height: BwSpacing.xl),
          BwButton(label: 'Clear search', expand: false, onPressed: onClear),
        ],
      ),
    );
  }
}