import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../clients/clients_repository.dart';
import '../clients/validation.dart';
import '../products/money.dart';
import '../products/products_repository.dart';
import '../search/text.dart';
import '../theme/components.dart';

/// Picks an active product and variation for a sale. Pops
/// with the pair.
class ItemPickerScreen extends StatefulWidget {
  const ItemPickerScreen({super.key, required this.products, this.clock});

  final ProductsRepository products;
  final DateTime Function()? clock;

  @override
  State<ItemPickerScreen> createState() => _ItemPickerScreenState();
}

class _ItemPickerScreenState extends State<ItemPickerScreen> {
  List<Product> _all = const [];
  String _query = '';

  DateTime get _today => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    widget.products.list().then((all) {
      if (!mounted) return;
      setState(
        () => _all = [
          for (final p in all)
            if (p.active) p,
        ],
      );
    });
  }

  bool _matches(Product p) => textMatches(
    [
      p.name,
      p.sku ?? '',
      p.barcode ?? '',
      for (final v in p.activeVariants) ...[
        ...v.options,
        v.sku ?? '',
        v.barcode ?? '',
      ],
    ].join(' '),
    _query,
  );

  Future<void> _pick(Product p) async {
    if (!p.hasVariants) {
      Navigator.pop(context, (p, p.variants.first));
      return;
    }
    final today = _today;
    final variant = await showDialog<Variant>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(p.name),
        children: [
          for (final v in p.activeVariants)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, v),
              child: Text(
                '${v.label} · ${formatQuantity(v.stock)} ${p.unit} · '
                '${formatMoney(p.priceOf(v, today))}',
              ),
            ),
        ],
      ),
    );
    if (variant != null && mounted) Navigator.pop(context, (p, variant));
  }

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final p in _all)
        if (_matches(p)) p,
    ];
    final today = _today;
    return Scaffold(
      appBar: AppBar(title: const Text('Adicionar item')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Nome, código ou código de barras',
                prefixIcon: Icon(Symbols.search_rounded),
              ),
              onChanged: (t) => setState(() => _query = t),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: shown.length,
              itemBuilder: (context, i) {
                final p = shown[i];
                final prices = p.pricesToday(today);
                // The same row as the lists of Produtos and Clientes.
                return AppListTile(
                  leading: InitialsAvatar(p.name),
                  title: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      prices.length > 1
                          ? 'a partir de ${formatMoney(prices.first)}'
                          : formatMoney(prices.first),
                      if (!p.isService) '${formatQuantity(p.stock)} ${p.unit}',
                    ].join(' · '),
                  ),
                  onTap: () => _pick(p),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Picks a client for a sale. Pops with the client.
class ClientPickerScreen extends StatefulWidget {
  const ClientPickerScreen({super.key, required this.clients});

  final ClientsRepository clients;

  @override
  State<ClientPickerScreen> createState() => _ClientPickerScreenState();
}

class _ClientPickerScreenState extends State<ClientPickerScreen> {
  List<Client> _all = const [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    widget.clients.list().then((all) {
      if (mounted) setState(() => _all = all);
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final c in _all)
        if (textMatches('${c.name} ${c.phone} ${c.company}', _query)) c,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Escolher cliente')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Buscar clientes',
                prefixIcon: Icon(Symbols.search_rounded),
              ),
              onChanged: (t) => setState(() => _query = t),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: shown.length,
              itemBuilder: (context, i) => AppListTile(
                leading: InitialsAvatar(shown[i].name),
                title: Text(
                  shown[i].name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(formatPhone(shown[i].phone)),
                onTap: () => Navigator.pop(context, shown[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
