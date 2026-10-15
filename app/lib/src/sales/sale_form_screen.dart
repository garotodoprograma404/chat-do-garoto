import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../clients/clients_repository.dart';
import '../products/money.dart';
import '../products/pricing.dart';
import '../products/products_repository.dart';
import '../scan/barcode_scanner.dart';
import '../theme/components.dart';
import '../theme/form_parts.dart';
import '../theme/motion.dart';
import 'item_picker_screen.dart';
import 'quick_sale_screen.dart';
import 'sale_math.dart';
import 'sale_screen.dart';
import 'sales_repository.dart';
import 'sales_screen.dart';

const _decimal = TextInputType.numberWithOptions(decimal: true);

/// An item being added to the sale.
class _ItemDraft {
  _ItemDraft(this.product, this.variant);

  final Product product;
  final Variant variant;
  final quantity = TextEditingController(text: '1');
  final price = TextEditingController();
  final discount = TextEditingController();

  /// Typed by hand: the quantity no longer changes it.
  bool priceEdited = false;

  String get description => variant.label.isEmpty
      ? product.name
      : '${product.name} (${variant.label})';

  int get qty => parseQuantity(quantity.text, product.unit) ?? 0;
  int get unitPrice => parseMoney(price.text) ?? 0;
  int get gross => timesQuantity(qty, unitPrice);
  int get off => parseDiscount(discount.text, gross) ?? 0;
  int get total => gross - off;

  void dispose() {
    quantity.dispose();
    price.dispose();
    discount.dispose();
  }
}

class _InstallmentDraft {
  _InstallmentDraft(Installment i)
    : number = i.number,
      due = TextEditingController(text: formatDay(i.due)),
      amount = moneyController(i.amount);

  final int number;
  final TextEditingController due, amount;

  void dispose() {
    due.dispose();
    amount.dispose();
  }
}

/// A new sale: client, items, discounts, freight and payments. On success it shows the sale.
class SaleFormScreen extends StatefulWidget {
  const SaleFormScreen({super.key, required this.ctx, this.client, this.item});

  final SaleContext ctx;

  /// Chosen already (from the client page).
  final Client? client;

  /// The first item (from a product's page).
  final (Product, Variant)? item;

  @override
  State<SaleFormScreen> createState() => _SaleFormScreenState();
}

class _SaleFormScreenState extends State<SaleFormScreen> {
  SaleContext get ctx => widget.ctx;
  DateTime get _today => (ctx.clock ?? DateTime.now)();

  late Client? _client = widget.client;
  late final _date = TextEditingController(text: saleDay(_today));
  final _items = <_ItemDraft>[];
  final _discount = TextEditingController();
  final _freight = TextEditingController();
  final _note = TextEditingController();
  // "Como vai pagar?": one way for the whole total, or
  // several ("Dividir em mais de uma forma").
  PayMethod? _choice;
  bool _fiado = false;
  bool _otherOpen = false;
  bool _splitCredit = false;
  bool _split = false;
  bool _detailsOpen = false;
  final _received = TextEditingController();

  // Divided: the payments and installments.
  final _payments = <SalePayment>[];
  PayMethod _method = PayMethod.pix;
  final _payAmount = TextEditingController();
  final _count = TextEditingController(text: '1');
  late final _firstDue = TextEditingController(text: _autoFirstDue);

