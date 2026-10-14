import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../products/money.dart';
import 'motion.dart';

/// The space between two fields of a form: 16. Between groups
/// of fields it is [FormGroupGap].
class FormGap extends StatelessWidget {
  const FormGap({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(height: 16);
}

/// Two fields side by side when there is room (480 or more), one under the
/// other with the usual gap when there is not: fewer lines to scroll on
/// wide windows, the same form on a phone.
class FormPair extends StatelessWidget {
  const FormPair({super.key, required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxWidth < 480) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [first, const FormGap(), second],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: 16),
          Expanded(child: second),
        ],
      );
    },
  );
}

/// The space between two groups of a form: 24.
class FormGroupGap extends StatelessWidget {
  const FormGroupGap({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(height: 24);
}

/// The body of a form: text buttons and links sit on the same
/// left edge as the fields (no inner margin of their own), still with a
/// 48 high touch target. Wrap the whole scrollable body in it.
class FormBody extends StatelessWidget {
  const FormBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textButtonTheme.style ?? const ButtonStyle();
    return Theme(
      data: theme.copyWith(
        textButtonTheme: TextButtonThemeData(
          style: base.merge(
            TextButton.styleFrom(
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
              minimumSize: const Size(48, 48),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
          ),
        ),
      ),
      child: child,
    );
  }
}

/// Masks while typing. Pure, so they are tested
/// alone; the cursor always goes to the end.
abstract final class Masks {
  /// "1290" → "R$ 12,90": the digits are cents, pushed in from the right.
  static final money = _Mask((digits) {
    if (digits.isEmpty) return '';
    final trimmed = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (trimmed.length > 12) return null;
    return formatMoney(int.parse(trimmed));
  });

  /// "13102026" → "13/10/2026"; also "0503" → "05/03" (birthdays).
  static final date = _Mask((d) {
    if (d.length > 8) return null;
    return [
      d.substring(0, d.length.clamp(0, 2)),
      if (d.length > 2) d.substring(2, d.length.clamp(2, 4)),
      if (d.length > 4) d.substring(4),
    ].join('/');
  });

  /// "01001000" → "01001-000".
  static final cep = _Mask((d) {
    if (d.length > 8) return null;
    return d.length <= 5 ? d : '${d.substring(0, 5)}-${d.substring(5)}';
  });

  /// "5511987654321" → "+55 11 98765-4321".
  static final phone = _Mask((d) {
    if (d.length > 15) return null;
    if (d.isEmpty) return '';
    final cc = d.substring(0, d.length.clamp(0, 2));
    if (d.length <= 2) return '+$cc';
    final ddd = d.substring(2, d.length.clamp(2, 4));
    if (d.length <= 4) return '+$cc $ddd';
    final rest = d.substring(4);
    final number = rest.length > 4
        ? '${rest.substring(0, rest.length - 4)}-${rest.substring(rest.length - 4)}'
        : rest;
    return '+$cc $ddd $number';
  });

  /// CPF "000.000.000-00" up to 11 digits, CNPJ "00.000.000/0000-00" after.
  static final document = _Mask((d) {
    if (d.length > 14) return null;
    String put(String pattern) {
      final out = StringBuffer();
      var i = 0;
      for (final ch in pattern.split('')) {
        if (i >= d.length) break;
        out.write(ch == '0' ? d[i++] : ch);
      }
      return out.toString();
    }

    return d.length <= 11 ? put('000.000.000-00') : put('00.000.000/0000-00');
  });
}

/// A mask over the digits typed: [format] answers the text to show, or
/// null to refuse the change (too long).
class _Mask extends TextInputFormatter {
  _Mask(this.format);

  final String? Function(String digits) format;

  /// The masked text of [input], for initial values.
  String apply(String input) =>
      format(input.replaceAll(RegExp(r'\D'), '')) ?? input;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    // Deleting only a mask character (a dot, a slash) deletes the digit
    // before it, or nothing would change.
    final oldDigits = oldValue.text.replaceAll(RegExp(r'\D'), '');
    if (newValue.text.length < oldValue.text.length &&
        digits == oldDigits &&
        digits.isNotEmpty) {
      digits = digits.substring(0, digits.length - 1);
    }
    final text = format(digits);
    if (text == null) return oldValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// A money field: number keyboard and "R$ 12,90" while
/// typing. The text is read with `parseMoney`.
class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    required this.controller,
    required this.label,
    this.error,
    this.hint,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final String? error;
  final String? hint;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    keyboardType: TextInputType.number,
    inputFormatters: [Masks.money],
    decoration: InputDecoration(
      labelText: label,
      hintText: hint ?? 'R\$ 0,00',
      errorText: error,
    ),
  );
}

/// Starts [controller] with [cents] in the money mask; empty for null.
TextEditingController moneyController([int? cents]) =>
    TextEditingController(text: cents == null ? '' : formatMoney(cents));

/// A group of "Mais detalhes": the title and a one-line
/// summary of what is filled in; a tap opens it.
class DetailsGroup extends StatelessWidget {
  const DetailsGroup({
    super.key,
    required this.title,
    required this.open,
    required this.onToggle,
    required this.children,
    this.summary,
    this.icon,
  });

  final String title;

  /// What is filled in, shown when closed; null when nothing is.
  final String? summary;
  final IconData? icon;
  final bool open;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onToggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                  child: Row(
                    children: [
                      if (icon case final i?) ...[
                        Icon(i, size: 22, color: colors.onSurfaceVariant),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(title, style: t.titleSmall),
                            if (summary case final s? when !open)
                              Text(
                                s,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodySmall!.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: Motion.of(context, Motion.state),
                        child: Icon(
                          Symbols.expand_more_rounded,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: Motion.of(context, Motion.state),
              curve: Motion.standard,
              alignment: Alignment.topCenter,
              child: open
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 12,
                        children: children,
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}
