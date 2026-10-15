import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../chats/chat_screen.dart';
import '../clients/clients_repository.dart';
import '../core_bridge/core_bridge.dart';
import '../products/money.dart';
import '../products/pricing.dart';
import '../theme/components.dart';
import '../theme/motion.dart';
import '../theme/status_colors.dart';
import 'sale_math.dart';
import 'receive_dialog.dart';
import 'sale_summary.dart';
import 'sales_repository.dart';
import 'sales_screen.dart';
import '../theme/responsive.dart';

/// One sale: items, totals, payments and installments; receive, undo a
/// receipt, cancel and the summary on WhatsApp.
class SaleScreen extends StatefulWidget {
  const SaleScreen({
    super.key,
    required this.ctx,
    required this.id,
    this.registered = false,
  });

  /// Just concluded: the top comes in with the highlight.
  final bool registered;

  final SaleContext ctx;
  final int id;

  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
  Sale? _sale;
  Client? _client;
  String _chat = '';
  bool _loaded = false;

  SaleContext get ctx => widget.ctx;
  DateTime get _today => (ctx.clock ?? DateTime.now)();

  /// "Venda registrada" or "Recebimento registrado", shown with the
  /// highlight; [_celebration] replays it.
  late String? _celebrating = widget.registered ? 'Venda registrada' : null;
  int _celebration = 0;

  @override
  void initState() {
    super.initState();
    if (widget.registered) Haptics.success();
    _load();
  }

  Future<void> _load() async {
    final sale = await ctx.sales.byId(widget.id);
    Client? client;
    var chat = '';
    if (sale?.clientId case final id? when ctx.clients != null) {
      client = await ctx.clients!.byId(id);
    }
    // The client's conversation, as on the client page.
    if ((client, ctx.bridge) case (final c?, final bridge?)) {
      chat = c.chatJid ?? '';
      if (chat.isEmpty) {
        try {
          chat = bridge.chatForPhone(c.phone);
        } on CoreException {
          chat = ''; // WhatsApp not started
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _sale = sale;
      _client = client;
      _chat = chat;
      _loaded = true;
    });
  }

  Future<void> _receive(Sale s) async {
    final receipt = await askReceipt(context, s, _today);
    if (receipt == null) return;
    await ctx.sales.receive(s.id!, receipt.method, receipt.amount, receipt.at);
    Haptics.success();
    _celebrating = 'Recebimento registrado';
    _celebration++;
    await _load();
  }

  Future<void> _undo(SalePayment p) async {
    final ok = await _confirm(
      'Desfazer recebimento?',
      '${payMethodLabels[p.method]} ${formatMoney(p.amount)} em '
          '${saleDay(p.at)} volta a ficar em aberto.',
      'Desfazer',
    );
    if (!ok) return;
    await ctx.sales.undoReceipt(p.id!);
    await _load();
  }

  Future<void> _cancel(Sale s) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _CancelDialog(number: s.number),
    );
    if (reason == null) return;
    await ctx.sales.cancel(s.id!, reason: reason);
    await _load();
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Opens the client's conversation with the summary in the message box;
  /// sending stays with the user.
  void _summary(Sale s) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: wideRouteName),
      builder: (_) => ChatScreen(
        bridge: ctx.bridge!,
        chat: ChatSummary(
          jid: _chat,
          name: _client?.name ?? '',
          lastText: '',
          lastTs: 0,
        ),
        clients: ctx.clients,
        draft: saleSummary(s),
      ),
    ),
  );

  Widget _line(String title, String value, {TextStyle? style}) => ListTile(
    dense: true,
    // On the same left edge as the section titles.
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(value, style: style),
  );

  @override
  Widget build(BuildContext context) {
    final s = _sale;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: _loaded
              ? const Text('Venda não encontrada.')
              : const CircularProgressIndicator(),
        ),
      );
    }
    final today = _today;
    final status = s.status(today);
    final paid = s.installmentPaid;
    final error = TextStyle(color: Theme.of(context).colorScheme.error);
    return Scaffold(
      appBar: AppBar(
        title: Text('Venda nº ${s.number}'),
        actions: [
          if (!s.canceled)
            IconButton(
              tooltip: 'Cancelar venda',
              icon: const Icon(Symbols.block_rounded),
              onPressed: () => _cancel(s),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          // A wide pane: the items beside the payments and installments
          final wide = box.maxWidth >= 760;
          final top = <Widget>[
            if (_celebrating case final text?)
              Highlight(
                key: ValueKey(_celebration),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Done(text),
                    const SizedBox(height: 8),
                    _Header(sale: s, status: status),
                  ],
                ),
              )
            else
              _Header(sale: s, status: status),
          ];
          final itemsBlock = <Widget>[
            Text('Itens', style: Theme.of(context).textTheme.titleMedium),
            for (final i in s.items)
              _line(
                '${formatQuantity(i.quantity)} ${i.unit} × ${i.description}',
                [
                  '${formatMoney(i.unitPrice)} cada',
                  if (i.discount > 0) 'desconto ${formatMoney(i.discount)}',
                  formatMoney(i.total),
                ].join(' · '),
              ),
            if (s.discount > 0) _line('Desconto', formatMoney(s.discount)),
            if (s.freight > 0) _line('Frete', formatMoney(s.freight)),
            _line('Total', formatMoney(s.total)),
            _line(
              'Custo e lucro',
              'custo ${formatMoney(s.cost)} · lucro ${formatMoney(s.profit)}',
            ),
          ];
          final moneyBlock = <Widget>[
            if (s.payments.isNotEmpty) ...[
              wide ? const SizedBox(height: 24) : const Divider(height: 32),
              Text(
                'Pagamentos',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final p in s.payments)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${payMethodLabels[p.method]} ${formatMoney(p.amount)}',
                  ),
                  subtitle: Text(
                    [
                      saleDay(p.at),
                      p.receipt ? 'recebido' : 'na venda',
                      if (p.voided) 'estornado',
                    ].join(' · '),
                  ),
                  trailing: p.receipt && !p.voided && !s.canceled
                      ? IconButton(
                          tooltip: 'Desfazer recebimento',
                          icon: const Icon(Symbols.undo_rounded),
                          onPressed: () => _undo(p),
                        )
                      : null,
                ),
            ],
            if (s.installments.isNotEmpty) ...[
              wide ? const SizedBox(height: 24) : const Divider(height: 32),
              Text('Parcelas', style: Theme.of(context).textTheme.titleMedium),
              for (final (i, inst) in s.installments.indexed)
                if ((
                      paid[i] >= inst.amount,
                      inst.due.compareTo(isoDay(today)) < 0,
                    )
                    case (final done, final late))
                  _line(
                    '${inst.number}ª · vence ${formatDay(inst.due)} · '
                    '${formatMoney(inst.amount)}',
                    [
                      if (paid[i] > 0 && !done) 'pago ${formatMoney(paid[i])}',
                      if (s.canceled)
                        'cancelada'
                      else if (done)
                        'paga'
                      else if (late)
                        'vencida'
                      else
                        'em aberto',
                    ].join(' · '),
                    style: !s.canceled && !done && late ? error : null,
                  ),
            ],
            if (s.note.isNotEmpty) ...[
              wide ? const SizedBox(height: 24) : const Divider(height: 32),
              _line('Observação', s.note),
            ],
          ];
          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (s.open > 0)
                FilledButton(
                  onPressed: () => _receive(s),
                  child: const Text('Receber'),
                ),
              if (_chat.isNotEmpty && !s.canceled)
                OutlinedButton(
                  onPressed: () => _summary(s),
                  child: const Text('Resumo pelo WhatsApp'),
                ),
            ],
          );
          final padding = EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.paddingOf(context).bottom,
          );
          if (wide) {
            return SingleChildScrollView(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 16,
                children: [
                  ...top,
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 16,
                    children: [
                      Expanded(
                        child: AppCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: itemsBlock,
                          ),
                        ),
                      ),
                      Expanded(
                        child: AppCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // The spacer that stood for the divider is not
                              // needed on top of a card.
                              if (moneyBlock.isNotEmpty &&
                                  moneyBlock.first is SizedBox)
                                ...moneyBlock.skip(1)
                              else
                                ...moneyBlock,
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  actions,
                ],
              ),
            );
          }
          return ListView(
            padding: padding,
            children: [
              ...top,
              const Divider(height: 32),
              ...itemsBlock,
              ...moneyBlock,
              const SizedBox(height: 16),
              actions,
            ],
          );
        },
      ),
    );
  }
}

