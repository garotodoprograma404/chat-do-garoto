import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../home/crm_scope.dart';
import '../sales/sale_form_screen.dart';
import '../sales/sales_screen.dart' show SaleContext;
import '../theme/components.dart';
import '../theme/status_colors.dart';
import 'money.dart';
import 'pricing.dart';
import 'product_form_screen.dart';
import 'product_photos.dart';
import 'products_repository.dart';
import 'products_screen.dart';
import 'stock_screens.dart';

/// The situations of a product, as pills: inactive, out of
/// stock or low, expired or expiring, on promotion.
List<StatusPill> productPills(Product p, DateTime today) {
  final expires = p.expiresIn(today);
  final until = p.promoUntil;
  return [
    if (!p.active) const StatusPill('Inativo', Situation.off),
    if (p.outOfStock)
      const StatusPill('Sem estoque', Situation.overdue)
    else if (p.lowStock)
      const StatusPill('Estoque baixo', Situation.open),
    if (expires != null && expires < 0)
      const StatusPill('Vencido', Situation.overdue)
    else if (p.expiringSoon(today))
      StatusPill(expiryLabel(p, today)!, Situation.open),
    if (p.promoOn(today))
      StatusPill(
        until == null ? 'Promoção' : 'Promoção até ${formatDay(until)}',
        Situation.ok,
      ),
  ];
}

/// One product, like the client's page: who it is and the
/// price at a glance, the situations, the actions, the stock of each
/// variation, and the rest in "Detalhes".
class ProductScreen extends StatefulWidget {
  const ProductScreen({
    super.key,
    required this.repo,
    required this.id,
    this.photos,
    this.clock,
  });

  final ProductsRepository repo;
  final int id;
  final PhotoPicker? photos;
  final DateTime Function()? clock;

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  Product? _product;
  bool _loaded = false;

