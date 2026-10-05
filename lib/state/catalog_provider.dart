import 'package:flutter/material.dart';

import '../data/mock/mock_data.dart';
import '../data/models/coverage.dart';
import '../data/models/menu.dart';

/// Menu, categories, promos and café trading status.
///
/// Backed by [MockData] until Firebase is wired up. Every value the admin
/// panel edits will eventually flow through here.
class CatalogProvider extends ChangeNotifier {
  CatalogProvider();

  List<MenuCategory> _categories = List<MenuCategory>.from(MockData.categories);
  List<MenuItem> _items = List<MenuItem>.from(MockData.menu);
  final List<Promo> _promos = List<Promo>.from(MockData.promos);

  String _searchQuery = '';
  String _selectedCategoryId = 'all';
  bool _isOpen = true;

  DeliveryPricing _pricing = const DeliveryPricing(freeOver: 500);

  List<MenuCategory> get categories => _categories;
  List<Promo> get promos => _promos;
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

  List<Promo> get offerTiles => _promos.where((Promo p) => p.code != 'DAMPOTIST').toList(growable: false);

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

  void toggleOpen() {
    _isOpen = !_isOpen;
    notifyListeners();
  }

  void setPricing(DeliveryPricing pricing) {
    _pricing = pricing;
    notifyListeners();
  }

  // --- admin actions -----------------------------------------------------

  void upsertItem(MenuItem item) {
    final int i = _items.indexWhere((MenuItem e) => e.id == item.id);
    if (i == -1) {
      _items = <MenuItem>[..._items, item];
    } else {
      _items = <MenuItem>[..._items]..[i] = item;
    }
    notifyListeners();
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
  }
}