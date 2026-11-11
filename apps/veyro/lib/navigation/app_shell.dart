//! Каркас приложения (спека docs/UI_SPEC.md, разделы Desktop layout /
//! Android layout). Desktop: постоянный левый сайдбар 240 px + отзывчивый
//! контент. Узкие экраны (Android): нижняя навигация.
//!
//! С группы 4 все семь разделов каркаса — реальные экраны (Обзор, Активы,
//! Кошельки, Адресная книга, Бэкап, Настройки, О VEYRO). Настройки сети —
//! раздел «Настройки» (и центр управления BTC); дочерние экраны
//! (детали актива, BTC, Receive/Send) открываются push-навигацией.

import 'package:flutter/material.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/screens/asset_catalog_screen.dart';
import 'package:veyro/screens/dashboard_screen.dart';

import '../screens/settings_screen.dart';
import '../screens/transactions_screen.dart';
import '../screens/wallets_screen.dart';

/// Раздел каркаса. Все разделы реализованы (builder обязателен).
class ShellDestination {
  /// Стабильный идентификатор (не индекс — списки desktop/mobile различаются).
  final String id;
  final IconData icon;
  final String label;
  final WidgetBuilder builder;

  const ShellDestination({
    required this.id,
    required this.icon,
    required this.label,
    required this.builder,
  });
}

/// Реестр разделов каркаса (решение владельца): Обзор, Активы, Транзакции,
/// Кошельки, Настройки — пять пунктов навигации. Бэкап, «О VEYRO» и
/// адресная книга открываются из «Настроек» (карточка «Разделы»);
/// раздел «Транзакции» при закрытой сессии показывает честное состояние.
const List<ShellDestination> kShellDestinations = [
  ShellDestination(
    id: 'overview',
    icon: Icons.space_dashboard_outlined,
    label: 'Обзор',
    builder: _buildOverview,
  ),
  ShellDestination(
    id: 'assets',
    icon: Icons.grid_view_outlined,
    label: 'Активы',
    builder: _buildAssets,
  ),
  ShellDestination(
    id: 'transactions',
    icon: Icons.receipt_long_outlined,
    label: 'Транзакции',
    builder: _buildTransactions,
  ),
  ShellDestination(
    id: 'wallets',
    icon: Icons.wallet_outlined,
    label: 'Кошельки',
    builder: _buildWallets,
  ),
  ShellDestination(
    id: 'settings',
    icon: Icons.tune_outlined,
    label: 'Настройки',
    builder: _buildSettings,
  ),
];

Widget _buildOverview(BuildContext context) => const DashboardScreen();
Widget _buildAssets(BuildContext context) => const AssetCatalogScreen();
Widget _buildTransactions(BuildContext context) => const TransactionsScreen();
Widget _buildWallets(BuildContext context) => const WalletsScreen();
Widget _buildSettings(BuildContext context) => const SettingsScreen();
/// Порог, ниже которого каркас переключается на нижнюю навигацию
/// (Android-телефон); десктопные окна шире и получают сайдбар 240 px.
const double kShellWideBreakpoint = 960;

/// Ширина постоянного сайдбара (спека: ~240 px).
const double kSidebarWidth = 240;

/// Каркас приложения: выбранный раздел + рамка навигации.
class VeyroShell extends StatefulWidget {
  final String initialDestination;

  const VeyroShell({super.key, this.initialDestination = 'wallets'});

  @override
  State<VeyroShell> createState() => _VeyroShellState();
}

class _VeyroShellState extends State<VeyroShell> {
  late ShellDestination _current;

  @override
  void initState() {
    super.initState();
    _current = kShellDestinations.firstWhere(
      (d) => d.id == widget.initialDestination,
      orElse: () => kShellDestinations.firstWhere((d) => d.id == 'wallets'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= kShellWideBreakpoint;
    return wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: kSidebarWidth,
                child: KeyedSubtree(
                  key: const Key('shell-sidebar'),
                  // НЕ const: сайдбар обязан перестраиваться при каждом
                  // переключении раздела, иначе подсветка выбранного
                  // элемента замерзает на стартовой вкладке.
                  child: _Sidebar(),
                ),
              ),
              const VerticalDivider(width: 1, color: VColors.elevated),
              Expanded(child: _content()),
            ],
          )
        : Scaffold(
            body: _content(),
            bottomNavigationBar: _BottomNav(
              currentId: _current.id,
              onSelect: (id) => _selectById(id),
            ),
          );
  }

  Widget _content() => KeyedSubtree(
        key: ValueKey(_current.id),
        child: _current.builder(context),
      );

  void _selectById(String id) {
    final dest = kShellDestinations.firstWhere((d) => d.id == id);
    setState(() => _current = dest);
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    final shell = context.findAncestorStateOfType<_VeyroShellState>();
    final selection = shell!._current;
    return ColoredBox(
      color: VColors.surface,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  const VeyroLogo(size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'VEYRO',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                            letterSpacing: 3,
                            color: VColors.textPrimary,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        Text(
                          'YOUR CRYPTO. YOUR CONTROL.',
                          style: TextStyle(
                            fontSize: 8.5,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w600,
                            color: VColors.textSecondary,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                children: [
                  for (final dest in kShellDestinations)
                    _NavItem(
                      dest: dest,
                      selected: dest.id == selection.id,
                      onTap: () {
                        final shell =
                            context.findAncestorStateOfType<_VeyroShellState>();
                        shell?._selectById(dest.id);
                      },
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Некастодиально. Подпись — локально в Rust-ядре.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall!
                    .copyWith(fontSize: 10.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final ShellDestination dest;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.dest,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? VColors.primary : VColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          // Заливка плюс рамка: выбранный раздел виден сразу (отзыв
          // владельца — «не показывается, в какой я вкладке»).
          color: selected ? VColors.primary.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: selected
              ? Border.all(color: VColors.primary.withValues(alpha: 0.75), width: 1.4)
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            dense: true,
            selected: selected,
            visualDensity: VisualDensity.compact,
            leading: Icon(dest.icon, size: 20, color: color),
            title: Text(
              dest.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? VColors.textPrimary : VColors.textSecondary,
                decoration: TextDecoration.none,
              ),
            ),
            trailing: selected
                ? const Icon(Icons.arrow_right,
                    color: VColors.primary, size: 20)
                : null,
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final String currentId;
  final ValueChanged<String> onSelect;

  const _BottomNav({required this.currentId, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex:
          kShellDestinations.indexWhere((d) => d.id == currentId).clamp(0, kShellDestinations.length - 1),
      destinations: [
        for (final dest in kShellDestinations)
          NavigationDestination(
            icon: Icon(dest.icon),
            selectedIcon: Icon(dest.icon, color: VColors.primary),
            label: dest.label,
          ),
      ],
      onDestinationSelected: (index) => onSelect(kShellDestinations[index].id),
    );
  }
}
