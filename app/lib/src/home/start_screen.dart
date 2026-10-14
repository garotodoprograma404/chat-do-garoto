import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../chats/chat_screen.dart';
import '../chats/chats_screen.dart' show chatTitle;
import '../clients/client_form_screen.dart';
import '../clients/client_screen.dart';
import '../clients/clients_repository.dart';
import '../core_bridge/core_bridge.dart';
import '../products/money.dart';
import '../products/pricing.dart' show isoDay;
import '../products/product_form_screen.dart';
import '../products/product_photos.dart';
import '../products/product_screen.dart';
import '../products/products_repository.dart';
import '../sales/sale_form_screen.dart';
import '../sales/sale_math.dart';
import '../sales/sale_screen.dart';
import '../sales/sales_repository.dart';
import '../sales/sales_screen.dart';
import '../theme/brand_mark.dart';
import '../theme/app_theme.dart';
import '../theme/components.dart';
import '../theme/status_colors.dart';
import 'start_controller.dart';

const _months = [
  'Janeiro',
  'Fevereiro',
  'Março',
  'Abril',
  'Maio',
  'Junho',
  'Julho',
  'Agosto',
  'Setembro',
  'Outubro',
  'Novembro',
  'Dezembro',
];

/// "Outubro de 2026".
String monthLabel(DateTime m) => '${_months[m.month - 1]} de ${m.year}';

/// "Hoje", "Amanhã", "Em 3 dias".
String inDaysLabel(int d) => switch (d) {
  0 => 'Hoje',
  1 => 'Amanhã',
  _ => 'Em $d dias',
};

/// "agora", "há 5 min", "há 2 h", "há 3 dias".
String waitingLabel(DateTime since, DateTime now) {
  final d = now.difference(since);
  if (d.inMinutes < 1) return 'agora';
  if (d.inHours < 1) return 'há ${d.inMinutes} min';
  if (d.inDays < 1) return 'há ${d.inHours} h';
  return d.inDays == 1 ? 'há 1 dia' : 'há ${d.inDays} dias';
}

/// Início: what to do today, shortcuts and the month.
class StartScreen extends StatefulWidget {
  const StartScreen({
    super.key,
    required this.clients,
    required this.products,
    required this.sales,
    this.photos,
    this.bridge,
    this.onOpenSettings,
    this.onOpenWaiting,
    this.clock,
  });

  /// "Ver todas": Conversas with "Sem resposta".
  final VoidCallback? onOpenWaiting;

  final ClientsRepository? clients;
  final ProductsRepository? products;
  final SalesRepository? sales;
  final PhotoPicker? photos;
  final CoreBridge? bridge;
  final VoidCallback? onOpenSettings;
  final DateTime Function()? clock;

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  late final _c = StartController(
    clients: widget.clients,
    products: widget.products,
    sales: widget.sales,
    bridge: widget.bridge,
    clock: widget.clock,
  )..load();

  StreamSubscription<CoreEvent>? _events;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // New messages change who waits for a reply; a burst
    // reloads once.
    _events = widget.bridge?.events.listen((event) {
      if (event.type case 'wa_message' || 'wa_history' || 'wa_deleted') {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 500), _c.reloadWaiting);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _events?.cancel();
    _c.dispose();
    super.dispose();
  }

  SaleContext? get _saleCtx => switch (widget.sales) {
    final s? => SaleContext(
      sales: s,
      products: widget.products,
      clients: widget.clients,
      bridge: widget.bridge,
      clock: widget.clock,
    ),
    null => null,
  };

  Future<void> _open(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    await _c.load();
  }

  void _newSale() {
    if (_saleCtx case final ctx? when ctx.products != null) {
      _open(SaleFormScreen(ctx: ctx));
    }
  }

  void _newClient() {
    if (widget.clients case final repo?) _open(ClientFormScreen(repo: repo));
  }

