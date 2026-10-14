import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The strip on top of a conversation with someone who is not a client
///: "Cadastrar", "Vincular" or "Ignorar".
class NewContactStrip extends StatelessWidget {
  const NewContactStrip({
    super.key,
    required this.onRegister,
    required this.onLink,
    required this.onIgnore,
  });

  final VoidCallback onRegister;
  final VoidCallback onLink;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Material(
      color: c.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        // Wraps instead of overflowing with large text.
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Symbols.person_add_rounded,
                    size: 20,
                    color: c.onSecondaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Contato novo',
                      style: Theme.of(context).textTheme.labelLarge!
                          .copyWith(color: c.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onRegister, child: const Text('Cadastrar')),
            TextButton(onPressed: onLink, child: const Text('Vincular')),
            TextButton(onPressed: onIgnore, child: const Text('Ignorar')),
          ],
        ),
      ),
    );
  }
}
