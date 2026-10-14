import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'brand_mark.dart';

/// An amount in evidence: the display face, aligned digits.
class MoneyText extends StatelessWidget {
  const MoneyText(this.text, {super.key, this.small = false, this.color});

  final String text;

  /// A smaller size, for totals inside a card.
  final bool small;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    // One line, smaller when there is no room (large text).
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        text,
        maxLines: 1,
        style: (small ? t.headlineSmall : t.displaySmall)!.copyWith(
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Whether the system text is large (150% or more): rows and pairs of
/// fields go one under the other.
bool largeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) >= 15;

/// "1 item", "3 itens".
String plural(int n, String one, String many) => n == 1 ? '1 $one' : '$n $many';

/// Aligned digits for amounts and dates inside running text and lists.
const tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// A group heading inside a list: "Devendo", "Hoje".
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: t.labelLarge!.copyWith(color: c.onSurfaceVariant),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// What an empty screen says: the situation and the next step, with the
/// Garoto's face above.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.action,
    this.onAction,
  });

  final String title;
  final String? message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 64),
            const SizedBox(height: 16),
            Text(title, style: t.titleLarge, textAlign: TextAlign.center),
            if (message case final m?) ...[
              const SizedBox(height: 8),
              Text(
                m,
                style: t.bodyMedium!.copyWith(color: c.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
            if (action case final a? when onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(a)),
            ],
          ],
        ),
      ),
    );
  }
}

/// A round avatar with the initials of [name], 40 dp.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.name, {super.key, this.size = 40});

  final String name;
  final double size;

  /// "Ana Souza" → "AS"; "ana" → "A"; digits only → "#".
  static String initials(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where(
          (w) => w.isNotEmpty && RegExp(r'\p{L}', unicode: true).hasMatch(w[0]),
        )
        .toList();
    if (words.isEmpty) return '#';
    final first = words.first.characters.first.toUpperCase();
    if (words.length == 1) return first;
    return first + words.last.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: c.secondaryContainer,
      foregroundColor: c.onSecondaryContainer,
      child: Text(
        initials(name),
        style: Theme.of(context).textTheme.titleSmall!
            .copyWith(color: c.onSecondaryContainer),
      ),
    );
  }
}

/// The search at the top of a list: a filled pill, always there.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Symbols.search_rounded),
          filled: true,
          fillColor: c.surfaceContainerHigh,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: c.primary, width: 2),
          ),
        ),
      ),
    );
  }
}

/// Room under a list for the floating buttons ([fabs] stacked) and the
/// system bar.
double listBottomPadding(
  BuildContext context, {
  bool fab = false,
  int fabs = 1,
}) => (fab ? 28 + 68.0 * fabs : 24) + MediaQuery.paddingOf(context).bottom;

/// The "cliente" mark next to a conversation of a client.
class ClientMark extends StatelessWidget {
  const ClientMark({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.tertiaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Text(
          'cliente',
          style: Theme.of(context).textTheme.labelSmall!
              .copyWith(color: c.onTertiaryContainer),
        ),
      ),
    );
  }
}

/// A list row: 64 dp or more, leading, title and subtitle,
/// and a trailing part (amount, pill) that grows with large text instead
/// of overflowing, as [ListTile] would. Also lighter than [ListTile],
/// which lays its texts out again for the baselines: a new row cost 2 to
/// 3 ms on the Redmi.
class AppListTile extends StatelessWidget {
  const AppListTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
  });

  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    // With large text the trailing part goes under the texts, which keep
    // the whole width.
    final below = trailing != null && largeText(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              if (leading case final l?) ...[l, const SizedBox(width: 16)],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextStyle.merge(style: t.titleMedium, child: title),
                    if (subtitle case final s?)
                      DefaultTextStyle.merge(
                        style: t.bodyMedium!.copyWith(color: muted),
                        child: s,
                      ),
                    if (below) ...[
                      const SizedBox(height: 4),
                      DefaultTextStyle.merge(
                        style: t.labelLarge,
                        child: trailing!,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing case final tr? when !below) ...[
                const SizedBox(width: 12),
                // With large text a big amount wraps instead of pushing
                // the title out.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.4,
                  ),
                  child: DefaultTextStyle.merge(style: t.labelLarge, child: tr),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
