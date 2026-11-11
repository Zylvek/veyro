//! Каркас приложения (спека docs/UI_SPEC.md, разделы Desktop layout /
//! Android layout). Desktop: постоянный левый сайдбар 240 px + отзывчивый
//! контент. Узкие экраны (Android): нижняя навигация.
//!
//! Разделы, не реализованные к текущей группе разработки, отображаются
//! ЧЕСТНО: «группа N» — без имитации содержимого. Каждая следующая группа
//! заменяет свои заглушки реальными экранами (docs/UI_SPEC.md — порядок).

import 'package:flutter/material.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';

import '../screens/backup_screen.dart';
import '../screens/network_settings_screen.dart';
import '../screens/wallets_screen.dart';
import '../screens/about_screen.dart';

/// Раздел каркаса.
class ShellDestination {
  /// Стабильный идентификатор (не индекс — списки desktop/mobile различаются).
  final String id;
  final IconData icon;
  final String label;

  /// Экран раздела. Для заглушек — null (отображается честная карточка).
  final WidgetBuilder? builder;

  /// Группа разработки (спека «Development sequence»), в которой раздел
  /// получает реализацию. Для готовых разделов 0.
  final int pendingGroup;

  const ShellDestination({
    required this.id,
    required this.icon,
    required this.label,
    this.builder,
    this.pendingGroup = 0,
  });

  bool get available => builder != null && pendingGroup == 0;
}

/// Реестр разделов каркаса. Группа 1: реальны Кошельки, Бэкап, Сеть,
/// О программе; Обзор и Активы — честные заглушки группы 2.
const List<ShellDestination> kShellDestinations = [
  ShellDestination(
    id: 'overview',
    icon: Icons.space_dashboard_outlined,
    label: 'Обзор',
    pendingGroup: 2,
  ),
  ShellDestination(
    id: 'assets',
    icon: Icons.grid_view_outlined,
    label: 'Активы',
    pendingGroup: 2,
  ),
  ShellDestination(
    id: 'wallets',
    icon: Icons.wallet_outlined,
    label: 'Кошельки',
    builder: _buildWallets,
  ),
  ShellDestination(
    id: 'backup',
    icon: Icons.backup_outlined,
    label: 'Бэкап',
    builder: _buildBackup,
  ),
  ShellDestination(
    id: 'network',
    icon: Icons.public_outlined,
    label: 'Сеть',
    builder: _buildNetwork,
  ),
  ShellDestination(
    id: 'about',
    icon: Icons.info_outline,
    label: 'О VEYRO',
    builder: _buildAbout,
  ),
];

Widget _buildWallets(BuildContext context) => const WalletsScreen();
Widget _buildBackup(BuildContext context) => const BackupScreen();
Widget _buildNetwork(BuildContext context) => const NetworkSettingsScreen();
Widget _buildAbout(BuildContext context) => const AboutScreen();

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
      (d) => d.id == widget.initialDestination && d.available,
      orElse: () => kShellDestinations
          .firstWhere((d) => d.id == 'wallets'),
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
                  child: const _Sidebar(),
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
        child: _current.builder?.call(context) ?? ShellStubScreen(dest: _current),
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
                          ),
                        ),
                        Text(
                          'YOUR CRYPTO. YOUR CONTROL.',
                          style: TextStyle(
                            fontSize: 8.5,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w600,
                            color: VColors.textSecondary,
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
                      onTap: dest.available
                          ? () {
                              final shell =
                                  context.findAncestorStateOfType<_VeyroShellState>();
                              shell?._selectById(dest.id);
                            }
                          : null,
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Некастодиально.\nПодпись — локально в Rust-ядре.',
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
  final VoidCallback? onTap;

  const _NavItem({
    required this.dest,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final available = dest.available;
    final color = available
        ? (selected ? VColors.primary : VColors.textSecondary)
        : VColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? VColors.elevated : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: selected
              ? Border.all(color: VColors.primary.withValues(alpha: 0.4))
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
          dense: true,
          enabled: available,
          selected: selected,
          visualDensity: VisualDensity.compact,
          leading: Icon(dest.icon, size: 20, color: color),
          title: Text(
            dest.label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: available ? VColors.textPrimary : VColors.textSecondary,
            ),
          ),
          trailing: available
              ? (selected
                  ? Icon(Icons.arrow_right, color: VColors.primary, size: 20)
                  : null)
              : VStatusChip('группа ${dest.pendingGroup}', kind: VChipKind.neutral),
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
    final items = kShellDestinations.where((d) => d.available).toList();
    return NavigationBar(
      selectedIndex: items.indexWhere((d) => d.id == currentId).clamp(0, items.length - 1),
      destinations: [
        for (final dest in items)
          NavigationDestination(
            icon: Icon(dest.icon),
            selectedIcon: Icon(dest.icon, color: VColors.primary),
            label: dest.label,
          ),
      ],
      onDestinationSelected: (index) => onSelect(items[index].id),
    );
  }
}

/// Честная заглушка нереализованного раздела: имя группы по спеке,
/// никакого имитированного содержимого.
class ShellStubScreen extends StatelessWidget {
  final ShellDestination dest;

  const ShellStubScreen({super.key, required this.dest});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(dest.label)),
      body: VScreen(
        child: VCard(
          icon: Icons.schedule,
          title: 'Раздел в разработке',
          children: [
            Text(
              'Раздел «${dest.label}» реализуется группой ${dest.pendingGroup} '
              'по принятой спецификации UI (docs/UI_SPEC.md, Development '
              'sequence). Имитировать содержимое не допускается — этот экран '
              'сознательно пуст до своей группы.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
