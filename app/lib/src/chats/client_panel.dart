import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../clients/client_screen.dart' show noteTime;
import '../clients/client_summary.dart';
import '../clients/clients_repository.dart';
import '../clients/validation.dart';
import '../sales/sales_repository.dart';
import '../theme/components.dart';
import '../theme/motion.dart';

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
  builder: (_) => _ClientPanel(
    title: title,
    phone: phone,
    client: client,
    repo: repo,
    sales: sales,
    canSell: canSell,
    today: (clock ?? DateTime.now)(),
  ),
);

class _ClientPanel extends StatefulWidget {
  const _ClientPanel({
    required this.title,
    required this.phone,
    required this.client,
    required this.repo,
    required this.sales,
    required this.canSell,
    required this.today,
  });

  final String title;
  final String phone;
  final Client? client;
  final ClientsRepository? repo;
  final SalesRepository? sales;
  final bool canSell;
  final DateTime today;

  @override
  State<_ClientPanel> createState() => _ClientPanelState();
}

class _ClientPanelState extends State<_ClientPanel> {
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

  void _pick(PanelAction action) => Navigator.pop(context, action);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final client = widget.client;
    final summary = _summary;
    final name = client?.name ?? widget.title;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
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
