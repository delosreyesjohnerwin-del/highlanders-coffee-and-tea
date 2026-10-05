import 'package:flutter/material.dart';

/// Menu category — "Coffee", "Brews", "Pastries", "Meals".
@immutable
class MenuCategory {
  const MenuCategory({
    required this.id,
    required this.label,
    required this.sortOrder,
    this.icon = Icons.local_cafe_outlined,
  });

  final String id;
  final String label;
  final int sortOrder;
  final IconData icon;
}

/// Stock health, derived from [MenuItem.stock] against its reorder level.
enum StockStatus { inStock, lowStock, outOfStock }

extension StockStatusX on StockStatus {
  String get label => switch (this) {
    StockStatus.inStock => 'In Stock',
    StockStatus.lowStock => 'Low Stock',
    StockStatus.outOfStock => 'Out of Stock',
  };

  /// Monochrome icons rather than colour: "low" reads as a warning glyph, and
  /// "out" as a missing one.
  IconData get icon => switch (this) {
    StockStatus.inStock => Icons.check_circle_outline_rounded,
    StockStatus.lowStock => Icons.error_outline_rounded,
    StockStatus.outOfStock => Icons.remove_circle_outline_rounded,
  };
}

/// A single sellable item.
@immutable
class MenuItem {
  const MenuItem({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.price,
    this.description = '',
    this.imageUrl,
    this.isAvailable = true,
    this.isBestseller = false,
    this.prepMinutes = 5,
    this.sortOrder = 0,
    this.stock = 0,
    this.reorderLevel = 10,
  });

  final String id;
  final String categoryId;
  final String name;
  final num price;
  final String description;
  final String? imageUrl;
  final bool isAvailable;
  final bool isBestseller;
  final int prepMinutes;
  final int sortOrder;

  /// Units on hand. `0` means sold out.
  final int stock;

  /// At or below this count the item is flagged [StockStatus.lowStock].
  final int reorderLevel;

  StockStatus get status {
    if (stock <= 0) return StockStatus.outOfStock;
    if (stock <= reorderLevel) return StockStatus.lowStock;
    return StockStatus.inStock;
  }

  /// Whether a customer can actually order this right now.
  ///
  /// Deliberately *not* the same as [isAvailable]: an admin can keep an item
  /// listed while it is sold out, and the shop shows a "Sold out" note instead
  /// of silently hiding a bestseller.
  bool get isOrderable => isAvailable && stock > 0;

  num get stockValue => price * stock;

  MenuItem copyWith({
    bool? isAvailable,
    num? price,
    int? stock,
    int? reorderLevel,
    String? name,
    String? description,
    String? categoryId,
  }) =>
      MenuItem(
        id: id,
        categoryId: categoryId ?? this.categoryId,
        name: name ?? this.name,
        price: price ?? this.price,
        description: description ?? this.description,
        imageUrl: imageUrl,
        isAvailable: isAvailable ?? this.isAvailable,
        isBestseller: isBestseller,
        prepMinutes: prepMinutes,
        sortOrder: sortOrder,
        stock: stock ?? this.stock,
        reorderLevel: reorderLevel ?? this.reorderLevel,
      );
}

/// Promotional banner content, editable from the admin panel.
@immutable
class Promo {
  const Promo({
    required this.code,
    required this.title,
    required this.subtitle,
    this.badge,
    this.ctaLabel,
    this.discountPercent,
    this.buyXGetY,
    this.active = true,
  });

  final String code;
  final String title;
  final String subtitle;
  final String? badge;
  final String? ctaLabel;
  final int? discountPercent;

  /// Buy-one-get-one, expressed as a human label such as "Buy 1 Get 1".
  final String? buyXGetY;
  final bool active;
}