  DateTime get _today => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final product = await widget.repo.byId(widget.id);
    if (!mounted) return;
    setState(() {
      _product = product;
      _loaded = true;
    });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<Object>(builder: (_) => screen));
    await _load();
  }

  /// A sale is possible where the sales are (the app with app.db open).
  SaleContext? get _saleCtx {
    final scope = CrmScope.maybeOf(context);
    final sales = scope?.sales;
    if (sales == null) return null;
    return SaleContext(
      sales: sales,
      products: widget.repo,
      clients: scope?.clients,
      clock: widget.clock,
    );
  }

  /// "Nova venda com este produto": the sale with the product, after
  /// choosing the variation when there is more than one.
  Future<void> _sell(Product p, SaleContext ctx) async {
    final variants = p.activeVariants;
    var variant = variants.length == 1 ? variants.single : null;
    if (variant == null && variants.isNotEmpty) {
      variant = await showModalBottomSheet<Variant>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Qual variação?',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final v in variants)
                AppListTile(
                  title: Text(v.label),
                  subtitle: Text(
                    '${formatMoney(p.priceOf(v, _today))} · '
                    '${stockText(v.stock, p.unit)}',
                  ),
                  onTap: () => Navigator.pop(context, v),
                ),
            ],
          ),
        ),
      );
    }
    if (variant == null || !mounted) return;
    await _open(SaleFormScreen(ctx: ctx, item: (p, variant)));
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar produto?'),
        content: const Text(
          'O produto, as variações, o histórico de estoque e as fotos serão '
          'apagados de vez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repo.delete(widget.id);
    } on ProductHasSales {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Este produto já foi vendido: não pode ser apagado. Desative-o '
              'em Editar → Ativo.',
            ),
          ),
        );
      }
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _showPhoto(int id) async {
    final bytes = await widget.repo.photo(id);
    if (bytes != null && mounted) openPhoto(context, bytes);
  }

  /// "Custo R$ 7,00 · lucro R$ 5,00 · margem 41,7%"; null without a cost.
  String? _margin(Product p, Variant v) {
    if (v.cost <= 0) return null;
    final price = p.priceOf(v, _today);
    final margin = marginPercent(price, v.cost);
    return [
      'Custo ${formatMoney(v.cost)}',
      'lucro ${formatMoney(price - v.cost)}',
      if (margin != null) 'margem ${formatPercent(margin)}',
    ].join(' · ');
  }

  /// The price, cost and margin of each variation are the same.
  bool _uniform(Product p) {
    final v = p.activeVariants.isEmpty ? p.variants : p.activeVariants;
    return v.every((x) => x.price == v.first.price && x.cost == v.first.cost);
  }

  Widget _header(Product p, DateTime today) {
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final prices = p.pricesToday(today);
    final struck = struckPrice(p, today);
    final pills = productPills(p, today);
    final margin = p.variants.isNotEmpty && _uniform(p)
        ? _margin(p, p.activeVariants.firstOrNull ?? p.variants.first)
        : null;
    final photo = p.photoIds.firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: photo == null ? null : () => _showPhoto(photo),
                child: ProductAvatar(product: p, repo: widget.repo, size: 88),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: t.headlineSmall),
                    if ([p.category, p.brand].where((s) => s.isNotEmpty)
                        case final about when about.isNotEmpty)
                      Text(
                        about.join(' · '),
                        style: t.bodyMedium!.copyWith(color: muted),
                      ),
                    if (p.isService)
                      Text(
                        'Serviço',
                        style: t.bodyMedium!.copyWith(color: muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (prices.length > 1)
            Text('a partir de', style: t.bodyMedium!.copyWith(color: muted)),
          // Wraps under the price with large text.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              MoneyText(formatMoney(prices.first)),
              if (struck != null)
                Text(
                  formatMoney(struck),
                  style: t.titleMedium!.copyWith(
                    color: muted,
                    decoration: TextDecoration.lineThrough,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          if (margin != null)
            Text(margin, style: t.bodyMedium!.copyWith(color: muted)),
          if (pills.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: pills),
          ],
          if (p.photoIds.length > 1) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 64,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final id in p.photoIds)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ProductThumb(
                          key: ValueKey(id),
                          repo: widget.repo,
                          photoId: id,
                          size: 64,
                          onTap: () => _showPhoto(id),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Nova venda com este produto and Movimentar estoque.
  Widget _actions(Product p) {
    final ctx = _saleCtx;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (ctx != null && p.active)
            FilledButton.icon(
              onPressed: () => _sell(p, ctx),
              icon: const Icon(Symbols.add_shopping_cart_rounded),
              label: const Text('Nova venda com este produto'),
            ),
          if (!p.isService)
            FilledButton.tonalIcon(
              onPressed: () =>
                  _open(StockMoveScreen(repo: widget.repo, product: p)),
              icon: const Icon(Symbols.inventory_2_rounded),
              label: const Text('Movimentar estoque'),
            ),
        ],
      ),
    );
  }

  /// The stock: the total and the minimum, and one row per variation with
  /// its quantity and situation.
  List<Widget> _stock(Product p, DateTime today) {
    final t = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final uniform = _uniform(p);
    Widget quantity(int stock) => Text(
      stockText(stock, p.unit),
      style: tabular.copyWith(color: stock < 0 ? colors.error : null),
    );
    return [
      SectionHeader(
        'Estoque',
        trailing: DefaultTextStyle.merge(
          style: t.titleSmall,
          child: quantity(p.stock),
        ),
      ),
      if (p.stock < 0 || p.minStock > 0)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            [
              if (p.stock < 0) 'Estoque negativo',
              if (p.minStock > 0) 'Mínimo: ${stockText(p.minStock, p.unit)}',
            ].join(' · '),
            style: t.bodyMedium!.copyWith(
              color: p.stock < 0 ? colors.error : colors.onSurfaceVariant,
            ),
          ),
        ),
      if (p.hasVariants)
        for (final v in p.variants)
          AppListTile(
            title: Text(v.active ? v.label : '${v.label} (desativada)'),
            subtitle: switch ([
              if (!uniform) formatMoney(p.priceOf(v, today)),
              if (!uniform) ?_margin(p, v),
              if (v.sku case final sku? when sku.isNotEmpty) 'cód. $sku',
            ]) {
              final parts when parts.isNotEmpty => Text(parts.join(' · ')),
              _ => null,
            },
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                quantity(v.stock),
                if (!v.active)
                  const StatusPill('Desativada', Situation.off)
                else if (v.stock <= 0)
                  const StatusPill('Sem estoque', Situation.overdue)
                else if (p.minStock > 0 && v.stock <= p.minStock)
                  const StatusPill('Estoque baixo', Situation.open),
              ],
            ),
          ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () =>
                _open(StockHistoryScreen(repo: widget.repo, product: p)),
            icon: const Icon(Symbols.history_rounded),
            label: const Text('Ver histórico do estoque'),
          ),
        ),
      ),
    ];
  }

  /// The rest, only what is filled in.
  List<Widget> _details(Product p, DateTime today) {
    final promo = p.promoPrice;
    final details = <(String, String)>[
      ('Código interno (SKU)', p.sku ?? ''),
      ('Código de barras', p.barcode ?? ''),
      ('Unidade', p.unit),
      if (p.expiresOn case final day? when day.isNotEmpty)
        ('Validade', '${formatDay(day)} · ${expiryLabel(p, today)}'),
      if (promo != null)
        (
          'Promoção',
          [
            formatMoney(promo),
            if (p.promoUntil case final until?) 'até ${formatDay(until)}',
            if (!p.promoOn(today)) 'encerrada',
          ].join(' · '),
        ),
      for (final tier in p.tiers)
        (
          'Atacado: a partir de ${stockText(tier.minQty, p.unit)}',
          formatMoney(tier.price),
        ),
      ('Fornecedor', p.supplier),
      ('Descrição', p.description),
    ];
    return [
      const SectionHeader('Detalhes'),
      for (final (label, value) in details)
        if (value.isNotEmpty)
          ListTile(dense: true, title: Text(label), subtitle: Text(value)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = _product;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: _loaded
              ? const Text('Produto não encontrado.')
              : const CircularProgressIndicator(),
        ),
      );
    }
    final today = _today;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Symbols.edit_rounded),
            onPressed: () => _open(
              ProductFormScreen(
                repo: widget.repo,
                photos: widget.photos,
                initial: p,
                clock: widget.clock,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Apagar produto',
            icon: const Icon(Symbols.delete_rounded),
            onPressed: _delete,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          // Content drawn behind the system navigation bar must scroll
          // above it (edge to edge on Android).
          final bottom = 16 + MediaQuery.paddingOf(context).bottom;
          // A wide pane: stock beside the details.
          if (box.maxWidth >= 760 && !p.isService) {
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 16,
                children: [
                  AppCard(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [_header(p, today), _actions(p)],
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 16,
                    children: [
                      Expanded(
                        child: AppCard(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _stock(p, today),
                          ),
                        ),
                      ),
                      Expanded(
                        child: AppCard(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _details(p, today),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }
          return ListView(
            padding: EdgeInsets.only(bottom: bottom),
            children: [
              _header(p, today),
              _actions(p),
              const Divider(height: 32),
              if (!p.isService) ..._stock(p, today),
              ..._details(p, today),
            ],
          );
        },
      ),
    );
  }
}
