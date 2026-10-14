import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../chats/chat_screen.dart';
import '../chats/chats_screen.dart';
import '../core_bridge/core_bridge.dart';
import '../home/crm_scope.dart';
import '../products/money.dart';
import '../products/products_repository.dart';
import '../sales/charge_message.dart';
import '../sales/receive_dialog.dart';
import '../sales/sale_form_screen.dart';
import '../sales/sale_screen.dart';
import '../sales/sales_repository.dart';
import '../sales/sales_screen.dart';
import '../theme/components.dart';
import 'client_form_screen.dart';
import 'client_summary.dart';
import 'client_timeline.dart';
import 'clients_controller.dart';
import 'clients_repository.dart';
import 'validation.dart';

/// "02/10/2026 09:05".
String noteTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
}

/// One client: who they are, what they owe and
/// bought, the actions and the story in a timeline,
/// the data and the WhatsApp block.
class ClientScreen extends StatefulWidget {
  const ClientScreen({
    super.key,
    required this.repo,
    required this.id,
    this.bridge,
    this.clock,
  });

  /// "Now", for what is overdue (tests).
  final DateTime Function()? clock;

  final ClientsRepository repo;
  final int id;

  /// The WhatsApp side, for the last messages and "Abrir conversa"
  ///; null hides the block.
  final CoreBridge? bridge;

  @override
  State<ClientScreen> createState() => _ClientScreenState();
}

class _ClientScreenState extends State<ClientScreen> {
  late final _controller = ClientController(repo: widget.repo, id: widget.id)
    ..load().then((_) => _findChat());
  final _note = TextEditingController();

  /// The client's sales; null without the sales (app.db opening, tests).
  SalesRepository? _salesRepo;
  ProductsRepository? _products;
  List<Sale>? _sales;

  /// The client's WhatsApp chat, or "".
  String _chat = '';

  /// How many timeline events show; "Ver mais" adds 20.
  int _shown = 20;

