//! Экран 13 спеки (asset-поток Receive, BTC): свежий адрес получения из
//! ядра (btc_receive_address — следующий свободный индекс после последней
//! синхронизации) + QR-код + путь деривации. Copy работает по-настоящему;
//! Share отключён честно (системный share-канал в этой сборке не подключён,
//! url_launcher/системный шеринг отсутствуют). BTC не использует memo/tag —
//! об этом честно сказано на экране, а не выдумано поле.

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:veyro/design/components.dart';
import 'package:veyro/src/rust/api/btc.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/util/ui_helpers.dart';

class ReceiveScreen extends StatefulWidget {
  /// Точки замены для виджет-тестов (без RustLib).
  final Future<BtcSessionStateDto?> Function()? sessionLoader;
  final Future<BtcAddressDto> Function()? addressLoader;

  const ReceiveScreen({super.key, this.sessionLoader, this.addressLoader});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  BtcAddressDto? _address;
  BtcSessionStateDto? _state;
  String? _error;
  bool _loading = true;
  String? _sessionError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Состояние сессии — дешёвое чтение; падение не мешает адресу
    // (адрес требует активной сессии, но ошибка сессии показывается
    // как отдельная, честная строка).
    try {
      final loader = widget.sessionLoader;
      final state = loader != null ? await loader() : await btcSessionState();
      if (!mounted) return;
      setState(() => _state = state);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sessionError = e.toString());
    }
    try {
      final loader = widget.addressLoader;
      final address =
          loader != null ? await loader() : await btcReceiveAddress();
      if (!mounted) return;
      setState(() {
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
    final network = _state?.networkDisplay;
    return Scaffold(
      appBar: AppBar(title: const Text('Получение BTC')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              VCard(
                title: network == null
                    ? 'Адрес получения (сеть не определена)'
                    : 'Адрес получения ($network)',
                icon: Icons.qr_code_2_outlined,
                children: _buildContent(context),
              ),
              const SizedBox(height: 12),
              VCard(
                title: 'Memo / tag',
                icon: Icons.label_outline,
                children: [
                  Text(
                    'BTC не использует memo/tag: получателю достаточно '
                    'адреса. Полей для заметок адреса ядро не хранит.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const _PrivacyNote(),
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
        Text(
          'Ядро не вернуло адрес: $_error${_sessionError == null ? '' : '\n(также: $_sessionError)'}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 10),
        VButton.secondary('Повторить', icon: Icons.refresh, onPressed: _load),
      ];
    }
    final address = _address;
    if (address == null) {
      return [
        Text('Адрес недоступен.', style: Theme.of(context).textTheme.bodyMedium)
      ];
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
      VMonoCopyRow(label: 'Адрес', value: address.address),
      const SizedBox(height: 8),
      _kvRow(context, 'Путь', address.path, mono: true),
      _kvRow(context, 'Ветка', branchLabel),
      _kvRow(context, 'Индекс', '${address.index}'),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: VButton.primary(
              'Копировать адрес',
              icon: Icons.copy_outlined,
              onPressed: () =>
                  copyToClipboard(context, 'Адрес', address.address),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Tooltip(
              message: 'Системный Share появится в Android-группе: '
                  'канал шерингa в этой сборке не подключён.',
              child: VButton.secondary('Поделиться'),
            ),
          ),
        ],
      ),
    ];
  }
}

/// Строка «ключ → значение» на токенах темы (аналог kvRow без
/// жёстко-белых цветов, чтобы совпадать с новой системой).
Widget _kvRow(BuildContext context, String key, String value,
    {bool mono = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(key, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: mono
              ? VMono(value, fontSize: 12.5)
              : SelectableText(value, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    ),
  );
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Адрес выдаётся ядром по последней синхронизации: после получения '
      'средств или отправки выполните синхронизацию в центре управления '
      'BTC — адрес сменится на следующий свободный. Повторное '
      'использование адреса снижает приватность.',
      style: Theme.of(context).textTheme.bodySmall,
      textAlign: TextAlign.center,
    );
  }
}
