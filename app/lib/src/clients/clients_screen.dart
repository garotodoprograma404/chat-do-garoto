import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../core_bridge/core_bridge.dart';
import '../home/crm_scope.dart';
import '../products/money.dart';
import '../sales/sales_repository.dart';
import '../settings/settings_menu.dart';
import '../theme/brand_mark.dart';
import '../theme/components.dart';
import '../theme/motion.dart';
import '../theme/status_colors.dart';
import 'client_form_screen.dart';
import 'client_hint.dart';
import 'client_screen.dart';
import 'clients_controller.dart';
import 'clients_repository.dart';

/// All clients, by name, and "Novo cliente".
class ClientsScreen extends StatefulWidget {
  const ClientsScreen({
    super.key,
    required this.repo,
    this.onOpenSettings,
    this.bridge,
    this.clock,
  });

  final ClientsRepository repo;
  final DateTime Function()? clock;

  /// The WhatsApp side for the client page.
  final CoreBridge? bridge;

  /// Shows the ⋮ menu when this screen is the Clientes section.
  final VoidCallback? onOpenSettings;

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  late final _controller = ClientsController(
    repo: widget.repo,
    bridge: widget.bridge,
    clock: widget.clock,
  )..load();

  DateTime _now() => widget.clock?.call() ?? DateTime.now();

  static const _sorts = {
    ClientSort.name: 'Nome (A-Z)',
    ClientSort.newest: 'Cadastro mais recente',
    ClientSort.lastChat: 'Última conversa',
    ClientSort.birthday: 'Próximo aniversário',
  };

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    await _controller.load();
    await _loadDebts();
  }

  /// What each client owes, for the row's amount.
  Map<int, ({int open, bool overdue})> _debts = const {};

  /// Each client's sales, for the row's useful line.
  Map<int, List<Sale>> _salesBy = const {};
  SalesRepository? _sales;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sales = CrmScope.maybeOf(context)?.sales;
    if (!identical(sales, _sales)) {
      _sales = sales;
      _loadDebts();
    }
  }

  Future<void> _loadDebts() async {
    final sales = _sales;
    if (sales == null) return;
    final all = await sales.list();
    final now = _now();
    final debts = debtsByClient(all, now);
    final by = <int, List<Sale>>{};
    for (final s in all) {
      if (s.clientId case final id?) (by[id] ??= []).add(s);
    }
    if (!mounted) return;
    setState(() {
      _debts = debts;
      _salesBy = by;
    });
    _controller.setDebtors(debts.keys.toSet(), gone: goneClients(all, now));
  }

  Widget? _debt(int? id) {
    final d = _debts[id];
    if (d == null) return null;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(formatMoney(d.open), style: tabular),
        const SizedBox(height: 2),
        d.overdue
            ? const StatusPill('Vencido', Situation.overdue)
            : const StatusPill('Em aberto', Situation.open),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const SemicolonText('Clientes'),
        actions: [
          PopupMenuButton<ClientSort>(
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
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-client',
        onPressed: () => _open(ClientFormScreen(repo: widget.repo)),
        icon: const Icon(Symbols.person_add_rounded),
        label: const Text('Novo cliente'),
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final all = _controller.all;
          if (all.isEmpty) {
            return const EmptyState(
              title: 'Nenhum cliente ainda.',
              message:
                  'Cadastre o primeiro em "Novo cliente" ou salve um contato '
                  'a partir de uma conversa.',
            );
          }
          final clients = _controller.clients;
          final t = Theme.of(context).textTheme;
          final muted = Theme.of(context).colorScheme.onSurfaceVariant;
          final today = _now();
          // By name, the ones owing first, each group in name order
          final owing = [
            for (final c in clients)
              if (_debts.containsKey(c.id)) c,
          ];
          final rows = <Object>[
            if (_controller.sort == ClientSort.name &&
                owing.isNotEmpty &&
                owing.length < clients.length) ...[
              'Devendo',
              ...owing,
              'Em dia',
              for (final c in clients)
                if (!_debts.containsKey(c.id)) c,
            ] else
              ...clients,
          ];
          return Column(
            children: [
              AppSearchField(
                hint: 'Buscar clientes',
                onChanged: _controller.search,
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  spacing: 8,
                  children: [
                    if (_sales != null) ...[
                      FilterChip(
                        label: const Text('Devendo'),
                        selected: _controller.owingOnly,
                        onSelected: (_) => _controller.toggleOwing(),
                      ),
                      FilterChip(
                        label: const Text('Sumidos'),
                        selected: _controller.goneOnly,
                        onSelected: (_) => _controller.toggleGone(),
                      ),
                    ],
                    FilterChip(
                      label: const Text('Aniversariantes do mês'),
                      selected: _controller.birthdaysThisMonth,
                      onSelected: (_) => _controller.toggleBirthdays(),
                    ),
                    for (final tag in _controller.allTags)
                      FilterChip(
                        label: Text(tag),
                        selected: _controller.tags.contains(tag),
                        onSelected: (_) => _controller.toggleTag(tag),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${clients.length} de ${all.length}',
                    style: t.bodySmall!.copyWith(color: muted),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.only(
                    bottom: listBottomPadding(context, fab: true),
                  ),
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    if (row is String) return SectionHeader(row);
                    final client = row as Client;
                    return OpenTile(
                      onClosed: () {
                        _controller.load();
                        _loadDebts();
                      },
                      page: (_) => ClientScreen(
                        repo: widget.repo,
                        id: client.id!,
                        bridge: widget.bridge,
                      ),
                      row: (open) => AppListTile(
                        leading: InitialsAvatar(client.name),
                        title: Text(
                          client.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              clientHint(
                                client,
                                _salesBy[client.id] ?? const [],
                                today,
                              ),
                            ),
                            if (client.tags.isNotEmpty)
                              Text(
                                client.tags.join(', '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodySmall!.copyWith(color: muted),
                              ),
                          ],
                        ),
                        trailing: _debt(client.id),
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
