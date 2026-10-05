import 'dart:async';

import 'package:flutter/material.dart';

import '../data/firestore/firestore_errors.dart';
import '../data/firestore/memory_shop_repository.dart';
import '../data/firestore/shop_repository.dart';
import '../data/mock/mock_data.dart';
import '../data/models/coverage.dart';
import '../data/models/menu.dart';

/// Menu, categories, promos and café trading status.
///
/// Seeded from [MockData] so the app is usable with no backend, then replaced by
/// whatever a [ShopRepository] returns as soon as one is bound. Both happen: the
/// seed is the first paint, the repository is the truth a moment later. That
/// avoids an empty shop on a cold start, at the cost of a brief window where the
/// menu is the mock one — the tradeoff is deliberate, because "no items" reads as
/// "we are closed" and "closed" loses a sale.
class CatalogProvider extends ChangeNotifier {
  CatalogProvider({ShopRepository? repository})
      : _repository = repository ?? MemoryShopRepository() {
    _categories = List<MenuCategory>.from(MockData.categories);
    _items = List<MenuItem>.from(MockData.menu);
    _promos = List<Promo>.from(MockData.promos);
  }

  final ShopRepository _repository;
  StreamSubscription<CatalogSnapshot>? _subscription;
  bool _bound = false;

  List<MenuCategory> _categories = <MenuCategory>[];
  List<MenuItem> _items = <MenuItem>[];
  List<Promo> _promos = <Promo>[];

  String _searchQuery = '';
  String _selectedCategoryId = 'all';
  bool _isOpen = true;

  DeliveryPricing _pricing = const DeliveryPricing(freeOver: 500);

  /// Most recent failed write, for the UI to surface. Cleared by
  /// [consumeFailure].
  WriteFailure? _failure;

  /// True once a live backend has answered. False means the menu on screen is
  /// the seed and any edit is memory-only.
  bool get isLive => _repository.isLive;

  bool _loaded = false;
  bool get hasLoaded => _loaded;

  /// Subscribes to the repository. Idempotent, so a rebuild can call it freely.
  void bind() {
    if (_bound) return;
    _bound = true;

    _subscription = _repository.watchCatalog().listen(
      (CatalogSnapshot snapshot) {
        // The menu lists are only replaced when the snapshot actually has
        // content. A brand-new project returns three empty collections, and
        // blowing away the seed on that first emission would show a café with no
        // menu — which reads as "we are closed", not "not configured yet".
        //
        // Settings are applied unconditionally, including on an empty snapshot.
        // The admin closing the shop has to reach the customer app even in the
        // window before the menu has loaded, and that is the one case where
        // applying from an empty snapshot matters.
        if (!snapshot.isEmpty) {
          _categories = snapshot.categories;
          _items = snapshot.items;
          _promos = snapshot.promos;
        }

        _isOpen = snapshot.isOpen;
        _pricing = snapshot.pricing;
        _loaded = true;
        notifyListeners();
      },
      onError: (Object error) {
        _failure = describeFailure('watch the menu', error);
        logWriteFailure(_failure!);
        notifyListeners();
      },
    );
  }

