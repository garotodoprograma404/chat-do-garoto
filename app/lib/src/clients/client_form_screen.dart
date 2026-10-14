import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../home/crm_scope.dart';
import '../storage/form_drafts.dart';
import '../theme/form_parts.dart';
import 'cep_lookup.dart';
import 'clients_repository.dart';
import 'contact_picker.dart';
import 'validation.dart';

/// Creates or edits a client. Pops with the id.
class ClientFormScreen extends StatefulWidget {
  const ClientFormScreen({super.key, required this.repo, this.initial});

  final ClientsRepository repo;

  /// The client to edit, or the data to start from (a chat).
  final Client? initial;

  @override
  State<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends State<ClientFormScreen> {
  late final Client? c = widget.initial;
  late final _name = TextEditingController(text: c?.name ?? '');
  late final _phone = TextEditingController(
    text: Masks.phone.apply(c?.phone ?? ''),
  );
  late final _email = TextEditingController(text: c?.email ?? '');
  late final _address = TextEditingController(text: c?.address ?? '');
  late final _cep = TextEditingController(text: Masks.cep.apply(c?.cep ?? ''));
  late final _number = TextEditingController(text: c?.number ?? '');
  late final _complement = TextEditingController(text: c?.complement ?? '');
  late final _district = TextEditingController(text: c?.district ?? '');
  late final _city = TextEditingController(text: c?.city ?? '');
  late final _state = TextEditingController(text: c?.state ?? '');
  final _numberFocus = FocusNode();

  /// What the last CEP lookup filled in: a new lookup may replace it, but
  /// never what was typed by hand.
  var _looked = <TextEditingController, String>{};
  bool _looking = false;
  late final _document = TextEditingController(
    text: c == null ? '' : formatDocument(c!.document),
  );
  late final _birthday = TextEditingController(
    text: c == null ? '' : formatBirthday(c!.birthday),
  );
  late final _company = TextEditingController(text: c?.company ?? '');
  late final _tags = TextEditingController(text: c?.tags.join(', ') ?? '');
  final _errors = <String, String>{};
  bool _saving = false;

  /// "Mais detalhes" open; errors in it open it.
  bool _details = false;

  /// The draft of a new client: not when editing or saving a chat.
  late final _draft = DraftKeeper(
    form: 'client',
    drafts: null,
    enabled: c == null,
    fields: {
      'name': _name,
      'phone': _phone,
      'email': _email,
      'address': _address,
      'cep': _cep,
      'number': _number,
      'complement': _complement,
      'district': _district,
      'city': _city,
      'state': _state,
      'document': _document,
      'birthday': _birthday,
      'company': _company,
      'tags': _tags,
    },
  );
  bool _draftChecked = false;

  @override
  void initState() {
    super.initState();
    _draft.start(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_draftChecked) return;
    _draftChecked = true;
    _draft.drafts = CrmScope.maybeOf(context)?.drafts;
    _offerDraft();
  }

  Future<void> _offerDraft() async {
    final pending = await _draft.pending();
    if (pending == null || !mounted) return;
    if (await askContinueDraft(context)) {
      setState(() => _draft.restore(pending));
    } else {
      await _draft.clear();
      _draft.enabled = true;
    }
  }

  @override
  void dispose() {
    _draft.dispose();
    _numberFocus.dispose();
    for (final t in [
      _name,
      _phone,
      _email,
      _address,
      _cep,
      _number,
      _complement,
      _district,
      _city,
      _state,
      _document,
      _birthday,
      _company,
      _tags,
    ]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final phone = digitsOf(_phone.text);
    final document = digitsOf(_document.text);
    final birthday = parseBirthday(_birthday.text);
    _errors.clear();
    if (_name.text.trim().isEmpty) _errors['name'] = 'Digite o nome.';
    if (phoneError(phone) case final e?) _errors['phone'] = e;
    if (!validEmail(_email.text.trim())) _errors['email'] = 'E-mail inválido.';
    if (documentError(document) case final e?) _errors['document'] = e;
    final cep = digitsOf(_cep.text);
    if (cep.isNotEmpty && cep.length != 8) {
      _errors['cep'] = 'O CEP tem 8 números.';
    }
    final uf = _state.text.trim();
    if (uf.isNotEmpty && !RegExp(r'^[A-Za-z]{2}$').hasMatch(uf)) {
      _errors['state'] = 'Use a sigla, como SP.';
    }
    if (birthday == null) {
      _errors['birthday'] = 'Use dd/mm ou dd/mm/aaaa.';
    }
    if (_errors.isNotEmpty) {
      setState(() {
        if (_errors.keys.any((k) => k != 'name' && k != 'phone')) {
          _details = true;
        }
      });
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await widget.repo.save(
        Client(
          id: c?.id,
          name: _name.text.trim(),
          phone: phone,
          chatJid: c?.chatJid,
          email: _email.text.trim(),
          address: _address.text.trim(),
          cep: digitsOf(_cep.text),
          number: _number.text.trim(),
          complement: _complement.text.trim(),
          district: _district.text.trim(),
          city: _city.text.trim(),
          state: _state.text.trim().toUpperCase(),
          document: document,
          birthday: birthday!,
          company: _company.text.trim(),
          tags: parseTags(_tags.text),
        ),
      );
      await _draft.clear();
      if (mounted) Navigator.pop(context, id);
    } on DuplicatePhone {
      setState(() {
        _saving = false;
        _errors['phone'] = 'Já existe um cliente com este telefone.';
      });
    }
  }

  /// "Escolher da agenda": name and phone from the contact picked
  Future<void> _fromContacts(ContactPicker picker) async {
    final PickedContact? picked;
    try {
      picked = await picker.pick();
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir a agenda.')),
        );
      }
      return;
    }
    if (picked == null || !mounted) return;
    final phone = normalizePhone(picked.phone);
    setState(() {
      if (picked!.name.trim().isNotEmpty) _name.text = picked.name.trim();
      _phone.text = Masks.phone.apply(phone);
      _errors.remove('name');
      if (phoneError(phone) case final e?) {
        _errors['phone'] = e;
      } else {
        _errors.remove('phone');
      }
    });
  }

