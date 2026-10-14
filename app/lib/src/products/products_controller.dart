import 'package:flutter/foundation.dart';

import '../search/text.dart';
import 'products_repository.dart';

/// How the product list is ordered.
enum ProductSort { name, newest, priceLow, priceHigh, stockLow }

/// The product list with search, filters and sorting.
class ProductsController extends ChangeNotifier {
  ProductsController({required this._repo, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final ProductsRepository _repo;
  final DateTime Function() _clock;

  List<Product> all = const [];
  String query = '';
  final Set<String> categories = {};
  bool lowStock = false;
  bool outOfStock = false;
  bool onPromo = false;

  /// "Vencendo".
  bool expiring = false;
  bool showInactive = false;
  ProductSort sort = ProductSort.name;

  DateTime get today => _clock();

  Future<void> load() async {
    final loaded = await _repo.list();
    // The screen may be gone while the database answered (section changed).
    if (_disposed) return;
    all = loaded;
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Every category in use, in order.
  List<String> get allCategories => {
    for (final p in all)
      if (p.category.isNotEmpty) p.category,
  }.toList()..sort((a, b) => fold(a).compareTo(fold(b)));

  /// The products the list counts: active ones, or all with "inativos".
  List<Product> get counted => [
    for (final p in all)
      if (showInactive || p.active) p,
  ];

  /// The products shown: search and filters, in the chosen order.
  List<Product> get products {
    final day = today;
    final shown = [
      for (final p in counted)
        if (_matches(p) &&
            (categories.isEmpty || categories.contains(p.category)) &&
            // The stock filters add up: low or out of stock.
            (!(lowStock || outOfStock) ||
                (lowStock && p.lowStock) ||
                (outOfStock && p.outOfStock)) &&
            (!onPromo || p.promoOn(day)) &&
            (!expiring || p.expiringSoon(day)))
          p,
    ];
    int byName(Product a, Product b) => fold(a.name).compareTo(fold(b.name));
    int price(Product p) => p.pricesToday(day).first;
    shown.sort((a, b) {
      final order = switch (sort) {
        ProductSort.name => 0,
        ProductSort.newest => (b.createdAt ?? DateTime(0)).compareTo(
          a.createdAt ?? DateTime(0),
        ),
        ProductSort.priceLow => price(a).compareTo(price(b)),
        ProductSort.priceHigh => price(b).compareTo(price(a)),
        // Services have no stock: they go last.
        ProductSort.stockLow => switch ((a.isService, b.isService)) {
          (true, true) => 0,
          (true, false) => 1,
          (false, true) => -1,
          _ => a.stock.compareTo(b.stock),
        },
      };
      return order != 0 ? order : byName(a, b);
    });
    return shown;
  }

  bool _matches(Product p) {
    if (query.trim().isEmpty) return true;
    final text = [
      p.name,
      p.sku ?? '',
      p.barcode ?? '',
      p.category,
      p.brand,
      p.supplier,
      p.description,
      for (final v in p.variants) ...[
        ...v.options,
        v.sku ?? '',
        v.barcode ?? '',
      ],
    ].join(' ');
    return textMatches(text, query);
  }

  void search(String text) {
    query = text;
    notifyListeners();
  }

  void toggleCategory(String category) {
    if (!categories.remove(category)) categories.add(category);
    notifyListeners();
  }

  void toggleLowStock() {
    lowStock = !lowStock;
    notifyListeners();
  }

  void toggleOutOfStock() {
    outOfStock = !outOfStock;
    notifyListeners();
  }

  void togglePromo() {
    onPromo = !onPromo;
    notifyListeners();
  }

  void toggleExpiring() {
    expiring = !expiring;
    notifyListeners();
  }

  void toggleInactive() {
    showInactive = !showInactive;
    notifyListeners();
  }

  void sortBy(ProductSort value) {
    sort = value;
    notifyListeners();
  }
}
