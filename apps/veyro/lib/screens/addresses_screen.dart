//! Экран 7: управление адресами. Сканирование адресов аккаунта живым вызовом
//! btc_sync (gap-limit): адреса с ончейн-историей + следующие свободные адреса
//! получения и сдачи. Копирование по тапу; предупреждение о повторном
//! использовании.

import 'package:flutter/material.dart';

import 'package:veyro/src/rust/api/btc.dart';
import 'package:veyro/util/ui_helpers.dart';

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key});

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  BtcSyncDto? _sync;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sync = await btcSync(gapLimit: 20);
      if (!mounted) return;
      setState(() {
        _sync = sync;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Адреса BTC')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: _buildContent(context),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContent(BuildContext context) {
    if (_loading) {
      return const [
        Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_error != null) {
      return [
        Text('Ошибка: $_error'),
        const SizedBox(height: 10),
        FilledButton.tonal(onPressed: _reload, child: const Text('Повторить')),
      ];
    }
    final sync = _sync!;
    final used = sync.usedAddresses;

    return [
      SectionCard(
        title: 'Следующий адрес получения',
        icon: Icons.add_location_alt_outlined,
        children: [
          _addressTile(context, sync.nextReceive, showCopy: true),
          const Text(
            'Это адрес, который кошелёк покажет следующим для получения — '
            'он ещё не использован.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Следующий адрес сдачи',
        icon: Icons.output_outlined,
        children: [
          _addressTile(context, sync.nextChange, showCopy: false),
          const Text(
            'Используется ядром для сдачи при отправках (внутренняя ветка '
            'm/84’/1’/0’/1).',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Адреса с историей (${used.length})',
        icon: Icons.location_on_outlined,
        children: [
          if (used.isEmpty)
            const Text(
              'Ни один адрес ещё не имеет ончейн-истории.',
              style: TextStyle(color: Colors.white70),
            )
          else
            ...[
              for (final a in used)
                _addressTile(context, a, showCopy: true),
            ],
        ],
      ),
      const SizedBox(height: 12),
      const Text(
        'Тап по адресу копирует его. Не используйте один адрес для многократных '
        'получений — это видно в блокчейне и снижает приватность.',
        style: TextStyle(color: Colors.white38, fontSize: 12),
      ),
    ];
  }

  Widget _addressTile(
    BuildContext context,
    BtcAddressDto address, {
    required bool showCopy,
  }) {
    final branchLabel = address.branch == 0 ? 'получение' : 'сдача';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  address.address,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
                Text(
                  '${address.path} · $branchLabel · индекс ${address.index}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          if (showCopy)
            IconButton(
              tooltip: 'Копировать',
              icon: const Icon(Icons.copy_outlined, size: 18),
              onPressed: () => copyToClipboard(context, 'Адрес', address.address),
            ),
        ],
      ),
    );
  }
}