  /// The first installment's default: 30 days after the sale date. It
  /// follows the date until the user types another one.
  late String _autoFirstDue = saleDay(_today.add(const Duration(days: 30)));
  final _installments = <_InstallmentDraft>[];
  final _errors = <String, String>{};
  String? _change;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_discount, _freight, _received, _count, _firstDue]) {
      c.addListener(() => setState(() {}));
    }
    _date.addListener(_followDate);
    if (widget.item case (final product, final variant)) {
      _items.add(_draft(product, variant));
    }
  }

  /// A sale typed with an earlier date gets its first installment 30 days
  /// after that date, not after today.
  void _followDate() {
    final iso = parseDay(_date.text);
    if (iso == null || _firstDue.text != _autoFirstDue) return;
    final [y, m, d] = iso.split('-').map(int.parse).toList();
    _autoFirstDue = saleDay(DateTime(y, m, d).add(const Duration(days: 30)));
    _firstDue.text = _autoFirstDue;
  }

  @override
  void dispose() {
    for (final c in [
      _date,
      _discount,
      _freight,
      _note,
      _received,
      _payAmount,
      _count,
      _firstDue,
    ]) {
      c.dispose();
    }
    for (final i in _items) {
      i.dispose();
    }
    for (final i in _installments) {
      i.dispose();
    }
    super.dispose();
  }

  // --- Totals ---------------------------------------------------------

  /// The day of the sale, for prices; today while the date is invalid.
  DateTime get _saleDay {
    final iso = parseDay(_date.text);
    if (iso == null || iso.isEmpty) return _today;
    final [y, m, d] = iso.split('-').map(int.parse).toList();
    return DateTime(y, m, d);
  }

  int get _itemsTotal => _items.fold(0, (sum, i) => sum + i.total);
  int get _saleDiscount => parseDiscount(_discount.text, _itemsTotal) ?? 0;
  int get _freightValue => parseMoney(_freight.text) ?? 0;
  int get _total => _itemsTotal - _saleDiscount + _freightValue;
  int get _paid => _payments.fold(0, (sum, p) => sum + p.amount);
  int get _credit =>
      _installments.fold(0, (sum, i) => sum + (parseMoney(i.amount.text) ?? 0));
  int get _left => _total - _paid - _credit;
  int get _cost =>
      _items.fold(0, (sum, i) => sum + timesQuantity(i.qty, i.variant.cost));

  // --- Items ----------------------------------------------------------

  void _reprice(_ItemDraft i) {
    if (i.priceEdited) return;
    final qty = i.qty == 0 ? 1000 : i.qty;
    i.price.text = formatMoney(
      i.product.priceOf(i.variant, _saleDay, quantity: qty),
    );
  }

  Future<void> _addItem() async {
    final products = ctx.products;
    if (products == null) return;
    final picked = await Navigator.of(context).push<(Product, Variant)>(
      MaterialPageRoute(
        builder: (_) => ItemPickerScreen(products: products, clock: ctx.clock),
      ),
    );
    if (picked == null || !mounted) return;
    _append(picked.$1, picked.$2);
  }

  _ItemDraft _append(Product product, Variant variant) {
    final item = _draft(product, variant);
    setState(() => _items.add(item));
    return item;
  }

  _ItemDraft _draft(Product product, Variant variant) {
    final item = _ItemDraft(product, variant);
    _reprice(item);
    item.quantity.addListener(() => setState(() => _reprice(item)));
    item.discount.addListener(() => setState(() {}));
    return item;
  }

  /// "Ler código": the camera stays open and each code adds
  /// its item, or one more of it.
  Future<void> _scanItems() async {
    final products = ctx.products;
    final scanner = barcodeScanner;
    if (products == null || scanner == null) return;
    final all = await products.list();
    if (!mounted) return;
    await scanner.scanMany(
      context,
      onCode: (code) async => _addScanned(productByCode(all, code)),
    );
  }

  /// Adds what a code found and says what happened.
  String _addScanned(({Product product, Variant? variant})? found) {
    if (found == null) return 'Código não cadastrado';
    final (:product, :variant) = found;
    if (!product.active || (variant != null && !variant.active)) {
      return '${product.name} está inativo';
    }
    if (variant == null) {
      return '${product.name} tem variações: escolha em "Adicionar item"';
    }
    final i = _items.indexWhere((d) => d.variant.id == variant.id);
    final item = i < 0 ? _append(product, variant) : _items[i];
    if (i >= 0) item.quantity.text = formatQuantity(item.qty + 1000);
    return '${item.description}: ${formatQuantity(item.qty)} ${product.unit}';
  }

  Future<void> _chooseClient() async {
    final clients = ctx.clients;
    if (clients == null) return;
    final client = await Navigator.of(context).push<Client>(
      MaterialPageRoute(builder: (_) => ClientPickerScreen(clients: clients)),
    );
    if (client != null) setState(() => _client = client);
  }

  // --- Payments -------------------------------------------------------

  void _addPayment() {
    _errors.remove('payment');
    _change = null;
    final due = _left;
    final typed = _payAmount.text.trim().isEmpty
        ? due
        : parseMoney(_payAmount.text);
    if (typed == null || typed <= 0 || due <= 0) {
      setState(() => _errors['payment'] = 'Nada a pagar ou valor inválido.');
      return;
    }
    var amount = typed;
    if (_method == PayMethod.cash) {
      final cash = cashPayment(typed, due);
      amount = cash.recorded;
      if (cash.change > 0) _change = 'Troco: ${formatMoney(cash.change)}';
    } else if (typed > due) {
      setState(() => _errors['payment'] = 'Maior que o que falta.');
      return;
    }
    setState(() {
      _payments.add(SalePayment(method: _method, amount: amount, at: _saleDay));
      _payAmount.clear();
    });
  }

  void _splitRest() {
    _errors.remove('credit');
    final count = int.tryParse(_count.text.trim());
    final first = parseDay(_firstDue.text);
    final rest = _total - _paid;
    if (count == null || count < 1 || count > 24) {
      setState(() => _errors['credit'] = 'De 1 a 24 parcelas.');
      return;
    }
    if (first == null || first.isEmpty) {
      setState(() => _errors['credit'] = 'Primeiro vencimento: dd/mm/aaaa.');
      return;
    }
    if (rest <= 0) {
      setState(() => _errors['credit'] = 'Nada a parcelar.');
      return;
    }
    final [y, m, d] = first.split('-').map(int.parse).toList();
    setState(() {
      for (final i in _installments) {
        i.dispose();
      }
      _installments
        ..clear()
        ..addAll([
          for (final i in splitInstallments(rest, count, DateTime(y, m, d)))
            _InstallmentDraft(i)..amount.addListener(() => setState(() {})),
        ]);
    });
  }

  // --- Concluding -----------------------------------------------------

  static const _others = [
    PayMethod.transfer,
    PayMethod.boleto,
    PayMethod.cheque,
    PayMethod.other,
  ];

  /// What a cash payment received: the total when left blank.
  int? get _receivedValue =>
      _received.text.trim().isEmpty ? _total : parseMoney(_received.text);

  /// The installments of a sale on credit ("Fiado"): one, or "Parcelar" in
  /// [_count], monthly from [_firstDue]; null while invalid.
  List<Installment>? get _fiadoInstallments {
    final count = _splitCredit ? int.tryParse(_count.text.trim()) : 1;
    final first = parseDay(_firstDue.text);
    if (count == null || count < 1 || count > 24) return null;
    if (first == null || first.isEmpty || _total <= 0) return null;
    final [y, m, d] = first.split('-').map(int.parse).toList();
    return splitInstallments(_total, count, DateTime(y, m, d));
  }

  void _choose(PayMethod method) => setState(() {
    _errors.remove('pay');
    _choice = method;
    _fiado = false;
    _otherOpen = _others.contains(method);
  });

  void _chooseFiado() => setState(() {
    _errors.remove('pay');
    _choice = null;
    _fiado = true;
    _otherOpen = false;
  });

  /// The payments and installments of one way for the whole total.
  (List<SalePayment>, List<Installment>)? _single(DateTime at) {
    if (_fiado) {
      if (_client == null) _errors['client'] = 'Fiado precisa de um cliente.';
      final installments = _fiadoInstallments;
      if (installments == null) {
        _errors['credit'] = _splitCredit
            ? 'De 1 a 24 parcelas, com o vencimento em dd/mm/aaaa.'
            : 'Vencimento: dd/mm/aaaa.';
        return null;
      }
      return (const <SalePayment>[], installments);
    }
    final method = _choice;
    if (method == null) {
      _errors['pay'] = 'Escolha como vai pagar.';
      return null;
    }
    if (method == PayMethod.cash) {
      final received = _receivedValue;
      if (received == null || received < _total) {
        _errors['cash'] =
            'Menor que o total. Para o resto, use Fiado ou Dividir em mais '
            'de uma forma.';
        return null;
      }
    }
    return (
      [if (_total > 0) SalePayment(method: method, amount: _total, at: at)],
      const <Installment>[],
    );
  }

  /// The payments and installments typed one by one.
  (List<SalePayment>, List<Installment>)? _dividedPaid(DateTime at) {
    final installments = <Installment>[];
    for (final i in _installments) {
      final due = parseDay(i.due.text);
      final amount = parseMoney(i.amount.text);
      if (due == null || due.isEmpty || amount == null || amount <= 0) {
        _errors['credit'] = 'Confira as datas e os valores das parcelas.';
        continue;
      }
      installments.add(Installment(number: i.number, due: due, amount: amount));
    }
    if (installments.isNotEmpty && _client == null) {
      _errors['client'] = 'Venda a prazo precisa de um cliente.';
    }
    if (_errors.isEmpty && _left != 0) {
      _errors['left'] = _left > 0
          ? 'Falta ${formatMoney(_left)}: adicione um pagamento ou parcele.'
          : 'Os pagamentos passam do total em ${formatMoney(-_left)}.';
    }
    return (
      [
        for (final p in _payments)
          SalePayment(method: p.method, amount: p.amount, at: at),
      ],
      installments,
    );
  }

  Future<void> _conclude() async {
    _errors.clear();
    final iso = parseDay(_date.text);
    if (iso == null || iso.isEmpty) {
      _errors['date'] = 'Use dd/mm/aaaa.';
    } else if (iso.compareTo(isoDay(_today)) > 0) {
      _errors['date'] = 'A data não pode ser no futuro.';
    }
    if (_items.isEmpty) _errors['items'] = 'Adicione pelo menos um item.';
    for (final (n, i) in _items.indexed) {
      final gross = i.gross;
      if (i.qty <= 0) _errors['qty$n'] = 'Quantidade inválida.';
      if (parseMoney(i.price.text) == null) {
        _errors['price$n'] = 'Valor inválido.';
      }
      final off = parseDiscount(i.discount.text, gross);
      if (off == null || off > gross) {
        _errors['discount$n'] = 'Desconto inválido.';
      }
    }
    final off = parseDiscount(_discount.text, _itemsTotal);
    if (off == null || off > _itemsTotal) {
      _errors['discount'] = 'Desconto inválido.';
    }
    if (_freight.text.trim().isNotEmpty && parseMoney(_freight.text) == null) {
      _errors['freight'] = 'Valor inválido.';
    }
    final now = _today;
    final soldAt = switch (iso?.split('-').map(int.parse).toList()) {
      [final y, final m, final d] => DateTime(y, m, d, now.hour, now.minute),
      _ => now,
    };
    final paid = _items.isEmpty
        ? null
        : _split
        ? _dividedPaid(soldAt)
        : _single(soldAt);
    if (_errors.isNotEmpty || paid == null) {
      // An error in "Mais detalhes" opens it.
      if (const ['date', 'discount', 'freight'].any(_errors.containsKey)) {
        _detailsOpen = true;
      }
      Haptics.error();
      setState(() {});
      return;
    }
    if (!await _confirmNegativeStock()) return;

    setState(() => _saving = true);
    final (payments, installments) = paid;
    final id = await ctx.sales.conclude(
      Sale(
        clientId: _client?.id,
        soldAt: soldAt,
        items: [
          for (final i in _items)
            SaleItem(
              variantId: i.variant.id!,
              description: i.description,
              unit: i.product.unit,
              isService: i.product.isService,
              quantity: i.qty,
              unitPrice: i.unitPrice,
              discount: i.off,
            ),
        ],
        discount: _saleDiscount,
        freight: _freightValue,
        note: _note.text.trim(),
        payments: payments,
        installments: installments,
      ),
    );
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SaleScreen(ctx: ctx, id: id, registered: true),
      ),
    );
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descartar a venda?'),
        content: const Text(
          'Os itens e pagamentos preenchidos serão perdidos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuar a venda'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Stock may go negative after a warning.
  Future<bool> _confirmNegativeStock() async {
    final sold = <int, (_ItemDraft, int)>{};
    for (final i in _items) {
      if (i.product.isService) continue;
      final before = sold[i.variant.id!]?.$2 ?? 0;
      sold[i.variant.id!] = (i, before + i.qty);
    }
    final negative = [
      for (final (i, qty) in sold.values)
        if (i.variant.stock - qty < 0)
          '${i.description}: ${formatQuantity(i.variant.stock - qty)} '
              '${i.product.unit}',
    ];
    if (negative.isEmpty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Estoque negativo'),
        content: Text(
          'Estes itens vão ficar com estoque negativo:\n'
          '${negative.join('\n')}\nConcluir mesmo assim?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Concluir'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // --- Layout ---------------------------------------------------------

  Widget _field(
    String key,
    String label,
    TextEditingController c, {
    TextInputType? keyboard,
    String? hint,
    bool money = false,
    bool date = false,
  }) => TextField(
    controller: c,
    keyboardType: money || date ? TextInputType.number : keyboard,
    // Money shows "R$ 12,90" while typed.
    inputFormatters: [
      if (money) Masks.money,
      if (date) Masks.date,
      if (keyboard == _decimal) Masks.decimal,
    ],
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: _errors[key],
    ),
  );

  Widget _error(String key) => switch (_errors[key]) {
    final e? => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        e,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ),
    null => const SizedBox.shrink(),
  };

  /// Two fields side by side, one under the other with large text
  ///: nothing is cut.
  Widget _pair(Widget a, Widget b) {
    if (largeText(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [a, b],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Expanded(child: a),
        Expanded(child: b),
      ],
    );
  }

  Widget _muted(String text) => Text(
    text,
    style: Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
  );

  /// An item in two lines of fields: quantity and price, then the discount
  /// and the item's total.
  Widget _item(int n, _ItemDraft i) => Card(
    key: ObjectKey(i),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  i.description,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'Tirar ${i.description}',
                icon: const Icon(Symbols.close_rounded),
                onPressed: () => setState(() {
                  _items.remove(i);
                  i.dispose();
                }),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                _pair(
                  _field(
                    'qty$n',
                    'Qtd. (${i.product.unit})',
                    i.quantity,
                    keyboard: _decimal,
                  ),
                  TextField(
                    controller: i.price,
                    keyboardType: TextInputType.number,
                    inputFormatters: [Masks.money],
                    onChanged: (_) => setState(() => i.priceEdited = true),
                    decoration: InputDecoration(
                      labelText: 'Preço',
                      errorText: _errors['price$n'],
                    ),
                  ),
                ),
                _pair(
                  _field(
                    'discount$n',
                    'Desconto',
                    i.discount,
                    hint: 'R\$ ou %',
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Total do item: ${formatMoney(i.total)}',
                      textAlign: TextAlign.end,
                      style: tabular,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  /// "Como vai pagar?": one tap for the whole total.
  List<Widget> _payChoice() {
    final total = _total;
    final received = _receivedValue;
    final change = _choice == PayMethod.cash && received != null
        ? cashPayment(received, total).change
        : 0;
    final fiado = _fiado ? _fiadoInstallments : null;
    ChoiceChip chip(String label, bool selected, VoidCallback onTap) =>
        ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        );
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (label, m) in const [
            ('Pix', PayMethod.pix),
            ('Dinheiro', PayMethod.cash),
            ('Débito', PayMethod.debit),
            ('Crédito', PayMethod.credit),
          ])
            chip(label, _choice == m, () => _choose(m)),
          chip('Fiado', _fiado, _chooseFiado),
          chip(
            'Outra forma',
            _otherOpen,
            () => setState(() {
              _otherOpen = true;
              _fiado = false;
              if (!_others.contains(_choice)) _choice = null;
            }),
          ),
        ],
      ),
      _error('pay'),
      if (_otherOpen) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in _others)
              chip(payMethodLabels[m]!, _choice == m, () => _choose(m)),
          ],
        ),
      ],
      if (_choice == PayMethod.cash) ...[
        const SizedBox(height: 12),
        MoneyField(
          controller: _received,
          label: 'Valor recebido',
          hint: formatMoney(total),
          error: _errors['cash'],
        ),
        if (change > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Troco: ${formatMoney(change)}',
              style: Theme.of(context).textTheme.titleMedium!.merge(tabular),
            ),
          ),
      ],
      if (_fiado) ...[
        const SizedBox(height: 12),
        if (_client == null)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              _muted('Fiado precisa de um cliente.'),
              if (ctx.clients != null)
                TextButton(
                  onPressed: _chooseClient,
                  child: const Text('Escolher cliente'),
                ),
            ],
          ),
        _field(
          'firstDue',
          _splitCredit ? '1º vencimento' : 'Vence em',
          _firstDue,
          date: true,
        ),
        if (!_splitCredit)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _splitCredit = true;
                if (_count.text.trim() == '1') _count.text = '2';
              }),
              icon: const Icon(Symbols.event_repeat_rounded),
              label: const Text('Parcelar'),
            ),
          )
        else ...[
          const SizedBox(height: 8),
          _field('count', 'Parcelas', _count, keyboard: TextInputType.number),
          for (final i in fiado ?? const <Installment>[])
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${i.number}ª · vence ${formatDay(i.due)} · '
                '${formatMoney(i.amount)}',
                style: tabular,
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _splitCredit = false),
              child: const Text('Uma parcela só'),
            ),
          ),
        ],
        _error('credit'),
      ],
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() {
            _split = true;
            _errors.remove('pay');
          }),
          icon: const Icon(Symbols.call_split_rounded),
          label: const Text('Dividir em mais de uma forma'),
        ),
      ),
    ];
  }

  /// Several payments and installments: an entry in cash and
  /// the rest in installments, for example.
  List<Widget> _divided() {
    final left = _left;
    return [
      for (final p in _payments)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${payMethodLabels[p.method]} ${formatMoney(p.amount)}'),
          trailing: IconButton(
            tooltip: 'Tirar pagamento',
            icon: const Icon(Symbols.close_rounded),
            onPressed: () => setState(() => _payments.remove(p)),
          ),
        ),
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
      const SizedBox(height: 8),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: MoneyField(
              controller: _payAmount,
              label: 'Valor',
              hint: left > 0 ? formatMoney(left) : null,
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: FilledButton.tonal(
              onPressed: _addPayment,
              child: const Text('Adicionar'),
            ),
          ),
        ],
      ),
      _error('payment'),
      if (_change case final change?)
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(change)),
      const SizedBox(height: 16),
      Text('A prazo', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      _pair(
        _field('count', 'Parcelas', _count, keyboard: TextInputType.number),
        _field('firstDue', '1º vencimento', _firstDue, date: true),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: _splitRest,
          child: const Text('Parcelar o resto'),
        ),
      ),
      for (final i in _installments)
        Padding(
          key: ObjectKey(i),
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 4,
            children: [
              Text('${i.number}ª parcela'),
              _pair(
                TextField(
                  controller: i.due,
                  keyboardType: TextInputType.number,
                  inputFormatters: [Masks.date],
                  decoration: const InputDecoration(labelText: 'Vence'),
                ),
                TextField(
                  controller: i.amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [Masks.money],
                  decoration: const InputDecoration(labelText: 'Valor'),
                ),
              ),
            ],
          ),
        ),
      if (_installments.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() {
              for (final i in _installments) {
                i.dispose();
              }
              _installments.clear();
            }),
            child: const Text('Tirar parcelas'),
          ),
        ),
      _error('credit'),
      const SizedBox(height: 8),
      Text(
        left == 0
            ? 'Pagamento completo.'
            : left > 0
            ? 'Falta ${formatMoney(left)}'
            : 'Passou ${formatMoney(-left)}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      _error('left'),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() {
            _split = false;
            _payments.clear();
            for (final i in _installments) {
              i.dispose();
            }
            _installments.clear();
            _errors.remove('left');
          }),
          icon: const Icon(Symbols.undo_rounded),
          label: const Text('Voltar para uma forma só'),
        ),
      ),
    ];
  }

  /// Desconto, frete, data e observação, closed, with a summary.
  Widget _details() {
    final today = saleDay(_today);
    final summary = [
      if (_saleDiscount > 0) 'Desconto ${formatMoney(_saleDiscount)}',
      if (_freightValue > 0) 'Frete ${formatMoney(_freightValue)}',
      if (_date.text != today) 'Data ${_date.text}',
      if (_note.text.trim().isNotEmpty) 'Observação',
    ];
    return DetailsGroup(
      title: 'Mais detalhes',
      icon: Symbols.tune_rounded,
      summary: summary.isEmpty
          ? 'Desconto, frete, data e observação'
          : summary.join(' · '),
      open: _detailsOpen,
      onToggle: () => setState(() => _detailsOpen = !_detailsOpen),
      children: [
        FormPair(
          first: _field(
            'discount',
            'Desconto no total',
            _discount,
            hint: 'R\$ ou %',
          ),
          second: _field('freight', 'Frete', _freight, money: true),
        ),
        _field('date', 'Data da venda', _date, date: true),
        _field('note', 'Observação', _note),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = Theme.of(context).textTheme.titleMedium;
    // The back key would throw away a sale being filled in.
    return PopScope(
      canPop: _items.isEmpty && _payments.isEmpty && _installments.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !await _confirmDiscard()) return;
        if (context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Nova venda')),
        // The items and the total always in sight, with "Concluir".
        bottomNavigationBar: _TotalBar(
          items: _items.length,
          total: _total,
          onConclude: _saving ? null : _conclude,
        ),
        // A column, not a lazy list: rows come and go while typing.
        body: FormBody(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Only the amount? The quick sale.
                if (_items.isEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              QuickSaleScreen(ctx: ctx, client: _client),
                        ),
                      ),
                      icon: const Icon(Symbols.bolt_rounded),
                      label: const Text('Só o valor? Venda rápida'),
                    ),
                  ),
                // Wraps instead of overflowing with large text.
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  children: [
                    Text('Cliente: ${_client?.name ?? 'Consumidor final'}'),
                    if (ctx.clients != null)
                      TextButton(
                        onPressed: _chooseClient,
                        child: const Text('Escolher cliente'),
                      ),
                    if (_client != null)
                      IconButton(
                        tooltip: 'Tirar cliente',
                        icon: const Icon(Symbols.close_rounded),
                        onPressed: () => setState(() => _client = null),
                      ),
                  ],
                ),
                _error('client'),
                const SizedBox(height: 8),
                Text('Itens', style: title),
                const SizedBox(height: 4),
                for (final (n, i) in _items.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _item(n, i),
                  ),
                _error('items'),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _addItem,
                      icon: const Icon(Symbols.add_rounded),
                      label: const Text('Adicionar item'),
                    ),
                    if (barcodeScanner != null)
                      TextButton.icon(
                        onPressed: _scanItems,
                        icon: const Icon(Symbols.barcode_scanner_rounded),
                        label: const Text('Ler código'),
                      ),
                  ],
                ),
                if (_items.isNotEmpty)
                  _muted(
                    [
                      'Itens ${formatMoney(_itemsTotal)}',
                      if (_saleDiscount > 0)
                        'desconto ${formatMoney(_saleDiscount)}',
                      if (_freightValue > 0)
                        'frete ${formatMoney(_freightValue)}',
                      'lucro ${formatMoney(_itemsTotal - _saleDiscount - _cost)}',
                    ].join(' · '),
                  ),
                const SizedBox(height: 16),
                Text('Como vai pagar?', style: title),
                const SizedBox(height: 8),
                if (_split) ..._divided() else ..._payChoice(),
                const SizedBox(height: 8),
                _details(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The bar under the new sale: how many items, the total
/// and "Concluir".
class _TotalBar extends StatelessWidget {
  const _TotalBar({
    required this.items,
    required this.total,
    required this.onConclude,
  });

  final int items;
  final int total;
  final VoidCallback? onConclude;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: colors.onSurfaceVariant);
    return Material(
      color: colors.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plural(items, 'item', 'itens'), style: muted),
                    MoneyText(formatMoney(total), small: true),
                  ],
                ),
              ),
              FilledButton(
                onPressed: onConclude,
                child: const Text('Concluir'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
