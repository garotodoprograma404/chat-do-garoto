import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'brand_mark.dart';

/// One section in [BrandNavBar].
class BrandNavItem {
  const BrandNavItem(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// The bottom bar with the channel's look: the active section in a solid
/// neon green pill, its name in green with the pink ";", the others quiet.
class BrandNavBar extends StatelessWidget {
  const BrandNavBar({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  final List<BrandNavItem> items;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              for (final (i, item) in items.indexed)
                Expanded(
                  child: _Item(
                    item: item,
                    active: i == selected,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.item, required this.active, required this.onTap});

  final BrandNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final label = t.labelMedium!.copyWith(
      color: active ? c.primary : c.onSurfaceVariant,
      fontWeight: active ? FontWeight.w800 : FontWeight.w500,
    );
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: 60,
              height: 32,
              decoration: ShapeDecoration(
                shape: const StadiumBorder(),
                color: active ? c.primary : Colors.transparent,
              ),
              child: Icon(
                item.icon,
                size: 24,
                fill: active ? 1 : 0,
                weight: active ? 600 : 400,
                color: active ? c.onPrimary : c.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.label, style: label, maxLines: 1),
                  if (active)
                    Text(
                      ';',
                      style: label.copyWith(
                        color: Brand.pinkFor(Theme.of(context).brightness),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The app's five sections, in order.
const brandSections = [
  BrandNavItem(Symbols.home_rounded, 'Início'),
  BrandNavItem(Symbols.chat_rounded, 'Conversas'),
  BrandNavItem(Symbols.group_rounded, 'Clientes'),
  BrandNavItem(Symbols.inventory_2_rounded, 'Produtos'),
  BrandNavItem(Symbols.point_of_sale_rounded, 'Vendas'),
];
