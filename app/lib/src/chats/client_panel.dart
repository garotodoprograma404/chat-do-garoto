import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../clients/client_screen.dart' show noteTime;
import '../clients/client_summary.dart';
import '../clients/clients_repository.dart';
import '../clients/validation.dart';
import '../sales/sales_repository.dart';
import '../theme/components.dart';
import '../theme/motion.dart';

/// Width of the client panel docked beside a conversation, and the least
/// room (the conversation's pane) that has space for it.
const dockWidth = 340.0;
const dockMinPane = 1080.0;

/// What the person picked in the client panel; the conversation acts on
/// it.
enum PanelAction { newSale, receive, charge, openFile, register, link }

/// The client panel, opened by the name of a one-person conversation
///: a client's numbers, last notes and actions, or, for
/// someone who is not a client, "Cadastrar" and "Vincular".
Future<PanelAction?> showClientPanel(
  BuildContext context, {
  required String title,
  required String phone,
  Client? client,
  ClientsRepository? repo,
  SalesRepository? sales,
  bool canSell = false,
  DateTime Function()? clock,
}) => showModalBottomSheet<PanelAction>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  sheetAnimationStyle: AnimationStyle(
    duration: Motion.of(context, Motion.sheetIn),
    reverseDuration: Motion.of(context, Motion.sheetOut),
  ),
  builder: (context) => ClientPanelView(
    title: title,
    phone: phone,
    client: client,
    repo: repo,
    sales: sales,
    canSell: canSell,
    today: (clock ?? DateTime.now)(),
    onAction: (action) => Navigator.pop(context, action),
  ),
);

/// The client's numbers, last notes and actions. Opened as a sheet on
/// small windows ([showClientPanel]) and docked beside a conversation on
/// big ones ([docked]), where it stays in view while the person talks.
class ClientPanelView extends StatefulWidget {
  const ClientPanelView({
    super.key,
    required this.title,
    required this.phone,
    required this.client,
    required this.repo,
    required this.sales,
    required this.canSell,
    required this.today,
    required this.onAction,
    this.docked = false,
  });

  /// Whether it lives beside the conversation: the actions stack in a
  /// column, one per line, as in a side panel.
  final bool docked;
  final ValueChanged<PanelAction> onAction;

  final String title;
  final String phone;
  final Client? client;
  final ClientsRepository? repo;
  final SalesRepository? sales;
  final bool canSell;
  final DateTime today;

  @override
  State<ClientPanelView> createState() => _ClientPanelState();
}

class _ClientPanelState extends State<ClientPanelView> {
  ClientSummary? _summary;
  List<ClientNote> _notes = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.client?.id;
    if (id == null) return;
    final sales = await widget.sales?.byClient(id) ?? const <Sale>[];
    final notes = await widget.repo?.notes(id) ?? const <ClientNote>[];
    if (!mounted) return;
    setState(() {
      _summary = ClientSummary.of(sales, widget.today);
      _notes = notes.take(2).toList();
    });
  }

  void _pick(PanelAction action) => widget.onAction(action);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final client = widget.client;
    final summary = _summary;
    final name = client?.name ?? widget.title;
    final docked = widget.docked;
    return SingleChildScrollView(
      padding: docked
          ? const EdgeInsets.all(24)
          : EdgeInsets.fromLTRB(
              24,
              0,
              24,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialsAvatar(name, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: t.headlineSmall),
                    Text(
                      widget.phone.isEmpty
                          ? 'Número não informado pelo WhatsApp'
                          : formatPhone(widget.phone),
                      style: t.bodyMedium!.copyWith(color: muted),
                    ),
                    if (client != null && client.tags.isNotEmpty)
                      Text(
                        client.tags.join(' · '),
                        style: t.bodyMedium!.copyWith(color: muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (client == null) ...[
            const Text('Este contato ainda não é cliente.'),
            const SizedBox(height: 16),
            _Actions(
              docked: docked,
              children: [
                FilledButton.icon(
                  onPressed: () => _pick(PanelAction.register),
                  icon: const Icon(Symbols.person_add_rounded),
                  label: const Text('Cadastrar como cliente'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pick(PanelAction.link),
                  icon: const Icon(Symbols.link_rounded),
                  label: const Text('Vincular a um cliente'),
                ),
              ],
            ),
          ] else ...[
            if (summary != null) ClientNumbers(summary),
            if (_notes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Últimas anotações', style: t.titleSmall),
              for (final n in _notes)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: n.body),
                        TextSpan(
                          text: '  ${noteTime(n.at)}',
                          style: t.bodySmall!.copyWith(color: muted),
                        ),
                      ],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            const SizedBox(height: 16),
            _Actions(
              docked: docked,
              children: [
                if (widget.canSell)
                  FilledButton.icon(
                    onPressed: () => _pick(PanelAction.newSale),
                    icon: const Icon(Symbols.add_shopping_cart_rounded),
                    label: const Text('Nova venda'),
                  ),
                if ((summary?.owes ?? 0) > 0) ...[
                  FilledButton.tonalIcon(
                    onPressed: () => _pick(PanelAction.receive),
                    icon: const Icon(Symbols.payments_rounded),
                    label: const Text('Receber'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _pick(PanelAction.charge),
                    icon: const Icon(Symbols.request_quote_rounded),
                    label: const Text('Cobrar'),
                  ),
                ],
                OutlinedButton.icon(
                  onPressed: () => _pick(PanelAction.openFile),
                  icon: const Icon(Symbols.badge_rounded),
                  label: const Text('Ver ficha'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The panel's buttons: side by side, wrapping, in the sheet; one per
/// line, full width, in the docked panel.
class _Actions extends StatelessWidget {
  const _Actions({required this.docked, required this.children});

  final bool docked;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => docked
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: children,
        )
      : Wrap(spacing: 8, runSpacing: 8, children: children);
}
