import 'package:flutter/material.dart';

import '../clients/client_screen.dart' show noteTime;
import '../theme/form_parts.dart';
import 'money.dart';
import 'pricing.dart';
import 'products_repository.dart';
import 'products_screen.dart';

/// Why stock leaves without a sale.
const exitReasons = [
  'Perda',
  'Quebra',
  'Uso próprio',
  'Brinde',
  'Devolução ao fornecedor',
  'Outro',
];

const _decimal = TextInputType.numberWithOptions(decimal: true);

/// An entry, exit or count of one variation. Pops
/// with true when saved.
class StockMoveScreen extends StatefulWidget {
  const StockMoveScreen({super.key, required this.repo, required this.product});

  final ProductsRepository repo;
  final Product product;

  @override
  State<StockMoveScreen> createState() => _StockMoveScreenState();
}

class _StockMoveScreenState extends State<StockMoveScreen> {
  Product get p => widget.product;
  late Variant _variant = p.activeVariants.firstOrNull ?? p.variants.first;
  MoveKind _kind = MoveKind.entry;
  String? _reason;
  final _quantity = TextEditingController();
  final _unitCost = TextEditingController();
  final _note = TextEditingController();
  final _errors = <String, String>{};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_quantity, _unitCost]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _quantity.dispose();
    _unitCost.dispose();
    _note.dispose();
    super.dispose();
  }

  int? _balance(int quantity) => switch (_kind) {
    MoveKind.entry => _variant.stock + quantity,
    MoveKind.exit => _variant.stock - quantity,
    MoveKind.count => quantity,
    MoveKind.initial || MoveKind.sale || MoveKind.saleCancel => null,
  };

  Future<void> _confirm() async {
    _errors.clear();
    final quantity = parseQuantity(_quantity.text, p.unit);
    if (quantity == null) {
      _errors['quantity'] = fractional(p.unit)
          ? 'Digite a quantidade.'
          : 'Digite a quantidade, só números inteiros em ${p.unit}.';
    } else if (quantity == 0 && _kind != MoveKind.count) {
      _errors['quantity'] = 'A quantidade precisa ser maior que zero.';
    }
    int? unitCost;
    if (_kind == MoveKind.entry && _unitCost.text.trim().isNotEmpty) {
      unitCost = parseMoney(_unitCost.text);
      if (unitCost == null) _errors['unitCost'] = 'Valor inválido.';
    }
    if (_kind == MoveKind.exit && _reason == null) {
      _errors['reason'] = 'Escolha o motivo.';
    }
    if (_errors.isNotEmpty) {
      setState(() {});
      return;
    }
    final balance = _balance(quantity!)!;
    if (balance < 0 && !await _confirmNegative(balance)) return;
    setState(() => _saving = true);
    await widget.repo.move(
      _variant.id!,
      _kind,
      quantity,
      unitCost: unitCost,
      reason: _kind == MoveKind.exit ? _reason! : '',
      note: _note.text.trim(),
    );
    if (mounted) Navigator.pop(context, true);
  }

  /// Negative stock is allowed after a warning.
  Future<bool> _confirmNegative(int balance) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Estoque negativo'),
        content: Text(
          'O estoque vai ficar em ${stockText(balance, p.unit)}. Confirmar '
          'mesmo assim?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Registrar mesmo assim'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  String? _preview() {
    final quantity = parseQuantity(_quantity.text, p.unit);
    if (quantity == null) return null;
    final balance = _balance(quantity);
    if (balance == null) return null;
    final parts = ['Estoque depois: ${stockText(balance, p.unit)}'];
    final unitCost = parseMoney(_unitCost.text);
    if (_kind == MoveKind.entry && unitCost != null && quantity > 0) {
      final cost = averageCost(
        stock: _variant.stock,
        cost: _variant.cost,
        quantity: quantity,
        unitCost: unitCost,
      );
      parts.add('custo médio ${formatMoney(cost)}');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Movimentar estoque'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _confirm,
            child: const Text('Registrar'),
          ),
        ],
      ),
      // A column, not a lazy list: fields that come and go must not move
      // the focus to another field.
      body: FormBody(
        child: SingleChildScrollView(
          // Content drawn behind the system navigation bar must scroll above
          // it (edge to edge on Android).
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(p.name, style: Theme.of(context).textTheme.titleMedium),
              if (p.hasVariants)
                DropdownButtonFormField<int>(
                  initialValue: _variant.id,
                  decoration: const InputDecoration(labelText: 'Variação'),
                  items: [
                    for (final v in p.variants)
                      DropdownMenuItem(
                        value: v.id,
                        child: Text(
                          '${v.label} (${stockText(v.stock, p.unit)})',
                        ),
                      ),
                  ],
                  onChanged: (id) => setState(
                    () => _variant = p.variants.firstWhere((v) => v.id == id),
                  ),
                ),
              Text(
                'Estoque atual: ${stockText(_variant.stock, p.unit)} · custo '
                '${formatMoney(_variant.cost)}',
              ),
              const SizedBox(height: 8),
              SegmentedButton<MoveKind>(
                segments: const [
                  ButtonSegment(value: MoveKind.entry, label: Text('Entrada')),
                  ButtonSegment(value: MoveKind.exit, label: Text('Saída')),
                  ButtonSegment(value: MoveKind.count, label: Text('Balanço')),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.single),
              ),
              TextField(
                controller: _quantity,
                keyboardType: _decimal,
                inputFormatters: [Masks.decimal],
                decoration: InputDecoration(
                  labelText: _kind == MoveKind.count
                      ? 'Quantidade contada (${p.unit})'
                      : 'Quantidade (${p.unit})',
                  errorText: _errors['quantity'],
                ),
              ),
              if (_kind == MoveKind.entry)
                TextField(
                  controller: _unitCost,
                  keyboardType: TextInputType.number,
                  inputFormatters: [Masks.money],
                  decoration: InputDecoration(
                    labelText: 'Custo unitário (opcional)',
                    errorText: _errors['unitCost'],
                  ),
                ),
              if (_kind == MoveKind.exit) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  children: [
                    for (final r in exitReasons)
                      ChoiceChip(
                        label: Text(r),
                        selected: _reason == r,
                        onSelected: (_) => setState(() => _reason = r),
                      ),
                  ],
                ),
                if (_errors['reason'] case final e?)
                  Text(
                    e,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
              TextField(
                controller: _note,
                decoration: const InputDecoration(labelText: 'Observação'),
              ),
              if (preview != null) ...[
                const SizedBox(height: 8),
                Text(preview),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// How a movement shows in the history.
String moveLabel(MoveKind kind, [int? sale]) => switch (kind) {
  MoveKind.initial => 'Estoque inicial',
  MoveKind.entry => 'Entrada',
  MoveKind.exit => 'Saída',
  MoveKind.count => 'Balanço',
  MoveKind.sale => 'Venda nº $sale',
  MoveKind.saleCancel => 'Cancelamento da venda nº $sale',
};

/// The product's movements, newest first, with the balance.
class StockHistoryScreen extends StatelessWidget {
  const StockHistoryScreen({
    super.key,
    required this.repo,
    required this.product,
  });

  final ProductsRepository repo;
  final Product product;

  @override
  Widget build(BuildContext context) {
    final unit = product.unit;
    return Scaffold(
      appBar: AppBar(title: Text('Histórico: ${product.name}')),
      body: FutureBuilder(
        future: repo.moves(product.id!),
        builder: (context, snapshot) {
          final moves = snapshot.data;
          if (moves == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (moves.isEmpty) {
            return const Center(child: Text('Nenhuma movimentação ainda.'));
          }
          return ListView.builder(
            itemCount: moves.length,
            itemBuilder: (context, i) {
              final m = moves[i];
              final signed = m.quantity > 0
                  ? '+${formatQuantity(m.quantity)}'
                  : formatQuantity(m.quantity);
              return ListTile(
                title: Text('${moveLabel(m.kind, m.saleNumber)} $signed $unit'),
                subtitle: Text(
                  [
                    noteTime(m.at),
                    if (m.variantLabel.isNotEmpty) m.variantLabel,
                    if (m.unitCost case final cost?)
                      'custo ${formatMoney(cost)}',
                    if (m.reason.isNotEmpty) m.reason,
                    if (m.note.isNotEmpty) m.note,
                    'saldo ${stockText(m.balance, unit)}',
                  ].join(' · '),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