/// The top of a sale: its situation, the client and the
/// date, and the amount that matters in evidence: what is left to receive,
/// with how much was paid, or the total.
class _Header extends StatelessWidget {
  const _Header({required this.sale, required this.status});

  final Sale sale;
  final SaleStatus status;

  @override
  Widget build(BuildContext context) {
    final s = sale;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = t.bodyMedium!.copyWith(color: scheme.onSurfaceVariant);
    final open = s.open;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                saleStatusPill(status),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${s.clientLabel} · ${saleDay(s.soldAt)}',
                    style: muted,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (s.canceled && s.cancelReason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Motivo: ${s.cancelReason}', style: muted),
              ),
            const SizedBox(height: 12),
            if (open > 0) ...[
              Text('Falta receber', style: muted),
              MoneyText(formatMoney(open)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: s.total == 0 ? 0 : (s.total - open) / s.total,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Pago ${formatMoney(s.total - open)} de ${formatMoney(s.total)}',
                style: muted.merge(tabular),
              ),
            ] else ...[
              Text('Total', style: muted),
              MoneyText(formatMoney(s.total)),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Venda registrada" with a check, in the "ok" situation color.
class _Done extends StatelessWidget {
  const _Done(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final (fg, _) = AppStatusColors.resolve(context, Situation.ok);
    return Row(
      children: [
        Icon(Symbols.check_circle_rounded, fill: 1, color: fg),
        const SizedBox(width: 8),
        Text(
          text,
          style: Theme.of(context).textTheme.titleMedium!.copyWith(color: fg),
        ),
      ],
    );
  }
}

/// Confirms a cancellation with an optional reason; pops with the
/// reason, or null when backing out.
class _CancelDialog extends StatefulWidget {
  const _CancelDialog({required this.number});

  final int number;

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Cancelar a venda nº ${widget.number}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 16,
        children: [
          const Text(
            'O estoque volta e os recebimentos ficam estornados. A venda '
            'continua na lista como cancelada.',
          ),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Voltar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _reason.text.trim()),
          child: const Text('Cancelar venda'),
        ),
      ],
    );
  }
}
