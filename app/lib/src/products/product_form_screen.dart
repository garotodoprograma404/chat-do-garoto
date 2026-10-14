import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../search/text.dart';
import '../home/crm_scope.dart';
import '../scan/barcode_scanner.dart';
import '../storage/form_drafts.dart';
import '../theme/form_parts.dart';
import '../theme/motion.dart';
import 'barcode.dart';
import 'money.dart';
import 'pricing.dart';
import 'product_photos.dart';
import 'products_repository.dart';
import 'variants.dart';

/// A variation being edited; its key is the combination of options.
class _VariantDraft {
  _VariantDraft({required this.options, Variant? saved})
    : id = saved?.id,
      savedStock = saved?.stock ?? 0,
      active = saved?.active ?? true,
      sku = TextEditingController(text: saved?.sku ?? ''),
      barcode = TextEditingController(text: saved?.barcode ?? ''),
      price = moneyController(saved?.price),
      cost = moneyController(saved?.cost);

  final int? id;
  final List<String> options;
  final int savedStock;
  bool active;
  final TextEditingController sku, barcode, price, cost;

  /// The initial stock, only for a new variation.
  final stock = TextEditingController();

  String get label => variantLabel(options);

  void dispose() {
    for (final c in [sku, barcode, price, cost, stock]) {
      c.dispose();
    }
  }
}

class _AttributeDraft {
  _AttributeDraft([Attribute? a])
    : name = TextEditingController(text: a?.name ?? ''),
      values = TextEditingController(text: a?.values.join(', ') ?? '');
  final TextEditingController name, values;

  void dispose() {
    name.dispose();
    values.dispose();
  }
}

/// A photo in the form: saved in app.db, or just picked.
class _Photo {
  const _Photo({this.id, this.bytes});
  final int? id;
  final Uint8List? bytes;
}

