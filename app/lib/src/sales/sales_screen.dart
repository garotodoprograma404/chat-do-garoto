import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/responsive.dart';
import '../clients/clients_repository.dart';
import '../core_bridge/core_bridge.dart';
import '../products/money.dart';
import '../products/pricing.dart';
import '../products/products_repository.dart';
import '../settings/settings_menu.dart';
import '../theme/detail_pane.dart';
import '../theme/brand_mark.dart';
import '../theme/components.dart';
import '../theme/motion.dart';
import '../theme/status_colors.dart';
import 'quick_sale_screen.dart';
import 'sale_form_screen.dart';
import 'sale_math.dart';
import 'sale_screen.dart';
import 'sales_controller.dart';
import 'sales_repository.dart';

/// "02/10/2026".
String saleDay(DateTime d) => formatDay(isoDay(d));

/// The situation shown for each sale status.
const saleSituations = {
  SaleStatus.paid: Situation.ok,
  SaleStatus.open: Situation.open,
  SaleStatus.overdue: Situation.overdue,
  SaleStatus.canceled: Situation.off,
};

/// "Hoje", "Ontem" or "02/10/2026", for the day headings of a list.
String dayHeading(DateTime d, DateTime today) {
  final day = DateTime(d.year, d.month, d.day);
  final diff = DateTime(today.year, today.month, today.day).difference(day);
  return switch (diff.inDays) {
    0 => 'Hoje',
    1 => 'Ontem',
    _ => saleDay(d),
  };
}

/// A sale's situation as a pill.
Widget saleStatusPill(SaleStatus s) =>
    StatusPill(saleStatusLabels[s]!, saleSituations[s]!);

/// What a sale screen needs besides the sales.
class SaleContext {
  const SaleContext({
    required this.sales,
    this.products,
    this.clients,
    this.bridge,
    this.clock,
  });

  final SalesRepository sales;

  /// Null where new sales cannot be made.
  final ProductsRepository? products;
  final ClientsRepository? clients;

  /// For the summary in the client's conversation; null hides it.
  final CoreBridge? bridge;
  final DateTime Function()? clock;
}

Future<void> openSale(BuildContext context, SaleContext ctx, int id) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SaleScreen(ctx: ctx, id: id),
      ),
    );