  Widget _field(
    String key,
    String label,
    TextEditingController controller, {
    TextInputType? keyboard,
    String? hint,
    TextInputFormatter? mask,
  }) => TextField(
    controller: controller,
    keyboardType: keyboard,
    inputFormatters: [?mask],
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: _errors[key],
    ),
  );

  /// "Buscar CEP": only the 8 digits leave the phone.
  Future<void> _findCep() async {
    final cep = digitsOf(_cep.text);
    if (cep.length != 8) {
      setState(() => _errors['cep'] = 'O CEP tem 8 números.');
      return;
    }
    setState(() {
      _errors.remove('cep');
      _looking = true;
    });
    String? problem;
    CepAddress? found;
    try {
      found = await cepLookup.find(cep);
    } on CepNotFound {
      problem = 'CEP não encontrado. Confira ou digite o endereço.';
    } on CepUnavailable {
      problem = 'Sem conexão para buscar o CEP. Digite o endereço.';
    }
    if (!mounted) return;
    setState(() {
      _looking = false;
      if (problem != null) _errors['cep'] = problem;
    });
    final a = found;
    if (a == null) return;
    final filled = <TextEditingController, String>{};
    for (final (field, value) in [
      (_address, a.street),
      (_district, a.district),
      (_city, a.city),
      (_state, a.state),
    ]) {
      final typed = field.text.trim();
      // Typed by hand: kept.
      if (typed.isNotEmpty && typed != _looked[field]) continue;
      field.text = value;
      filled[field] = value;
    }
    _looked = filled;
    _numberFocus.requestFocus();
  }

  List<Widget> _addressFields() => [
    TextField(
      controller: _cep,
      keyboardType: TextInputType.number,
      inputFormatters: [Masks.cep],
      decoration: InputDecoration(
        labelText: 'CEP',
        hintText: '00000-000',
        errorText: _errors['cep'],
        suffixIcon: _looking
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : TextButton(onPressed: _findCep, child: const Text('Buscar CEP')),
      ),
    ),
    _field('address', 'Rua', _address),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Expanded(
          flex: 2,
          child: TextField(
            controller: _number,
            focusNode: _numberFocus,
            decoration: const InputDecoration(labelText: 'Número'),
          ),
        ),
        Expanded(
          flex: 3,
          child: _field('complement', 'Complemento', _complement),
        ),
      ],
    ),
    _field('district', 'Bairro', _district),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Expanded(child: _field('city', 'Cidade', _city)),
        SizedBox(width: 96, child: _field('state', 'UF', _state)),
      ],
    ),
  ];

  /// What "Mais detalhes" holds, in one line when closed.
  String? get _summary {
    final parts = [
      for (final t in [
        _email.text,
        _document.text,
        if (_birthday.text.trim().isNotEmpty)
          'aniversário ${_birthday.text.trim()}',
        _company.text,
        _tags.text,
        if ([_address, _district, _city].any((c) => c.text.trim().isNotEmpty))
          [
            _address.text,
            _district.text,
            _city.text,
          ].where((t) => t.trim().isNotEmpty).join(', '),
      ])
        if (t.trim().isNotEmpty) t.trim(),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

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
    return Scaffold(
      appBar: AppBar(
        title: Text(c?.id == null ? 'Novo cliente' : 'Editar cliente'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Salvar'),
          ),
        ],
      ),
      // A column, not a lazy list: the group opening must not move the
      // focus to another field.
      body: FormBody(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Only name and phone on top.
              if (contactPicker case final picker?
                  when widget.initial == null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _fromContacts(picker),
                    icon: const Icon(Symbols.contacts_rounded),
                    label: const Text('Escolher da agenda'),
                  ),
                ),
                const FormGap(),
              ],
              FormPair(
                first: _field('name', 'Nome', _name),
                second: _field(
                  'phone',
                  'Telefone (com DDD)',
                  _phone,
                  keyboard: TextInputType.phone,
                  hint: '+55 11 99999-0000',
                  mask: Masks.phone,
                ),
              ),
              const FormGroupGap(),
              DetailsGroup(
                title: 'Mais detalhes',
                icon: Symbols.person_rounded,
                summary: _summary ?? 'E-mail, endereço, CPF, aniversário…',
                open: _details,
                onToggle: () => setState(() => _details = !_details),
                children: [
                  _field(
                    'email',
                    'E-mail',
                    _email,
                    keyboard: TextInputType.emailAddress,
                  ),
                  ..._addressFields(),
                  _field(
                    'document',
                    'CPF ou CNPJ',
                    _document,
                    keyboard: TextInputType.number,
                    mask: Masks.document,
                  ),
                  _field(
                    'birthday',
                    'Aniversário',
                    _birthday,
                    keyboard: TextInputType.number,
                    hint: 'dd/mm ou dd/mm/aaaa',
                    mask: Masks.date,
                  ),
                  _field('company', 'Empresa', _company),
                  _field(
                    'tags',
                    'Etiquetas',
                    _tags,
                    hint: 'separadas por vírgula',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
