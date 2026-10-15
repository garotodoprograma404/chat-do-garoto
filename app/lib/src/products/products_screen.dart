import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/responsive.dart';
import '../scan/barcode_scanner.dart';

import '../settings/settings_menu.dart';
import '../theme/detail_pane.dart';
import '../theme/brand_mark.dart';
import '../theme/components.dart';
import '../theme/motion.dart';
import '../theme/status_colors.dart';
import 'money.dart';
import 'product_form_screen.dart';
import 'product_photos.dart';
import 'product_screen.dart';
import 'products_controller.dart';
import 'products_repository.dart';

/// The regular price to strike next to the one of a running promotion
///; null without one.
int? struckPrice(Product p, DateTime today) {
  if (!p.promoOn(today)) return null;
  final shown = p.activeVariants.isEmpty ? p.variants : p.activeVariants;
  final regular = shown.isEmpty
      ? p.price
      : shown.map((v) => v.price ?? p.price).reduce((a, b) => a < b ? a : b);
  return regular > p.pricesToday(today).first ? regular : null;
}

/// "12 UN", "1,25 KG".
String stockText(int milli, String unit) => '${formatQuantity(milli)} $unit';

/// The Produtos section: list, search, filters and sorting.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({
    super.key,
    required this.repo,
    this.photos,
    this.onOpenSettings,
    this.clock,
  });

  final ProductsRepository repo;

  /// Null where photos cannot be picked (tests).
  final PhotoPicker? photos;
  final VoidCallback? onOpenSettings;
  final DateTime Function()? clock;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  late final _controller = ProductsController(
    repo: widget.repo,
    clock: widget.clock,
  )..load();

  static const _sorts = {
    ProductSort.name: 'Nome (A-Z)',
    ProductSort.newest: 'Mais recentes',
    ProductSort.priceLow: 'Menor preço',
    ProductSort.priceHigh: 'Maior preço',
    ProductSort.stockLow: 'Menor estoque',
  };

  @override
  void dispose() {
    _detailReloader.dispose();
    _controller.dispose();
    super.dispose();
  }

  final _detailReloader = DetailReloader();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _detailReloader.attach(context, _controller.load);
  }

  void _newProduct() => _open(
    ProductFormScreen(
      repo: widget.repo,
      photos: widget.photos,
      clock: widget.clock,
    ),
  );

  Future<void> _open(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    await _controller.load();
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => FilterChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
  );

  /// The price, with the regular one struck when on promotion, and the
  /// most important situation.
  Widget _trailing(Product p, DateTime today) {
    final prices = p.pricesToday(today);
    final price = prices.length > 1
        ? 'a partir de ${formatMoney(prices.first)}'
        : formatMoney(prices.first);
    final expires = p.expiresIn(today);
    final pill = !p.active
        ? const StatusPill('Inativo', Situation.off)
        : expires != null && expires < 0
        ? const StatusPill('Vencido', Situation.overdue)
        : p.outOfStock
        ? const StatusPill('Sem estoque', Situation.overdue)
        : p.expiringSoon(today)
        ? StatusPill(expiryLabel(p, today)!, Situation.open)
        : p.lowStock
        ? const StatusPill('Estoque baixo', Situation.open)
        : p.promoOn(today)
        ? const StatusPill('Promoção', Situation.ok)
        : null;
    final struck = struckPrice(p, today);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // The regular price struck over the promotion's.
        if (struck != null)
          Text(
            formatMoney(struck),
            style: Theme.of(context).textTheme.bodySmall!.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              decoration: TextDecoration.lineThrough,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        Text(price, style: tabular),
        if (pill != null) ...[const SizedBox(height: 2), pill],
      ],
    );
  }

  /// Reads a code: the product's page, or "Cadastrar
  /// produto com este código".
  Future<void> _scan() async {
    final code = await barcodeScanner?.scanOne(context);
    if (code == null || !mounted) return;
    final found = productByCode(await widget.repo.list(), code);
    if (!mounted) return;
    if (found != null) {
      await _open(
        ProductScreen(
          repo: widget.repo,
          id: found.product.id!,
          photos: widget.photos,
          clock: widget.clock,
        ),
      );
      return;
    }
    final create = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Código não cadastrado'),
        content: Text('Nenhum produto tem o código $code.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cadastrar produto com este código'),
          ),
        ],
      ),
    );
    if (create != true || !mounted) return;
    await _open(
      ProductFormScreen(
        repo: widget.repo,
        photos: widget.photos,
        clock: widget.clock,
        barcode: code,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const SemicolonText('Produtos'),
        actions: [
          if (barcodeScanner != null)
            IconButton(
              tooltip: 'Ler código de barras',
              icon: const Icon(Symbols.barcode_scanner_rounded),
              onPressed: _scan,
            ),
          PopupMenuButton<ProductSort>(
            tooltip: 'Ordenar',
            icon: const Icon(Symbols.sort_rounded),
            onSelected: _controller.sortBy,
            itemBuilder: (context) => [
              for (final MapEntry(:key, :value) in _sorts.entries)
                CheckedPopupMenuItem(
                  value: key,
                  checked: _controller.sort == key,
                  child: Text(value),
                ),
            ],
          ),
          if (widget.onOpenSettings case final open?)
            SettingsMenuButton(onOpenSettings: open),
        ],
      ),
      floatingActionButton: actionBar(context)
          ? null
          : FloatingActionButton.extended(
              heroTag: 'new-product',
              onPressed: _newProduct,
              icon: const Icon(Symbols.add_box_rounded),
              label: const Text('Novo produto'),
            ),
      bottomNavigationBar: actionBar(context)
          ? ListActionBar(
              children: [
                FilledButton.icon(
                  onPressed: _newProduct,
                  icon: const Icon(Symbols.add_box_rounded),
                  label: const Text('Novo produto'),
                ),
              ],
            )
          : null,
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final c = _controller;
          if (c.all.isEmpty) {
            return const EmptyState(
              title: 'Nenhum produto ainda.',
              message:
                  'Cadastre o primeiro em "Novo produto": só nome e preço são '
                  'obrigatórios.',
            );
          }
          final products = c.products;
          final today = c.today;
          final t = Theme.of(context).textTheme;
          final muted = Theme.of(context).colorScheme.onSurfaceVariant;
          return Column(
            children: [
              AppSearchField(hint: 'Buscar produtos', onChanged: c.search),
              FilterBar(
                children: [
                  _chip('Estoque baixo', c.lowStock, c.toggleLowStock),
                  _chip('Sem estoque', c.outOfStock, c.toggleOutOfStock),
                  _chip('Em promoção', c.onPromo, c.togglePromo),
                  _chip('Vencendo', c.expiring, c.toggleExpiring),
                  _chip('Inativos', c.showInactive, c.toggleInactive),
                  for (final category in c.allCategories)
                    _chip(
                      category,
                      c.categories.contains(category),
                      () => c.toggleCategory(category),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${products.length} de ${c.counted.length}',
                    style: t.bodySmall!.copyWith(color: muted),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.only(
                    bottom: listBottomPadding(context, fab: true),
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, i) {
                    final p = products[i];
                    return OpenTile(
                      selectKey: 'product:${p.id}',
                      onClosed: _controller.load,
                      page: (_) => ProductScreen(
                        repo: widget.repo,
                        id: p.id!,
                        photos: widget.photos,
                        clock: widget.clock,
                      ),
                      row: (open) => AppListTile(
                        selected: DetailHost.isSelected(
                          context,
                          'product:${p.id}',
                        ),
                        leading: ProductAvatar(product: p, repo: widget.repo),
                        title: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            if (p.isService)
                              'Serviço'
                            else
                              stockText(p.stock, p.unit),
                            if (p.category.isNotEmpty) p.category,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: _trailing(p, today),
                        onTap: open,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
