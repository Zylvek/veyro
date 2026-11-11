//! Экран 4: получение. Свежий адрес получения из ядра (btc_receive_address —
//! следующий свободный индекс после последней синхронизации) + QR-код + путь
//! деривации. Адрес и путь — единственные данные; никакой выдумки.

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:veyro/src/rust/api/btc.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/util/ui_helpers.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  BtcAddressDto? _address;
  BtcSessionStateDto? _state;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final state = await btcSessionState();
      final address = await btcReceiveAddress();
      if (!mounted) return;
      setState(() {
        _state = state;
        _address = address;
        _error = null;
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
    final network = _state?.networkDisplay ?? 'сеть не определена';
    return Scaffold(
      appBar: AppBar(title: const Text('Получение BTC')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                title: 'Адрес получения ($network)',
                icon: Icons.qr_code_2_outlined,
                children: _buildContent(context),
              ),
              const SizedBox(height: 12),
              const Text(
                'После каждой получения средств и каждой отправки выполните '
                'синхронизацию на экране BTC — тогда этот адрес сменится на '
                'следующий свободный. Повторное использование адреса снижает '
                'приватность.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
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
        Text('$_error'),
        const SizedBox(height: 10),
        FilledButton.tonal(onPressed: _load, child: const Text('Повторить')),
      ];
    }
    final address = _address;
    if (address == null) {
      return const [Text('Адрес недоступен')];
    }
    final branchLabel =
        address.branch == 0 ? 'получение (внешняя ветка)' : 'сдача (внутренняя ветка)';
    return [
      Center(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView(
            data: address.address,
            version: QrVersions.auto,
            size: 220,
            gapless: true,
          ),
        ),
      ),
      const SizedBox(height: 14),
      const Text('Адрес', style: TextStyle(color: Colors.white60, fontSize: 12)),
      SelectableText(
        address.address,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          FilledButton.icon(
            onPressed: () => copyToClipboard(context, 'Адрес', address.address),
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Копировать адрес'),
          ),
        ],
      ),
      const SizedBox(height: 6),
      kvRow('Путь', address.path, mono: true),
      kvRow('Ветка', branchLabel),
      kvRow('Индекс', '${address.index}'),
    ];
  }
}
