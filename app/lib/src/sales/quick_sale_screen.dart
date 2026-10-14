import 'package:flutter/material.dart';

import '../clients/clients_repository.dart';
import '../products/money.dart';
import '../products/pricing.dart';
import '../theme/form_parts.dart';
import '../theme/motion.dart';
import 'item_picker_screen.dart' show ClientPickerScreen;
import 'sale_math.dart';
import 'sale_screen.dart';
import 'sales_repository.dart';
import 'sales_screen.dart';

/// The description of a quick sale left blank.
const quickSaleLabel = 'Venda rápida';

/// The sale a quick sale becomes: one item
/// without a product, paid now with [method] or on credit due [due].
Sale quickSale({
  required int amount,
  required String description,
  required DateTime soldAt,
  int? clientId,
  PayMethod? method,
  String? due,
}) => Sale(
  clientId: clientId,
  soldAt: soldAt,
  items: [
    SaleItem(
      variantId: null,
      description: description.trim().isEmpty
          ? quickSaleLabel
          : description.trim(),
      isService: true,
      quantity: 1000,
      unitPrice: amount,
    ),
  ],
  payments: [
    if (due == null)
      SalePayment(method: method ?? PayMethod.pix, amount: amount, at: soldAt),
  ],
  installments: [
    if (due != null) Installment(number: 1, due: due, amount: amount),
  ],
);

/// Venda rápida: only the amount, an optional description
/// and client, and how it was paid: now, or on credit for a client. It
/// becomes a sale like any other, without moving stock.
class QuickSaleScreen extends StatefulWidget {
  const QuickSaleScreen({super.key, required this.ctx, this.client});

  final SaleContext ctx;

  /// Chosen already (from the client page or the new sale).
  final Client? client;

  @override
  State<QuickSaleScreen> createState() => _QuickSaleScreenState();
}

class _QuickSaleScreenState extends State<QuickSaleScreen> {
  SaleContext get ctx => widget.ctx;
  DateTime get _today => (ctx.clock ?? DateTime.now)();

  late Client? _client = widget.client;
  final _amount = TextEditingController();
  final _description = TextEditingController();
  late final _date = TextEditingController(text: saleDay(_today));
  late final _due = TextEditingController(
    text: saleDay(_today.add(const Duration(days: 30))),
  );
  bool _onCredit = false;
  var _method = PayMethod.pix;
  final _errors = <String, String>{};
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_amount, _description, _date, _due]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _chooseClient() async {
    final clients = ctx.clients;
    if (clients == null) return;
    final client = await Navigator.of(context).push<Client>(
      MaterialPageRoute(builder: (_) => ClientPickerScreen(clients: clients)),
    );
    if (client != null) setState(() => _client = client);
  }

  Future<void> _conclude() async {
    _errors.clear();
    final amount = parseMoney(_amount.text);
    if (amount == null || amount <= 0) _errors['amount'] = 'Digite o valor.';
    final iso = parseDay(_date.text);
    if (iso == null || iso.isEmpty) {
      _errors['date'] = 'Use dd/mm/aaaa.';
    } else if (iso.compareTo(isoDay(_today)) > 0) {
      _errors['date'] = 'A data não pode ser no futuro.';
    }
    String? due;
    if (_onCredit) {
      due = parseDay(_due.text);
      if (due == null || due.isEmpty) _errors['due'] = 'Use dd/mm/aaaa.';
      if (_client == null) {
        _errors['client'] = 'Fiado precisa de um cliente.';
      }
    }
    if (_errors.isNotEmpty) {
      Haptics.error();
      setState(() {});
      return;
    }
    setState(() => _saving = true);
    final now = _today;
    final [y, m, d] = iso!.split('-').map(int.parse).toList();
    final id = await ctx.sales.conclude(
      quickSale(
        amount: amount!,
        description: _description.text,
        soldAt: DateTime(y, m, d, now.hour, now.minute),
        clientId: _client?.id,
        method: _onCredit ? null : _method,
        due: _onCredit ? due : null,
      ),
    );
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SaleScreen(ctx: ctx, id: id, registered: true),
      ),
    );
  }

  Widget _field(
    String key,
    String label,
    TextEditingController controller, {
    TextInputType? keyboard,
    String? hint,
    bool autofocus = false,
  }) => TextField(
    controller: controller,
    keyboardType: keyboard,
    autofocus: autofocus,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: _errors[key],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Venda rápida'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _conclude,
            child: const Text('Concluir'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            MoneyField(
              controller: _amount,
              label: 'Valor',
              error: _errors['amount'],
              autofocus: true,
            ),
            _field(
              'description',
              'Descrição (opcional)',
              _description,
              hint: quickSaleLabel,
            ),
            // Wraps instead of overflowing with large text.
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  'Cliente: ${_client?.name ?? 'Consumidor final'}',
                  style: _errors['client'] == null
                      ? null
                      : TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                if (ctx.clients != null)
                  TextButton(
                    onPressed: _chooseClient,
                    child: const Text('Escolher cliente'),
                  ),
              ],
            ),
            if (_errors['client'] case final e?)
              Text(
                e,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            TextField(
              controller: _date,
              keyboardType: TextInputType.number,
              inputFormatters: [Masks.date],
              decoration: InputDecoration(
                labelText: 'Data da venda',
                errorText: _errors['date'],
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Pago agora')),
                ButtonSegment(value: true, label: Text('Fiado')),
              ],
              selected: {_onCredit},
              onSelectionChanged: (v) => setState(() => _onCredit = v.single),
            ),
            if (_onCredit)
              _field('due', 'Vence em', _due, keyboard: TextInputType.datetime)
            else
              DropdownButtonFormField<PayMethod>(
                initialValue: _method,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Forma'),
                items: [
                  for (final MapEntry(:key, :value) in payMethodLabels.entries)
                    DropdownMenuItem(value: key, child: Text(value)),
                ],
                onChanged: (m) => setState(() => _method = m!),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _conclude,
              child: const Text('Registrar venda'),
            ),
          ],
        ),
      ),
    );
  }
}