  DateTime get _today => (widget.clock ?? DateTime.now)();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final crm = CrmScope.maybeOf(context);
    final first = _salesRepo == null && crm?.sales != null;
    _salesRepo = crm?.sales;
    _products = crm?.products;
    if (first) _loadSales();
  }

  Future<void> _loadSales() async {
    final sales = await _salesRepo?.byClient(widget.id);
    if (mounted) setState(() => _sales = sales);
  }

  void _findChat() {
    final client = _controller.client;
    final bridge = widget.bridge;
    var chat = client?.chatJid ?? '';
    if (chat.isEmpty && client != null && bridge != null) {
      try {
        chat = bridge.chatForPhone(client.phone);
      } on CoreException {
        chat = ''; // WhatsApp not started
      }
    }
    if (mounted) setState(() => _chat = chat);
  }

  SaleContext? get _saleCtx => switch (_salesRepo) {
    final sales? => SaleContext(
      sales: sales,
      products: _products,
      clients: widget.repo,
      bridge: widget.bridge,
      clock: widget.clock,
    ),
    null => null,
  };

  Future<void> _push(Widget screen) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));

  ChatScreen _chatScreen(Client client, {String? draft}) => ChatScreen(
    bridge: widget.bridge!,
    chat: ChatSummary(jid: _chat, name: client.name, lastText: '', lastTs: 0),
    clients: widget.repo,
    draft: draft,
  );

  Future<void> _receive() async {
    final ok = await receiveFromClient(
      context,
      sales: _salesRepo!,
      clientId: widget.id,
      today: _today,
    );
    if (!ok || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Recebimento registrado.')));
    await _loadSales();
  }

  /// The conversation with the charge in the box; sending stays with the
  /// user.
  Future<void> _charge(Client client) async {
    final text = chargeMessage(
      name: client.name,
      sales: _sales ?? const [],
      today: _today,
    );
    if (text == null) return;
    await _push(_chatScreen(client, draft: text));
    await _controller.load(); // notes written in the conversation
  }

  Future<void> _openSale(Sale sale) async {
    final ctx = _saleCtx;
    if (ctx == null) return;
    await _push(SaleScreen(ctx: ctx, id: sale.id!));
    await _loadSales();
  }

  @override
  void dispose() {
    _controller.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _edit(Client client) async {
    await Navigator.of(context).push(
      MaterialPageRoute<int>(
        builder: (_) => ClientFormScreen(repo: widget.repo, initial: client),
      ),
    );
    await _controller.load();
    _findChat();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar cliente?'),
        content: const Text(
          'O cadastro, as anotações e as etiquetas serão apagados de vez. A '
          'conversa do WhatsApp continua, e as vendas ficam sem o nome.',
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
      await _controller.delete();
    } on ClientHasOpenSales catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Não dá para apagar'),
          content: Text(
            'Este cliente ainda tem ${formatMoney(e.open)} a receber. Receba '
            'ou cancele as vendas antes de apagar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendi'),
            ),
          ],
        ),
      );
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addNote() async {
    await _controller.addNote(_note.text);
    _note.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final client = _controller.client;
        if (client == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: _controller.loaded
                  ? const Text('Cliente não encontrado.')
                  : const CircularProgressIndicator(),
            ),
          );
        }
        final details = <(String, String)>[
          ('Telefone', formatPhone(client.phone)),
          ('E-mail', client.email),
          ('Endereço', client.fullAddress),
          ('CPF ou CNPJ', formatDocument(client.document)),
          ('Aniversário', formatBirthday(client.birthday)),
          ('Empresa', client.company),
          ('Etiquetas', client.tags.join(', ')),
        ];
        return Scaffold(
          appBar: AppBar(
            actions: [
              IconButton(
                tooltip: 'Editar',
                icon: const Icon(Symbols.edit_rounded),
                onPressed: () => _edit(client),
              ),
              IconButton(
                tooltip: 'Apagar cliente',
                icon: const Icon(Symbols.delete_rounded),
                onPressed: _delete,
              ),
            ],
          ),
          body: ListView(
            // Clear of the system's navigation buttons, so the last ones
            // ("Abrir conversa") can be tapped.
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              // Who it is, at a glance.
              Row(
                children: [
                  InitialsAvatar(client.name, size: 56),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          client.name,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        if (client.company.isNotEmpty)
                          Text(
                            client.company,
                            style: Theme.of(context).textTheme.bodyMedium!
                                .copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ..._top(context, client),
              const Divider(height: 32),
              ..._timeline(context),
              const Divider(height: 32),
              Text('Dados', style: Theme.of(context).textTheme.titleMedium),
              for (final (label, value) in details)
                if (value.isNotEmpty)
                  ListTile(
                    dense: true,
                    title: Text(label),
                    subtitle: Text(value),
                  ),
              if (widget.bridge case final bridge?) ...[
                const Divider(height: 32),
                _WhatsAppBlock(
                  bridge: bridge,
                  repo: widget.repo,
                  client: client,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// The numbers and the actions: Conversar, Nova venda, Receber and
  /// Cobrar.
  List<Widget> _top(BuildContext context, Client client) {
    final sales = _sales;
    final summary = sales == null ? null : ClientSummary.of(sales, _today);
    final owes = (summary?.owes ?? 0) > 0;
    final ctx = _saleCtx;
    final hasChat = _chat.isNotEmpty && widget.bridge != null;
    return [
      if (summary != null) ClientNumbers(summary),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (hasChat)
            FilledButton.tonalIcon(
              onPressed: () async {
                await _push(_chatScreen(client));
                await _controller.load();
              },
              icon: const Icon(Symbols.chat_rounded),
              label: const Text('Conversar'),
            ),
          if (ctx != null && ctx.products != null)
            FilledButton.icon(
              onPressed: () async {
                await _push(SaleFormScreen(ctx: ctx, client: client));
                await _loadSales();
              },
              icon: const Icon(Symbols.add_shopping_cart_rounded),
              label: const Text('Nova venda'),
            ),
          if (owes) ...[
            FilledButton.tonalIcon(
              onPressed: _receive,
              icon: const Icon(Symbols.payments_rounded),
              label: const Text('Receber'),
            ),
            OutlinedButton.icon(
              onPressed: hasChat ? () => _charge(client) : null,
              icon: const Icon(Symbols.request_quote_rounded),
              label: const Text('Cobrar'),
            ),
          ],
        ],
      ),
      if (owes && !hasChat)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Para cobrar pelo WhatsApp, o cliente precisa ter uma conversa '
            'com você.',
            style: Theme.of(context).textTheme.bodySmall!.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
    ];
  }

  /// Purchases, receipts, cancellations and notes, newest first, with the
  /// note field on top.
  List<Widget> _timeline(BuildContext context) {
    final sales = _sales ?? const <Sale>[];
    final events = buildTimeline(sales, _controller.notes);
    final ctx = _saleCtx;
    final client = _controller.client!;
    return [
      // The link goes under the title with large text.
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Linha do tempo',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (sales.isNotEmpty && ctx != null)
            TextButton(
              onPressed: () async {
                await _push(
                  ClientSalesScreen(
                    ctx: ctx,
                    clientId: widget.id,
                    clientName: client.name,
                  ),
                );
                await _loadSales();
              },
              child: const Text('Ver todas as compras'),
            ),
        ],
      ),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _note,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(hintText: 'Nova anotação'),
            ),
          ),
          TextButton(onPressed: _addNote, child: const Text('Anotar')),
        ],
      ),
      if (events.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Compras, recebimentos e anotações aparecem aqui.',
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      for (final e in events.take(_shown))
        TimelineTile(
          event: e,
          today: _today,
          noteTime: noteTime,
          onOpenSale: ctx == null ? null : _openSale,
          onDeleteNote: (n) => _controller.deleteNote(n.id),
        ),
      if (events.length > _shown)
        TextButton(
          onPressed: () => setState(() => _shown += 20),
          child: const Text('Ver mais'),
        ),
    ];
  }
}

/// The client's WhatsApp: the last 3 messages and "Abrir conversa"
/// The chat is the one the client was saved from, or the
/// one of their phone, also under a private ID (LID).
class _WhatsAppBlock extends StatelessWidget {
  const _WhatsAppBlock({
    required this.bridge,
    required this.repo,
    required this.client,
  });

  final CoreBridge bridge;
  final ClientsRepository repo;
  final Client client;

  String _chat() {
    if (client.chatJid case final jid?) return jid;
    try {
      return bridge.chatForPhone(client.phone);
    } on CoreException {
      return ''; // WhatsApp not started
    }
  }

  @override
  Widget build(BuildContext context) {
    final jid = _chat();
    var messages = const <ChatMessage>[];
    if (jid.isNotEmpty) {
      try {
        messages = bridge.listMessages(jid, limit: 3);
      } on CoreException {
        messages = const [];
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('WhatsApp', style: Theme.of(context).textTheme.titleMedium),
        if (jid.isEmpty)
          const Text('Sem conversa no WhatsApp')
        else ...[
          for (final m in messages)
            ListTile(
              dense: true,
              title: Text(
                m.fromMe ? 'Você: ${messageText(m)}' : messageText(m),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(shortTime(m.ts)),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ChatScreen(
                  bridge: bridge,
                  chat: ChatSummary(
                    jid: jid,
                    name: client.name,
                    lastText: '',
                    lastTs: 0,
                  ),
                  clients: repo,
                ),
              ),
            ),
            child: const Text('Abrir conversa'),
          ),
        ],
      ],
    );
  }
}