/// The Vendas section: the sales and what is left to receive. Only the title and the tabs stay on top; filters and totals
/// scroll with the list.
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key, required this.ctx, this.onOpenSettings});

  final SaleContext ctx;
  final VoidCallback? onOpenSettings;

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen>
    with SingleTickerProviderStateMixin {
  late final _controller = SalesController(
    repo: widget.ctx.sales,
    clock: widget.ctx.clock,
  )..load();
  late final _tabs = TabController(length: 2, vsync: this);
  final _search = SalesSearch();

  final _detailReloader = DetailReloader();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _detailReloader.attach(context, _controller.load);
  }

  @override
  void dispose() {
    _detailReloader.dispose();
    _controller.dispose();
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    await _controller.load();
  }

  /// "Venda rápida" and "Nova venda" side by side, over one row of the
  /// list; one under the other only when they do not fit.
  Widget _buttons(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width - 32,
      ),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          // Only the amount: needs no product.
          FloatingActionButton.extended(
            heroTag: 'quick-sale',
            onPressed: () => _open(QuickSaleScreen(ctx: widget.ctx)),
            backgroundColor: colors.secondaryContainer,
            // The strong text color: the container's own was at the
            // limit of 4.5:1 and looked off.
            foregroundColor: colors.onSurface,
            icon: const Icon(Symbols.bolt_rounded),
            label: const Text('Venda rápida'),
          ),
          if (widget.ctx.products != null)
            FloatingActionButton.extended(
              heroTag: 'new-sale',
              onPressed: () => _open(SaleFormScreen(ctx: widget.ctx)),
              icon: const Icon(Symbols.point_of_sale_rounded),
              label: const Text('Nova venda'),
            ),
        ],
      ),
    );
  }

  /// The same two buttons as a bar at the foot of the list (desktop,
  /// tablet).
  Widget _bar() => ListActionBar(
    children: [
      FilledButton.tonalIcon(
        onPressed: () => _open(QuickSaleScreen(ctx: widget.ctx)),
        icon: const Icon(Symbols.bolt_rounded),
        label: const Text('Venda rápida'),
      ),
      if (widget.ctx.products != null)
        FilledButton.icon(
          onPressed: () => _open(SaleFormScreen(ctx: widget.ctx)),
          icon: const Icon(Symbols.point_of_sale_rounded),
          label: const Text('Nova venda'),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    // Side by side the two buttons are about 300 dp at normal size; with
    // larger text they go one under the other.
    final fabs = MediaQuery.textScalerOf(context).scale(10) > 11 ? 2 : 1;
    return ListenableBuilder(
      listenable: _search,
      builder: (context, _) => PopScope(
        canPop: !_search.open,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _search.close(_controller);
        },
        child: Scaffold(
          appBar: _search.appBar(
            context,
            controller: _controller,
            title: 'Vendas',
            onOpen: () => _tabs.animateTo(0),
            actions: [
              if (widget.onOpenSettings case final open?)
                SettingsMenuButton(onOpenSettings: open),
            ],
            bottom: TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Vendas'),
                Tab(text: 'A receber'),
              ],
            ),
          ),
          floatingActionButton: actionBar(context) ? null : _buttons(context),
          bottomNavigationBar: actionBar(context) ? _bar() : null,
          body: TabBarView(
            controller: _tabs,
            children: [
              SalesListBody(
                controller: _controller,
                ctx: widget.ctx,
                fabs: fabs,
              ),
              _Receivables(
                controller: _controller,
                ctx: widget.ctx,
                fabs: fabs,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The search of a sales list, behind an icon in the title bar: the field takes the title's place while open.
class SalesSearch extends ChangeNotifier {
  final text = TextEditingController();
  bool open = false;

  void close(SalesController controller) {
    open = false;
    text.clear();
    controller.search('');
    notifyListeners();
  }

  PreferredSizeWidget appBar(
    BuildContext context, {
    required SalesController controller,
    required String title,
    List<Widget> actions = const [],
    PreferredSizeWidget? bottom,
    VoidCallback? onOpen,
  }) {
    if (!open) {
      return AppBar(
        title: SemicolonText(title),
        actions: [
          IconButton(
            tooltip: 'Buscar vendas',
            icon: const Icon(Symbols.search_rounded),
            onPressed: () {
              open = true;
              onOpen?.call();
              notifyListeners();
            },
          ),
          ...actions,
        ],
        bottom: bottom,
      );
    }
    const none = InputBorder.none;
    return AppBar(
      leading: IconButton(
        tooltip: 'Fechar busca',
        icon: const Icon(Symbols.arrow_back_rounded),
        onPressed: () => close(controller),
      ),
      title: TextField(
        controller: text,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onChanged: controller.search,
        decoration: const InputDecoration(
          hintText: 'Buscar por cliente, número ou produto',
          border: none,
          enabledBorder: none,
          focusedBorder: none,
          contentPadding: EdgeInsets.zero,
        ),
      ),
      bottom: bottom,
    );
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }
}

/// The period in one chip that opens the choices, and the situations
/// beside it: one row.
class _Filters extends StatelessWidget {
  const _Filters({required this.controller});

  final SalesController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = Theme.of(context).colorScheme;
    final chosen = c.period != SalePeriod.all;
    return FilterBar(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      children: [
        PopupMenuButton<SalePeriod>(
          tooltip: 'Período',
          onSelected: c.setPeriod,
          itemBuilder: (context) => [
            for (final MapEntry(:key, :value) in salePeriodLabels.entries)
              CheckedPopupMenuItem(
                value: key,
                checked: c.period == key,
                child: Text(value),
              ),
          ],
          child: Chip(
            backgroundColor: chosen ? colors.secondaryContainer : null,
            avatar: const Icon(Symbols.calendar_month_rounded, size: 18),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(salePeriodLabels[c.period]!),
                const Icon(Symbols.arrow_drop_down_rounded, size: 20),
              ],
            ),
          ),
        ),
        for (final MapEntry(:key, :value) in saleStatusLabels.entries)
          FilterChip(
            label: Text(value),
            selected: c.statuses.contains(key),
            onSelected: (_) => c.toggleStatus(key),
          ),
      ],
    );
  }
}

/// Totals in a compact card that scrolls with the list:
/// the main amount, and the others small beside each other.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.amount,
    required this.stats,
    required this.caption,
  });

  final String title;
  final int amount;

  /// Label, amount and whether it is overdue (in the overdue color).
  final List<(String, int, bool)> stats;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final (overdue, _) = AppStatusColors.resolve(context, Situation.overdue);
    Widget stat(String label, int cents, bool late) => Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label  ',
            style: t.bodySmall!.copyWith(color: muted),
          ),
          TextSpan(
            text: formatMoney(cents),
            style: t.titleSmall!
                .merge(tabular)
                .copyWith(color: late && cents > 0 ? overdue : null),
          ),
        ],
      ),
    );
    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$title · $caption', style: t.bodyMedium!.copyWith(color: muted)),
        MoneyText(formatMoney(amount), small: true),
      ],
    );
    final others = [
      for (final (label, cents, late) in stats) stat(label, cents, late),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          // The main amount on the left and the others on the right; one
          // under the other with large text.
          child: largeText(context)
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [main, ...others],
                )
              : Row(
                  children: [
                    Expanded(child: main),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      spacing: 2,
                      children: others,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The sales list with filters and totals, grouped by day. Also
/// used for one client's sales.
class SalesListBody extends StatelessWidget {
  const SalesListBody({
    super.key,
    required this.controller,
    required this.ctx,
    this.fabs = 0,
  });

  final SalesController controller;
  final SaleContext ctx;

  /// The floating buttons over the list, to leave room for.
  final int fabs;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        if (c.all.isEmpty) {
          return const EmptyState(
            title: 'Nenhuma venda ainda.',
            message: 'Registre a primeira em "Nova venda".',
          );
        }
        final sales = c.sales;
        final t = c.totals;
        final today = c.today;
        final rows = <Widget>[
          _Filters(controller: c),
          _SummaryCard(
            title: 'Vendido',
            amount: t.sold,
            caption: plural(sales.length, 'venda', 'vendas'),
            stats: [
              ('Recebido', t.received, false),
              ('A receber', t.open, false),
              ('Lucro', t.profit, false),
            ],
          ),
          if (sales.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nenhuma venda com essa busca ou esses filtros.'),
            ),
        ];
        // Sales grouped by day, newest first, with the day's total.
        String? day;
        for (final s in sales) {
          final heading = dayHeading(s.soldAt, today);
          if (heading != day) {
            day = heading;
            final dayTotal = sales
                .where(
                  (x) => !x.canceled && dayHeading(x.soldAt, today) == heading,
                )
                .fold(0, (sum, x) => sum + x.total);
            rows.add(
              SectionHeader(
                heading,
                trailing: Text(formatMoney(dayTotal), style: tabular),
              ),
            );
          }
          final status = s.status(today);
          rows.add(
            OpenTile(
              selectKey: 'sale:${s.id}',
              onClosed: c.load,
              page: (_) => SaleScreen(ctx: ctx, id: s.id!),
              row: (open) => AppListTile(
                selected: DetailHost.isSelected(context, 'sale:${s.id}'),
                leading: InitialsAvatar(s.clientLabel),
                title: Text(
                  s.clientLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'Nº ${s.number} · ${plural(s.items.length, 'item', 'itens')}',
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatMoney(s.total), style: tabular),
                    const SizedBox(height: 2),
                    saleStatusPill(status),
                  ],
                ),
                onTap: open,
              ),
            ),
          );
        }
        return ListView(
          padding: EdgeInsets.only(
            bottom: listBottomPadding(context, fab: fabs > 0, fabs: fabs),
          ),
          children: rows,
        );
      },
    );
  }
}