  void _newProduct() {
    if (widget.products case final repo?) {
      _open(
        ProductFormScreen(
          repo: repo,
          photos: widget.photos,
          clock: widget.clock,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const SemicolonText('Início'),
        actions: [
          if (widget.onOpenSettings case final open?)
            IconButton(
              tooltip: 'Configurações',
              icon: const Icon(Symbols.settings_rounded),
              onPressed: open,
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          if (!_c.loaded) return const SizedBox.shrink();
          final bottom = 24 + MediaQuery.paddingOf(context).bottom;
          if (_c.firstRun) {
            return ListView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, bottom),
              children: [
                Text(
                  'Comece por aqui',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Cadastre seus produtos e clientes. Depois, registre as '
                  'vendas: o que vencer e quem fizer aniversário aparece '
                  'aqui todo dia.',
                ),
                const SizedBox(height: 20),
                _Shortcuts(
                  onSale: null,
                  onClient: widget.clients == null ? null : _newClient,
                  onProduct: widget.products == null ? null : _newProduct,
                ),
              ],
            );
          }
          return ListView(
            padding: EdgeInsets.only(bottom: bottom),
            children: [
              _Today(
                controller: _c,
                open: _open,
                saleCtx: _saleCtx,
                widget: widget,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: _Shortcuts(
                  onSale: _saleCtx?.products == null ? null : _newSale,
                  onClient: widget.clients == null ? null : _newClient,
                  onProduct: widget.products == null ? null : _newProduct,
                ),
              ),
              _Month(controller: _c),
            ],
          );
        },
      ),
    );
  }
}

/// Big shortcuts with a verb: the label breaks in two
/// lines with large text instead of being cut.
class _Shortcuts extends StatelessWidget {
  const _Shortcuts({
    required this.onSale,
    required this.onClient,
    required this.onProduct,
  });

  final VoidCallback? onSale;
  final VoidCallback? onClient;
  final VoidCallback? onProduct;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    Widget tile(String label, IconData icon, VoidCallback? onTap) => Expanded(
      child: Material(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusHighlight),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 28, color: colors.onSecondaryContainer),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: t.labelLarge!.copyWith(
                    color: colors.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // The same height for all, the tallest label's.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          if (onSale != null)
            tile('Nova venda', Symbols.point_of_sale_rounded, onSale),
          tile('Novo cliente', Symbols.person_add_rounded, onClient),
          tile('Novo produto', Symbols.add_box_rounded, onProduct),
        ],
      ),
    );
  }
}

/// The "Hoje" block: due and overdue, birthdays, low stock.
class _Today extends StatelessWidget {
  const _Today({
    required this.controller,
    required this.open,
    required this.saleCtx,
    required this.widget,
  });

