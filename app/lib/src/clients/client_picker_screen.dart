import 'package:flutter/material.dart';

import '../search/text.dart';
import '../theme/components.dart';
import 'clients_repository.dart';
import 'validation.dart';

/// Picks a client, with a search. Pops with
/// the client.
class ClientPickerScreen extends StatefulWidget {
  const ClientPickerScreen({super.key, required this.repo});

  final ClientsRepository repo;

  @override
  State<ClientPickerScreen> createState() => _ClientPickerScreenState();
}

class _ClientPickerScreenState extends State<ClientPickerScreen> {
  List<Client>? _all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    widget.repo.list().then((all) {
      if (mounted) setState(() => _all = all);
    });
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final shown = [
      for (final c in all ?? const <Client>[])
        if (_query.isEmpty ||
            textMatches(c.name, _query) ||
            digitsOf(_query).isNotEmpty && c.phone.contains(digitsOf(_query)))
          c,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Vincular a um cliente')),
      body: all == null
          ? const Center(child: CircularProgressIndicator())
          : all.isEmpty
          ? const EmptyState(
              title: 'Nenhum cliente ainda.',
              message: 'Use "Cadastrar" para salvar este contato como cliente.',
            )
          : Column(
              children: [
                AppSearchField(
                  hint: 'Buscar clientes',
                  onChanged: (q) => setState(() => _query = q.trim()),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.only(
                      bottom: listBottomPadding(context),
                    ),
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final c = shown[i];
                      return AppListTile(
                        leading: InitialsAvatar(c.name),
                        title: Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(formatPhone(c.phone)),
                        onTap: () => Navigator.pop(context, c),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