  /// The failure to show, and clears it. One-shot so a toast does not reappear
  /// on the next rebuild.
  WriteFailure? consumeFailure() {
    final WriteFailure? failure = _failure;
    _failure = null;
    return failure;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  List<MenuCategory> get categories => _categories;

  /// Every promo, live or paused. The admin panel's job is to show all of them so
  /// a paused one can be brought back.
  List<Promo> get allPromos => _promos;

  /// Promos a customer should see, in carousel order.
  ///
  /// Filtered on read rather than on write so pausing a promo takes effect for an
  /// already-open customer app immediately, via the same catalog listener that
  /// carries the menu. Hiding it in the admin panel instead would leave the
  /// customer's screen showing an offer the owner believes they have taken down.
  List<Promo> get promos => _promos.where((Promo p) => p.active).toList(growable: false);
  bool get isOpen => _isOpen;
  String get searchQuery => _searchQuery;
  String get selectedCategoryId => _selectedCategoryId;
  DeliveryPricing get pricing => _pricing;
  String get cafeName => 'Highlanders Coffee & Tea';
  String get locationLabel => LumbanCoverage.municipality;

  List<MenuItem> get allItems => _items;

  Promo? get heroPromo {
    for (final Promo p in _promos) {
      if (p.code == 'DAMPOTIST') return p;
    }
    return _promos.isEmpty ? null : _promos.first;
  }

  

  MenuItem? itemById(String id) {
    for (final MenuItem i in _items) {
      if (i.id == id) return i;
    }
    return null;
  }

  String labelForCategory(String id) {
    if (id == 'all') return 'All';
    for (final MenuCategory c in _categories) {
      if (c.id == id) return c.label;
    }
    return id;
  }

  /// Items filtered by the active category and the search query.
  List<MenuItem> get visibleItems {
    final String q = _searchQuery.trim().toLowerCase();

    return _items.where((MenuItem item) {
      if (!item.isAvailable) return false;
      // Sold-out items stay listed: the shop shows a note rather than hiding a
      // bestseller the moment its stock hits zero.
      if (_selectedCategoryId != 'all' && item.categoryId != _selectedCategoryId) return false;
      if (q.isEmpty) return true;
      return item.name.toLowerCase().contains(q) ||
          item.description.toLowerCase().contains(q) ||
          labelForCategory(item.categoryId).toLowerCase().contains(q);
    }).toList(growable: false);
  }

  List<MenuItem> get bestsellers =>
      _items.where((MenuItem i) => i.isBestseller && i.isOrderable).toList(growable: false);

  void selectCategory(String id) {
    if (_selectedCategoryId == id) return;
    _selectedCategoryId = id;
    notifyListeners();
  }

  void setSearch(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    notifyListeners();
  }

  void clearSearch() => setSearch('');

  /// Flips trading state.
  ///
  /// Not a local-only toggle: the open flag lives in the shop settings document
  /// because the customer app reads it too. Kept here as the customer-facing
  /// entry point, delegating the write.
  Future<void> toggleOpen() async {
    _isOpen = !_isOpen;
    notifyListeners();

    final WriteFailure? failure = await _repository.saveSettings(
      (await _repository.loadSettings()).copyWith(isOpen: _isOpen),
    );
    _recordFailure(failure);
  }

  void setPricing(DeliveryPricing pricing) {
    _pricing = pricing;
    notifyListeners();
  }

  void _recordFailure(WriteFailure? failure) {
    if (failure == null) return;
    _failure = failure;
    logWriteFailure(failure);
    notifyListeners();
  }

  // --- admin actions -----------------------------------------------------
  //
  // Every one of these is optimistic: local state changes and the UI repaints
  // immediately, then the write goes out. An admin tapping a toggle in a
  // basement with no signal must see the toggle move. The cost is that a failed
  // write leaves the UI briefly lying, which is why each failure is recorded
  // rather than dropped and the caller can surface it.

  void upsertItem(MenuItem item) {
    final int i = _items.indexWhere((MenuItem e) => e.id == item.id);
    if (i == -1) {
      _items = <MenuItem>[..._items, item];
    } else {
      _items = <MenuItem>[..._items]..[i] = item;
    }
    notifyListeners();
    unawaited(_repository.saveMenuItem(item).then(_recordFailure));
  }

  void setItemAvailability(String id, bool available) {
    final MenuItem? item = itemById(id);
    if (item == null) return;
    upsertItem(item.copyWith(isAvailable: available));
  }

  /// Sets the on-hand count. Zero means sold out rather than hidden, so a
  /// bestseller does not silently vanish from the shop when it runs out.
  void setStock(String id, int stock) {
    final MenuItem? item = itemById(id);
    if (item == null) return;
    upsertItem(item.copyWith(stock: stock < 0 ? 0 : stock));
  }

  void removeItem(String id) {
    final int before = _items.length;
    _items = _items.where((MenuItem e) => e.id != id).toList(growable: false);
    if (_items.length == before) return;
    notifyListeners();
    unawaited(_repository.deleteMenuItem(id).then(_recordFailure));
  }

  void updatePrice(String id, num price) {
    final MenuItem? item = itemById(id);
    if (item == null) return;
    upsertItem(item.copyWith(price: price));
  }

  void upsertCategory(MenuCategory category) {
    final int i = _categories.indexWhere((MenuCategory e) => e.id == category.id);
    if (i == -1) {
      _categories = <MenuCategory>[..._categories, category];
    } else {
      _categories = <MenuCategory>[..._categories]..[i] = category;
    }
    notifyListeners();
    unawaited(_repository.saveCategory(category).then(_recordFailure));
  }

  void upsertPromo(Promo promo) {
    _promos = <Promo>[
      for (final Promo p in _promos)
        if (p.code == promo.code) promo else p,
      if (!_promos.any((Promo p) => p.code == promo.code)) promo,
    ];
    notifyListeners();
    unawaited(_repository.savePromo(promo).then(_recordFailure));
  }

  /// Deletes a promo outright.
  ///
  /// Distinct from [upsertPromo] with `active: false`: an inactive promo stays in
  /// Firestore and keeps coming back on every catalog read, so "turn it off"
  /// survives a restart while "remove it" does not. Both exist because a café
  /// ends a promotion and then wants it gone from the list rather than hidden.
  ///
  /// The promotion code doubles as the Firestore document id, so this deletes by
  /// code rather than by a separate id field.
  void removePromo(String code) {
    final int before = _promos.length;
    _promos = _promos.where((Promo p) => p.code != code).toList(growable: false);
    if (_promos.length == before) return;
    notifyListeners();
    unawaited(_repository.deletePromo(code).then(_recordFailure));
  }
}