  final StartController controller;
  final Future<void> Function(Widget) open;
  final SaleContext? saleCtx;
  final StartScreen widget;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final today = c.today;
    final nothing =
        c.receivables.isEmpty &&
        c.birthdays.isEmpty &&
        c.lowStock.isEmpty &&
        c.expiring.isEmpty &&
        c.waiting.isEmpty;
    final todayIso = isoDay(today);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Hoje'),
        if (nothing)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Tudo em dia: nenhuma parcela vence hoje, ninguém faz '
              'aniversário nesta semana, nenhuma conversa espera resposta e '
              'o estoque está bom, sem produto perto de vencer.',
              style: t.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        if (c.receivables.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 12,
              children: [
                Text(
                  'A receber até hoje',
                  style: t.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
                ),
                MoneyText(formatMoney(c.receivableTotal), small: true),
              ],
            ),
          ),
          for (final r in c.receivables.take(5))
            AppListTile(
              leading: InitialsAvatar(r.sale.clientLabel),
              title: Text(
                r.sale.clientLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              // What is due first, never cut.
              subtitle: Text(
                '${r.number}ª parcela ${dueLabel(r.due, today)}\n'
                'Venda nº ${r.sale.number}',
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatMoney(r.left), style: tabular),
                  const SizedBox(height: 2),
                  r.due == todayIso
                      ? const StatusPill('Hoje', Situation.open)
                      : const StatusPill('Vencida', Situation.overdue),
                ],
              ),
              onTap: saleCtx == null || r.sale.id == null
                  ? null
                  : () => open(SaleScreen(ctx: saleCtx!, id: r.sale.id!)),
            ),
          if (c.receivables.length > 5)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'E mais ${c.receivables.length - 5} na aba Vendas, '
                'em "A receber".',
                style: t.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
        for (final b in c.birthdays)
          AppListTile(
            leading: InitialsAvatar(b.client.name),
            title: Text(
              b.client.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              b.inDays == 0
                  ? 'Faz aniversário hoje'
                  : 'Aniversário ${inDaysLabel(b.inDays).toLowerCase()}',
            ),
            trailing: const Icon(Symbols.cake_rounded),
            onTap: widget.clients == null || b.client.id == null
                ? null
                : () => open(
                    ClientScreen(
                      repo: widget.clients!,
                      id: b.client.id!,
                      bridge: widget.bridge,
                    ),
                  ),
          ),
        if (c.waiting.isNotEmpty) ..._waiting(context),
        // One row per product, its situations together.
        for (final a in c.productAlerts.take(5))
          AppListTile(
            leading: widget.products == null
                ? null
                : ProductAvatar(product: a.product, repo: widget.products!),
            title: Text(
              a.product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              [
                if (a.expiry) expiryLabel(a.product, today)!,
                if (a.stock)
                  a.product.outOfStock
                      ? 'Sem estoque'
                      : '${formatQuantity(a.product.stock)} ${a.product.unit} '
                            'em estoque',
              ].join(' · '),
            ),
            trailing: Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              runSpacing: 4,
              children: [
                if (a.expiry)
                  a.product.expiresIn(today)! < 0
                      ? const StatusPill('Vencido', Situation.overdue)
                      : const StatusPill('Vencendo', Situation.open),
                if (a.stock)
                  a.product.outOfStock
                      ? const StatusPill('Sem estoque', Situation.overdue)
                      : const StatusPill('Estoque baixo', Situation.open),
              ],
            ),
            onTap: widget.products == null || a.product.id == null
                ? null
                : () => open(
                    ProductScreen(
                      repo: widget.products!,
                      id: a.product.id!,
                      photos: widget.photos,
                      clock: widget.clock,
                    ),
                  ),
          ),
        if (c.productAlerts.length > 5)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'E mais ${c.productAlerts.length - 5} em Produtos.',
              style: t.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  /// "Conversas sem resposta": how many, and the ones
  /// waiting longest.
  List<Widget> _waiting(BuildContext context) {
    final c = controller;
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final bridge = widget.bridge;
    final n = c.waiting.length;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text(
          '${plural(n, 'conversa', 'conversas')} sem resposta',
          style: t.bodyMedium!.copyWith(color: muted),
        ),
      ),
      for (final chat in c.waiting.take(StartController.waitingShown))
        if ((c.waitingClients[chat.jid]?.name, chatTitle(chat)) case (
          final client,
          final title,
        ))
          AppListTile(
            leading: InitialsAvatar(client ?? title),
            // The mark goes under the name when there is no room.
            title: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  client ?? title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (client != null) const ClientMark(),
              ],
            ),
            subtitle: Text(
              chat.lastText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              waitingLabel(
                DateTime.fromMillisecondsSinceEpoch(chat.lastTs),
                c.today,
              ),
              style: t.labelMedium!.copyWith(color: muted),
            ),
            onTap: bridge == null
                ? null
                : () => open(
                    ChatScreen(
                      bridge: bridge,
                      chat: chat,
                      clients: widget.clients,
                    ),
                  ),
          ),
      if (widget.onOpenWaiting case final all?)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: all, child: const Text('Ver todas')),
          ),
        ),
    ];
  }
}

/// The month's numbers, with arrows to change the month.
class _Month extends StatelessWidget {
  const _Month({required this.controller});

  final StartController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final n = c.numbers;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ticket = n.count == 0 ? 0 : n.revenue ~/ n.count;
    Widget number(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: t.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
          ),
          Text(
            value,
            style: t.titleLarge!.merge(tabular),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Mês anterior',
                icon: const Icon(Symbols.chevron_left_rounded),
                onPressed: () => c.moveMonth(-1),
              ),
              Expanded(
                child: Text(
                  monthLabel(c.month),
                  style: t.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                tooltip: 'Próximo mês',
                icon: const Icon(Symbols.chevron_right_rounded),
                onPressed: c.atCurrentMonth ? null : () => c.moveMonth(1),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Faturamento',
                style: t.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
              ),
              MoneyText(formatMoney(n.revenue)),
              const SizedBox(height: 12),
              Row(
                spacing: 12,
                children: [
                  number('Vendas', '${n.count}'),
                  number('Ticket médio', formatMoney(ticket)),
                  number('Lucro', formatMoney(n.profit)),
                ],
              ),
            ],
          ),
        ),
        if (n.top.isNotEmpty) ...[
          const SectionHeader('Mais vendidos'),
          for (final p in n.top)
            ListTile(
              dense: true,
              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${formatQuantity(p.quantity)} '
                '${p.quantity == 1000 ? 'vendido' : 'vendidos'}',
              ),
              trailing: Text(formatMoney(p.amount), style: tabular),
            ),
        ] else
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Nenhuma venda em ${monthLabel(c.month).toLowerCase()}.',
              style: t.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}