/// Creates or edits a product or service. Pops with the id.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({
    super.key,
    required this.repo,
    this.photos,
    this.initial,
    this.barcode,
    this.clock,
  });

  final ProductsRepository repo;
  final PhotoPicker? photos;
  final Product? initial;

  /// A code just read, for a new product.
  final String? barcode;
  final DateTime Function()? clock;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  late final Product? p = widget.initial;
  late ProductKind _kind = p?.kind ?? ProductKind.product;
  late String _unit = p?.unit ?? 'UN';
  late bool _active = p?.active ?? true;

  late final _name = TextEditingController(text: p?.name ?? '');
  late final _sku = TextEditingController(text: p?.sku ?? '');
  late final _barcode = TextEditingController(
    text: p?.barcode ?? widget.barcode ?? '',
  );
  late final _category = TextEditingController(text: p?.category ?? '');
  late final _brand = TextEditingController(text: p?.brand ?? '');
  late final _supplier = TextEditingController(text: p?.supplier ?? '');
  late final _description = TextEditingController(text: p?.description ?? '');
  late final _price = moneyController(p?.price);
  // The cost of a simple product; with variations, the cost of new ones.
  late final _cost = moneyController(
    p == null || p!.hasVariants || p!.variants.isEmpty
        ? null
        : p!.variants.first.cost,
  );
  late final _promoPrice = moneyController(p?.promoPrice);
  late final _promoUntil = TextEditingController(
    text: p?.promoUntil == null ? '' : formatDay(p!.promoUntil!),
  );
  late final _expiresOn = TextEditingController(
    text: p?.expiresOn == null ? '' : formatDay(p!.expiresOn!),
  );
  late final _minStock = TextEditingController(
    text: p == null || p!.minStock == 0 ? '' : formatQuantity(p!.minStock),
  );
  late final _initialStock = TextEditingController();
  late final _tiers = [
    for (var i = 0; i < 3; i++)
      (
        qty: TextEditingController(
          text: i < (p?.tiers.length ?? 0)
              ? formatQuantity(p!.tiers[i].minQty)
              : '',
        ),
        price: moneyController(
          i < (p?.tiers.length ?? 0) ? p!.tiers[i].price : null,
        ),
      ),
  ];
  late final _attributes = [
    for (final a in p?.attributes ?? const <Attribute>[]) _AttributeDraft(a),
  ];

  /// Every variation drafted while the form is open, by key: typing a value
  /// away and back keeps what was filled in.
  late final Map<String, _VariantDraft> _drafts = {
    for (final v in p?.variants ?? const <Variant>[])
      optionsKey(v.options): _VariantDraft(options: v.options, saved: v),
  };
  late final _photos = [
    for (final id in p?.photoIds ?? const []) _Photo(id: id),
  ];

  /// How many wholesale rows show; "Adicionar faixa" adds one.
  late int _tierRows = max(1, p?.tiers.length ?? 0);

  /// The "Mais detalhes" groups open now.
  final _open = <String>{};

  /// One key per field, to scroll to the first error.
  final _keys = <String, GlobalKey>{};
  GlobalKey _key(String field) => _keys.putIfAbsent(field, GlobalKey.new);

  /// The draft of a new product: not when editing or when
  /// a code just read opened the form.
  late final _draft = DraftKeeper(
    form: 'product',
    drafts: null,
    enabled: p == null && widget.barcode == null,
    fields: {
      'name': _name,
      'price': _price,
      'stock': _initialStock,
      'sku': _sku,
      'barcode': _barcode,
      'cost': _cost,
      'promoPrice': _promoPrice,
      'promoUntil': _promoUntil,
      for (final (i, t) in _tiers.indexed) ...{
        'tierQty$i': t.qty,
        'tierPrice$i': t.price,
      },
      'minStock': _minStock,
      'expiresOn': _expiresOn,
      'category': _category,
      'brand': _brand,
      'supplier': _supplier,
      'description': _description,
    },
  );
  bool _draftChecked = false;

  final _focus = <String, FocusNode>{};
  final _errors = <String, String>{};
  var _categories = const <String>[];
  var _brands = const <String>[];
  var _suppliers = const <String>[];
  bool _saving = false;

  bool get _isProduct => _kind == ProductKind.product;
  DateTime get _today => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    for (final c in [_price, _cost]) {
      c.addListener(() => setState(() {}));
    }
    for (final a in _attributes) {
      _listen(a);
    }
    _draft.start(() => setState(() {}));
    _loadSuggestions();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_draftChecked) return;
    _draftChecked = true;
    _draft.drafts = CrmScope.maybeOf(context)?.drafts;
    _offerDraft();
  }

  /// A product typed before and not saved: continue it?
  Future<void> _offerDraft() async {
    final pending = await _draft.pending();
    if (pending == null || !mounted) return;
    if (await askContinueDraft(context)) {
      final rows = [
        for (var i = 0; i < _tiers.length; i++)
          if ((pending['tierQty$i'] ?? '').isNotEmpty) i,
      ];
      setState(() {
        _draft.restore(pending);
        if (rows.isNotEmpty) _tierRows = rows.last + 1;
      });
    } else {
      await _draft.clear();
      _draft.enabled = true;
    }
  }

  void _listen(_AttributeDraft a) {
    a.name.addListener(() => setState(() {}));
    a.values.addListener(() => setState(() {}));
  }

  Future<void> _loadSuggestions() async {
    final all = await widget.repo.list();
    List<String> used(String Function(Product) field) => {
      for (final x in all)
        if (field(x).isNotEmpty) field(x),
    }.toList()..sort((a, b) => fold(a).compareTo(fold(b)));
    if (!mounted) return;
    setState(() {
      _categories = used((x) => x.category);
      _brands = used((x) => x.brand);
      _suppliers = used((x) => x.supplier);
    });
  }

  @override
  void dispose() {
    _draft.dispose();
    for (final c in [
      _name,
      _sku,
      _barcode,
      _category,
      _brand,
      _supplier,
      _description,
      _price,
      _cost,
      _promoPrice,
      _promoUntil,
      _expiresOn,
      _minStock,
      _initialStock,
      for (final t in _tiers) ...[t.qty, t.price],
    ]) {
      c.dispose();
    }
    for (final a in _attributes) {
      a.dispose();
    }
    for (final d in _drafts.values) {
      d.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  /// The attributes as typed: filled-in rows only.
  List<Attribute> get _typedAttributes => [
    for (final a in _attributes)
      if (a.name.text.trim().isNotEmpty || a.values.text.trim().isNotEmpty)
        Attribute(a.name.text.trim(), parseValues(a.values.text)),
  ];

  /// The grid for the attributes typed now.
  List<_VariantDraft> get _grid {
    final attributes = _typedAttributes;
    if (!_isProduct ||
        attributes.isEmpty ||
        combinationCount(attributes) > maxVariants) {
      return const [];
    }
    return [
      for (final o in combinations(attributes))
        _drafts.putIfAbsent(optionsKey(o), () => _VariantDraft(options: o)),
    ];
  }

  // --- Saving ---------------------------------------------------------

  int? _money(String key, TextEditingController c, {bool required = false}) {
    final text = c.text.trim();
    if (text.isEmpty) {
      if (required) _errors[key] = 'Digite o valor.';
      return null;
    }
    final value = parseMoney(text);
    if (value == null) _errors[key] = 'Valor inválido.';
    return value;
  }

  int? _quantity(String key, TextEditingController c) {
    final text = c.text.trim();
    if (text.isEmpty) return null;
    final value = parseQuantity(text, _unit);
    if (value == null) {
      _errors[key] = fractional(_unit)
          ? 'Quantidade inválida.'
          : 'Só números inteiros em $_unit.';
    }
    return value;
  }

  Future<void> _save() async {
    _errors.clear();
    final name = _name.text.trim();
    if (name.isEmpty) _errors['name'] = 'Digite o nome.';
    if (skuError(_sku.text.trim()) case final e?) _errors['sku'] = e;
    if (barcodeError(_barcode.text.trim()) case final e?) {
      _errors['barcode'] = e;
    }
    final price = _money('price', _price, required: true);
    final cost = _money('cost', _cost) ?? 0;

    final promo = _money('promoPrice', _promoPrice);
    final until = parseDay(_promoUntil.text);
    if (until == null) {
      _errors['promoUntil'] = 'Use dd/mm/aaaa.';
    } else if (until.isNotEmpty &&
        _promoUntil.text !=
            (p?.promoUntil == null ? '' : formatDay(p!.promoUntil!)) &&
        until.compareTo(isoDay(_today)) < 0) {
      _errors['promoUntil'] = 'Essa data já passou.';
    }
    final expires = _isProduct ? parseDay(_expiresOn.text) : '';
    if (expires == null) _errors['expiresOn'] = 'Use dd/mm/aaaa.';
    if (promo == null && until != null && until.isNotEmpty) {
      _errors['promoPrice'] = 'Digite o preço promocional.';
    }
    if (promo != null && price != null && promo >= price) {
      _errors['promoPrice'] = 'Precisa ser menor que o preço de venda.';
    }

    final tiers = <WholesaleTier>[];
    for (final (i, t) in _tiers.indexed) {
      if (t.qty.text.trim().isEmpty && t.price.text.trim().isEmpty) continue;
      final qty = _quantity('tierQty$i', t.qty);
      final tierPrice = _money('tierPrice$i', t.price, required: true);
      if (t.qty.text.trim().isEmpty) {
        _errors['tierQty$i'] = 'Digite a quantidade.';
      }
      if (qty == null || tierPrice == null) continue;
      final last = tiers.lastOrNull;
      if (qty == 0 || (last != null && qty <= last.minQty)) {
        _errors['tierQty$i'] = 'Use quantidades maiores a cada faixa.';
      } else if ((price != null && tierPrice >= price) ||
          (last != null && tierPrice >= last.price)) {
        _errors['tierPrice$i'] =
            'Precisa ser menor que o preço de venda e que a faixa anterior.';
      } else {
        tiers.add(WholesaleTier(qty, tierPrice));
      }
    }

    final minStock = _isProduct ? _quantity('minStock', _minStock) ?? 0 : 0;
    final initialStock = _quantity('stock', _initialStock) ?? 0;

    // Attributes and variations.
    final attributes = _isProduct ? _typedAttributes : const <Attribute>[];
    for (final (i, a) in attributes.indexed) {
      if (a.name.isEmpty) _errors['attrName$i'] = 'Digite o nome do atributo.';
      if (a.values.isEmpty) {
        _errors['attrValues$i'] = 'Digite os valores, separados por vírgula.';
      }
      if (attributes.take(i).any((b) => fold(b.name) == fold(a.name))) {
        _errors['attrName$i'] = 'Atributo repetido.';
      }
    }
    if (combinationCount(attributes) > maxVariants) {
      _errors['variants'] = 'No máximo $maxVariants variações por produto.';
    }

    final variants = <Variant>[];
    final variantErrors = <String>[];
    if (attributes.isEmpty) {
      // One default variation.
      final saved = _drafts[optionsKey(const [])];
      variants.add(
        Variant(id: saved?.id, cost: cost, stock: initialStock, price: null),
      );
    } else {
      for (final d in _grid) {
        String problem(String what) => '${d.label}: $what';
        final sku = d.sku.text.trim(), code = d.barcode.text.trim();
        if (skuError(sku) case final e?) variantErrors.add(problem(e));
        if (barcodeError(code) case final e?) variantErrors.add(problem(e));
        int? money(TextEditingController c) {
          if (c.text.trim().isEmpty) return null;
          final v = parseMoney(c.text);
          if (v == null) variantErrors.add(problem('valor inválido.'));
          return v;
        }

        final stockText = d.stock.text.trim();
        final stock = stockText.isEmpty ? 0 : parseQuantity(stockText, _unit);
        if (stock == null) variantErrors.add(problem('estoque inválido.'));
        variants.add(
          Variant(
            id: d.id,
            options: d.options,
            sku: sku,
            barcode: code,
            price: money(d.price),
            cost: money(d.cost) ?? cost,
            stock: stock ?? 0,
            active: d.active,
          ),
        );
      }
    }
    if (variantErrors.isNotEmpty) {
      _errors['variants'] = variantErrors.join('\n');
    }

    if (_errors.isNotEmpty) {
      _showErrors();
      return;
    }

    // Variations that go away take their stock and history.
    final keptIds = {for (final v in variants) ?v.id};
    final removed = [
      for (final v in p?.variants ?? const <Variant>[])
        if (!keptIds.contains(v.id)) v,
    ];
    if (removed.isNotEmpty && !await _confirmRemoval(removed)) return;

    setState(() => _saving = true);
    try {
      final id = await widget.repo.save(
        Product(
          id: p?.id,
          kind: _kind,
          name: name,
          sku: _sku.text.trim(),
          barcode: _barcode.text.trim(),
          category: _category.text.trim(),
          brand: _brand.text.trim(),
          supplier: _supplier.text.trim(),
          unit: _unit,
          description: _description.text.trim(),
          price: price!,
          promoPrice: promo,
          promoUntil: until == null || until.isEmpty ? null : until,
          expiresOn: expires == null || expires.isEmpty ? null : expires,
          minStock: minStock,
          active: _active,
          attributes: attributes,
          variants: variants,
          tiers: tiers,
        ),
        photos: [
          for (final ph in _photos)
            ph.id != null
                ? PhotoDraft.saved(ph.id!)
                : PhotoDraft.added(ph.bytes!),
        ],
      );
      await _draft.clear();
      if (mounted) Navigator.pop(context, id);
    } on ProductHasSales catch (e) {
      // Sold variations are deactivated, not deleted.
      setState(() {
        _saving = false;
        _errors['variants'] =
            'Já foram vendidas e não podem ser apagadas: '
            '${e.labels.join(', ')}. Desative-as em vez de tirar os valores.';
      });
    } on DuplicateCode catch (e) {
      setState(() {
        _saving = false;
        const message = 'Este código já está em uso.';
        if (_sku.text.trim() == e.code) {
          _errors['sku'] = message;
        } else if (_barcode.text.trim() == e.code) {
          _errors['barcode'] = message;
        } else {
          _errors['variants'] = 'O código ${e.code} já está em uso.';
        }
      });
    }
  }

  Future<bool> _confirmRemoval(List<Variant> removed) async {
    final stock = removed.fold(0, (sum, v) => sum + v.stock);
    final names = [
      for (final v in removed) v.label.isEmpty ? 'sem variação' : v.label,
    ].join(', ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          removed.length == 1
              ? 'Apagar 1 variação?'
              : 'Apagar ${removed.length} variações?',
        ),
        content: Text(
          '$names.\nEstoque total: ${formatQuantity(stock)} $_unit. O estoque '
          'e o histórico delas serão apagados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apagar e salvar'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Opens the groups with errors and scrolls to the first one.
  void _showErrors() {
    setState(() {
      for (final key in _errors.keys) {
        if (_groupOf(key) case final g?) _open.add(g);
      }
    });
    final first = _fieldOrder.firstWhere(
      _errors.containsKey,
      orElse: () => _errors.keys.first,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[first]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.2,
          duration: Motion.of(ctx, Motion.item),
        );
      }
    });
  }

  /// The fields in the order they show.
  static const _fieldOrder = [
    'name',
    'price',
    'stock',
    'sku',
    'barcode',
    'cost',
    'promoPrice',
    'promoUntil',
    'tierQty0',
    'tierPrice0',
    'tierQty1',
    'tierPrice1',
    'tierQty2',
    'tierPrice2',
    'minStock',
    'expiresOn',
    'attrName0',
    'attrValues0',
    'attrName1',
    'attrValues1',
    'attrName2',
    'attrValues2',
    'variants',
  ];

  /// The "Mais detalhes" group a field is in; null for the top ones.
  static String? _groupOf(String field) => switch (field) {
    'sku' || 'barcode' => 'codes',
    'cost' => 'cost',
    'promoPrice' || 'promoUntil' => 'promo',
    _ when field.startsWith('tier') => 'tiers',
    'minStock' || 'expiresOn' => 'stock',
    _ when field.startsWith('attr') || field == 'variants' => 'variants',
    _ => null,
  };

  // --- Photos ---------------------------------------------------------

  Future<void> _pick(PhotoSource source) async {
    final picker = widget.photos;
    if (picker == null) return;
    final bytes = await picker.pick(source);
    if (bytes == null || !mounted) return;
    setState(() => _photos.add(_Photo(bytes: bytes)));
  }

  /// "Adicionar foto": the camera or the gallery.
  Future<void> _addPhoto() async {
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Symbols.photo_camera_rounded),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.pop(context, PhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(Symbols.photo_library_rounded),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(context, PhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pick(source);
  }

  /// A photo tapped: make it the main one or remove it.
  Future<void> _photoMenu(int i) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (i > 0)
              ListTile(
                leading: const Icon(Symbols.star_rounded),
                title: const Text('Tornar principal'),
                onTap: () => Navigator.pop(context, 'main'),
              ),
            ListTile(
              leading: const Icon(Symbols.delete_rounded),
              title: const Text('Remover foto'),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      if (action == 'main') _photos.insert(0, _photos.removeAt(i));
      if (action == 'remove') _photos.removeAt(i);
    });
  }

  Widget _photo(_Photo ph, double size) => switch (ph) {
    _Photo(:final id?) => ProductThumb(
      repo: widget.repo,
      photoId: id,
      size: size,
    ),
    _Photo(:final bytes?) => SizedBox.square(
      dimension: size,
      child: Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 360),
    ),
    _ => const SizedBox.shrink(),
  };

  /// The photo first: a big "Adicionar foto", then the
  /// photos side by side, the first one the main.
  Widget _photos_() {
    final colors = Theme.of(context).colorScheme;
    final canAdd = widget.photos != null && _photos.length < maxPhotos;
    Widget tile({required Widget child, VoidCallback? onTap}) => Material(
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: child),
    );
    final size = _photos.isEmpty ? 120.0 : 96.0;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: 8,
        children: [
          for (final (i, ph) in _photos.indexed)
            tile(
              onTap: () => _photoMenu(i),
              child: Stack(
                children: [
                  _photo(ph, size),
                  if (i == 0)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surface.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            'Principal',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (canAdd)
            tile(
              onTap: _addPhoto,
              // Grows with large text instead of overflowing.
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: size,
                  maxWidth: size,
                  minHeight: size,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Symbols.add_a_photo_rounded,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Adicionar foto',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium!
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- Fields ---------------------------------------------------------

  Widget _field(
    String key,
    String label,
    TextEditingController controller, {
    TextInputType? keyboard,
    String? hint,
    int maxLines = 1,
    Widget? suffix,
    List<TextInputFormatter>? masks,
  }) => TextField(
    key: _key(key),
    controller: controller,
    keyboardType: keyboard,
    maxLines: maxLines,
    inputFormatters: masks,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: _errors[key],
      suffixIcon: suffix,
    ),
  );

  Widget _moneyField(String key, String label, TextEditingController c) =>
      KeyedSubtree(
        key: _key(key),
        child: MoneyField(controller: c, label: label, error: _errors[key]),
      );

  Widget _date(
    String key,
    String label,
    TextEditingController c,
    String hint,
  ) => _field(
    key,
    label,
    c,
    keyboard: TextInputType.number,
    hint: hint,
    masks: [Masks.date],
  );

  static const _decimal = TextInputType.numberWithOptions(decimal: true);

  /// A text field with suggestions from what was used before.
  Widget _suggested(
    String key,
    String label,
    TextEditingController controller,
    List<String> options,
  ) => RawAutocomplete<String>(
    textEditingController: controller,
    focusNode: _focus.putIfAbsent(key, FocusNode.new),
    optionsBuilder: (value) => [
      for (final o in options)
        if (o != value.text && textMatches(o, value.text)) o,
    ],
    fieldViewBuilder: (context, controller, focusNode, _) => TextField(
      controller: controller,
      focusNode: focusNode,
      decoration: InputDecoration(labelText: label),
    ),
    optionsViewBuilder: (context, onSelected, options) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        child: SizedBox(
          width: 280,
          height: min(240, 48.0 * options.length),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (final o in options)
                ListTile(title: Text(o), onTap: () => onSelected(o)),
            ],
          ),
        ),
      ),
    ),
  );

  String? _profitText() {
    final price = parseMoney(_price.text), cost = parseMoney(_cost.text);
    if (price == null || cost == null || cost == 0) return null;
    final margin = marginPercent(price, cost);
    return 'Lucro: ${formatMoney(price - cost)}'
        '${margin == null ? '' : ' · margem ${formatPercent(margin)}'}';
  }

  Future<void> _editVariant(_VariantDraft d) async {
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(d.label),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 12,
              children: [
                TextField(
                  controller: d.sku,
                  decoration: const InputDecoration(labelText: 'Código'),
                ),
                TextField(
                  controller: d.barcode,
                  decoration: InputDecoration(
                    labelText: 'Código de barras',
                    suffixIcon: scanIntoButton(context, d.barcode),
                  ),
                ),
                MoneyField(
                  controller: d.price,
                  label: 'Preço próprio',
                  hint: 'em branco: o do produto',
                ),
                MoneyField(
                  controller: d.cost,
                  label: 'Custo',
                  hint: d.id == null ? 'em branco: o do produto' : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ativa'),
                  value: d.active,
                  onChanged: (v) => setLocal(() => d.active = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        ),
      ),
    );
    setState(() {});
  }

  Widget _variantRow(_VariantDraft d) {
    final details = [
      if (d.sku.text.trim().isNotEmpty) 'cód. ${d.sku.text.trim()}',
      if (parseMoney(d.price.text) case final price?) formatMoney(price),
      if (parseMoney(d.cost.text) case final cost?)
        'custo ${formatMoney(cost)}',
      if (d.id != null) 'estoque ${formatQuantity(d.savedStock)}',
      if (!d.active) 'desativada',
    ];
    return Row(
      key: ObjectKey(d),
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(d.label, style: Theme.of(context).textTheme.titleSmall),
              if (details.isNotEmpty)
                Text(
                  details.join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        if (d.id == null)
          SizedBox(
            width: 96,
            child: TextField(
              controller: d.stock,
              keyboardType: _decimal,
              decoration: const InputDecoration(labelText: 'Estoque'),
            ),
          ),
        IconButton(
          tooltip: 'Editar ${d.label}',
          icon: const Icon(Symbols.edit_rounded),
          onPressed: () => _editVariant(d),
        ),
      ],
    );
  }

  List<Widget> _variations() {
    final grid = _grid;
    return [
      Text(
        'Para tamanhos, cores e outras opções: cada combinação vira uma '
        'variação, com estoque e preço próprios.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      // Name and values stacked: side by side, the name got cut.
      for (final (i, a) in _attributes.indexed)
        Column(
          key: ObjectKey(a),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field(
                    'attrName$i',
                    'Atributo',
                    a.name,
                    hint: 'Tamanho, Cor…',
                  ),
                ),
                IconButton(
                  tooltip: 'Tirar atributo',
                  icon: const Icon(Symbols.close_rounded),
                  onPressed: () => setState(() {
                    _attributes.removeAt(i);
                    a.dispose();
                  }),
                ),
              ],
            ),
            _field(
              'attrValues$i',
              'Valores, separados por vírgula',
              a.values,
              hint: 'P, M, G',
            ),
          ],
        ),
      if (_attributes.length < maxAttributes)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() {
              final a = _AttributeDraft();
              _listen(a);
              _attributes.add(a);
            }),
            icon: const Icon(Symbols.add_rounded),
            label: const Text('Adicionar atributo'),
          ),
        ),
      if (_errors['variants'] case final e?)
        Text(
          e,
          key: _key('variants'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (grid.isNotEmpty) ...[
        Text(grid.length == 1 ? '1 variação' : '${grid.length} variações'),
        for (final d in grid) _variantRow(d),
      ],
    ];
  }

  // --- Summaries of the closed groups ------------------------------

  String? _join(List<String> parts) {
    final kept = [
      for (final p in parts)
        if (p.trim().isNotEmpty) p.trim(),
    ];
    return kept.isEmpty ? null : kept.join(' · ');
  }

  String? get _codesSummary => _join([
    if (_sku.text.trim().isNotEmpty) 'cód. ${_sku.text.trim()}',
    _barcode.text,
  ]);

  String? get _costSummary => switch (parseMoney(_cost.text)) {
    null || 0 => null,
    final cost => _join(['Custo ${formatMoney(cost)}', _profitText() ?? '']),
  };

  String? get _promoSummary => switch (parseMoney(_promoPrice.text)) {
    null => null,
    final promo =>
      _promoUntil.text.trim().isEmpty
          ? '${formatMoney(promo)}, sem data para acabar'
          : '${formatMoney(promo)} até ${_promoUntil.text.trim()}',
  };

  String? get _tiersSummary {
    final filled = [
      for (final t in _tiers.take(_tierRows))
        if (t.qty.text.trim().isNotEmpty && parseMoney(t.price.text) != null)
          'a partir de ${t.qty.text.trim()}: ${formatMoney(parseMoney(t.price.text)!)}',
    ];
    return filled.isEmpty ? null : filled.join('; ');
  }

  String? get _stockSummary => _join([
    if (_unit != 'UN') 'Unidade $_unit',
    if (_minStock.text.trim().isNotEmpty) 'mínimo ${_minStock.text.trim()}',
    if (_expiresOn.text.trim().isNotEmpty) 'validade ${_expiresOn.text.trim()}',
  ]);

  String? get _variantsSummary {
    final attributes = _typedAttributes;
    if (attributes.isEmpty) return null;
    final n = combinationCount(attributes);
    return '${n == 1 ? '1 variação' : '$n variações'} '
        '(${attributes.map((a) => a.name).join(', ')})';
  }

  String? get _organizationSummary => _join([
    _category.text,
    _brand.text,
    _supplier.text,
    if (_description.text.trim().isNotEmpty) 'com descrição',
  ]);

  Widget _group(
    String id,
    String title,
    IconData icon,
    String? summary,
    List<Widget> children,
  ) => DetailsGroup(
    title: title,
    icon: icon,
    summary: summary,
    open: _open.contains(id),
    onToggle: () =>
        setState(() => _open.contains(id) ? _open.remove(id) : _open.add(id)),
    children: children,
  );

  @override
  Widget build(BuildContext context) {
    // Something typed: the back asks before throwing it away.
    return PopScope(
      canPop: !_draft.dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !await confirmDiscard(context)) return;
        await _draft.clear();
        if (context.mounted) Navigator.pop(context);
      },
      child: _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    final editing = p?.id != null;
    final simple = _isProduct && _typedAttributes.isEmpty;
    final profit = simple ? _profitText() : null;
    final t = Theme.of(context).textTheme;
    final savedStock = _drafts[optionsKey(const [])];
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Editar produto' : 'Novo produto'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Salvar'),
          ),
        ],
      ),
      // A column, not a lazy list: fields that come and go must not move
      // the focus to another field.
      body: SingleChildScrollView(
        // Content drawn behind the system navigation bar must scroll above
        // it (edge to edge on Android).
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Only what matters on top: photo, name, price
            // and stock.
            if (widget.photos != null || _photos.isNotEmpty) ...[
              _photos_(),
              const SizedBox(height: 16),
            ],
            _field('name', 'Nome', _name),
            const FormGap(),
            _moneyField('price', 'Preço de venda', _price),
            if (_isProduct) ...[
              const FormGap(),
              if (!simple)
                Text(
                  'O estoque fica em cada variação, em "Variações".',
                  style: t.bodySmall,
                )
              else if (savedStock?.id == null)
                _field(
                  'stock',
                  'Estoque ($_unit)',
                  _initialStock,
                  keyboard: _decimal,
                  hint: 'quanto você tem agora',
                )
              else
                Text(
                  'Estoque: ${formatQuantity(savedStock!.savedStock)} $_unit '
                  '(muda pela página do produto)',
                  style: t.bodyMedium,
                ),
            ],
            const SizedBox(height: 24),
            Text('Mais detalhes', style: t.titleMedium),
            Text(
              'Tudo opcional. Toque para abrir.',
              style: t.bodySmall!.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            _group(
              'codes',
              'Código de barras e código interno',
              Symbols.barcode_rounded,
              _codesSummary,
              [
                _field(
                  'barcode',
                  'Código de barras',
                  _barcode,
                  keyboard: TextInputType.number,
                  suffix: scanIntoButton(context, _barcode),
                ),
                _field('sku', 'Código interno (SKU)', _sku),
              ],
            ),
            _group(
              'cost',
              'Custo e lucro',
              Symbols.calculate_rounded,
              _costSummary,
              [
                _moneyField(
                  'cost',
                  simple || !_isProduct
                      ? 'Preço de custo'
                      : 'Preço de custo (das variações novas)',
                  _cost,
                ),
                if (profit != null) Text(profit),
              ],
            ),
            _group('promo', 'Promoção', Symbols.sell_rounded, _promoSummary, [
              _moneyField('promoPrice', 'Preço promocional', _promoPrice),
              _date(
                'promoUntil',
                'Promoção até',
                _promoUntil,
                'dd/mm/aaaa (em branco: sem data)',
              ),
            ]),
            _group('tiers', 'Atacado', Symbols.stacks_rounded, _tiersSummary, [
              Text(
                'Preço menor a partir de uma quantidade.',
                style: t.bodySmall,
              ),
              for (final (i, tier) in _tiers.take(_tierRows).indexed)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _field(
                        'tierQty$i',
                        'A partir de ($_unit)',
                        tier.qty,
                        keyboard: _decimal,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _moneyField('tierPrice$i', 'Preço', tier.price),
                    ),
                  ],
                ),
              if (_tierRows < _tiers.length)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _tierRows++),
                    icon: const Icon(Symbols.add_rounded),
                    label: const Text('Adicionar faixa'),
                  ),
                ),
            ]),
            if (_isProduct)
              _group(
                'stock',
                'Estoque e validade',
                Symbols.inventory_2_rounded,
                _stockSummary,
                [
                  DropdownButtonFormField<String>(
                    initialValue: _unit,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Unidade'),
                    items: [
                      for (final u in units)
                        DropdownMenuItem(value: u, child: Text(u)),
                    ],
                    onChanged: (u) => setState(() => _unit = u!),
                  ),
                  _field(
                    'minStock',
                    'Estoque mínimo ($_unit)',
                    _minStock,
                    keyboard: _decimal,
                    hint: 'avisa quando chegar nele',
                  ),
                  // The current batch's.
                  _date(
                    'expiresOn',
                    'Validade',
                    _expiresOn,
                    'dd/mm/aaaa (em branco: não se aplica)',
                  ),
                ],
              ),
            if (_isProduct)
              _group(
                'variants',
                'Variações (tamanho, cor…)',
                Symbols.style_rounded,
                _variantsSummary,
                _variations(),
              ),
            _group(
              'organization',
              'Categoria, marca e descrição',
              Symbols.folder_rounded,
              _organizationSummary,
              [
                _suggested('category', 'Categoria', _category, _categories),
                _suggested('brand', 'Marca', _brand, _brands),
                _suggested('supplier', 'Fornecedor', _supplier, _suppliers),
                _field('description', 'Descrição', _description, maxLines: 3),
              ],
            ),
            if (!editing)
              _group(
                'kind',
                'Produto ou serviço',
                Symbols.category_rounded,
                _isProduct ? 'Produto' : 'Serviço (sem estoque)',
                [
                  SegmentedButton<ProductKind>(
                    segments: const [
                      ButtonSegment(
                        value: ProductKind.product,
                        label: Text('Produto'),
                      ),
                      ButtonSegment(
                        value: ProductKind.service,
                        label: Text('Serviço'),
                      ),
                    ],
                    selected: {_kind},
                    onSelectionChanged: (s) => setState(() => _kind = s.single),
                  ),
                ],
              )
            else
              _group(
                'active',
                'Situação',
                Symbols.toggle_on_rounded,
                _active ? 'Ativo' : 'Inativo (não aparece na venda)',
                [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ativo'),
                    subtitle: const Text('Inativo não aparece na venda.'),
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
