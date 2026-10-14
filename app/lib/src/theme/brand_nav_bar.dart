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

/// The side bar of tablets and computers: the Garoto's face
/// on top, the sections in a column and the settings at the bottom. Same
/// look as [BrandNavBar]: the active one in a green pill with the pink ";".
class BrandNavRail extends StatelessWidget {
  const BrandNavRail({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
    this.onSettings,
  });

  final List<BrandNavItem> items;
  final int selected;
  final ValueChanged<int> onSelected;
  final VoidCallback? onSettings;

  static const width = 88.0;

  /// The width with the system text at [scale]: wider when it is large,
  /// so the names still fit under the icons.
  static double widthFor(double scale) => scale <= 1.15 ? width : 120.0;

  static double itemHeight(double scale) => scale <= 1.15 ? 72 : 96;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(right: BorderSide(color: c.outlineVariant)),
      ),
      child: SizedBox(
        width: widthFor(scale),
        child: SafeArea(
          right: false,
          child: FocusTraversalGroup(
            child: Column(
              children: [
                const SizedBox(height: 20),
                const BrandMark(size: 44),
                const SizedBox(height: 20),
                for (final (i, item) in items.indexed)
                  _RailItem(
                    item: item,
                    active: i == selected,
                    onTap: () => onSelected(i),
                  ),
                const Spacer(),
                if (onSettings != null)
                  Tooltip(
                    message: 'Configurações',
                    child: IconButton(
                      onPressed: onSettings,
                      icon: const Icon(Symbols.settings_rounded),
                      color: c.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final BrandNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
    final label = Theme.of(context).textTheme.labelMedium!.copyWith(
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
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: BrandNavRail.widthFor(scale) - 8,
          height: BrandNavRail.itemHeight(scale),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: 56,
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