/// Open installments: a card with the total and the overdue part,
/// then "Vencidas" and "A vencer".
class _Receivables extends StatelessWidget {
  const _Receivables({
    required this.controller,
    required this.ctx,
    required this.fabs,
  });

  final SalesController controller;
  final SaleContext ctx;
  final int fabs;

  Widget _row(BuildContext context, Receivable r) => AppListTile(
    leading: InitialsAvatar(r.sale.clientLabel),
    title: Text(
      r.sale.clientLabel,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    // What is due first, never cut.
    subtitle: Text(
      '${r.installment.number}ª parcela '
      '${dueLabel(r.installment.due, controller.today)}\n'
      'Venda nº ${r.sale.number} · ${formatDay(r.installment.due)}',
    ),
    trailing: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(formatMoney(r.left), style: tabular),
        const SizedBox(height: 2),
        r.overdue
            ? const StatusPill('Vencida', Situation.overdue)
            : const StatusPill('Em aberto', Situation.open),
      ],
    ),
    onTap: () async {
      await openSale(context, ctx, r.sale.id!);
      await controller.load();
    },
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final list = controller.receivables;
        if (list.isEmpty) {
          return const EmptyState(
            title: 'Nada a receber.',
            message: 'As parcelas das vendas a prazo aparecem aqui.',
          );
        }
        final t = controller.receivableTotals;
        final overdue = [
          for (final r in list)
            if (r.overdue) r,
        ];
        final upcoming = [
          for (final r in list)
            if (!r.overdue) r,
        ];
        Widget heading(String text, List<Receivable> rows) => SectionHeader(
          text,
          trailing: Text(
            formatMoney(rows.fold(0, (sum, r) => sum + r.left)),
            style: tabular,
          ),
        );
        return ListView(
          padding: EdgeInsets.only(
            bottom: listBottomPadding(context, fab: true, fabs: fabs),
          ),
          children: [
            _SummaryCard(
              title: 'A receber',
              amount: t.open,
              caption: plural(list.length, 'parcela', 'parcelas'),
              stats: [
                ('Vencido', t.overdue, true),
                ('A vencer', t.open - t.overdue, false),
              ],
            ),
            if (overdue.isNotEmpty) ...[
              heading('Vencidas', overdue),
              for (final r in overdue) _row(context, r),
            ],
            if (upcoming.isNotEmpty) ...[
              heading('A vencer', upcoming),
              for (final r in upcoming) _row(context, r),
            ],
          ],
        );
      },
    );
  }
}

/// One client's sales ("Ver todas" on the client page).
class ClientSalesScreen extends StatefulWidget {
  const ClientSalesScreen({
    super.key,
    required this.ctx,
    required this.clientId,
    required this.clientName,
  });

  final SaleContext ctx;
  final int clientId;
  final String clientName;

  @override
  State<ClientSalesScreen> createState() => _ClientSalesScreenState();
}

class _ClientSalesScreenState extends State<ClientSalesScreen> {
  late final _controller = SalesController(
    repo: widget.ctx.sales,
    clock: widget.ctx.clock,
    clientId: widget.clientId,
  )..load();
  final _search = SalesSearch();

  @override
  void dispose() {
    _controller.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _search,
      builder: (context, _) => PopScope(
        canPop: !_search.open,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _search.close(_controller);
        },
        child: Scaffold(
          appBar: _search.appBar(
            context,
            controller: _controller,
            title: 'Vendas: ${widget.clientName}',
          ),
          body: SalesListBody(controller: _controller, ctx: widget.ctx),
        ),
      ),
    );
  }
}
