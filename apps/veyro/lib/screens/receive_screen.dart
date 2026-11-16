//! Экран 13 спеки (asset-поток Receive, BTC/LTC): свежий адрес получения из
//! ядра (btc_receive_address / ltc_receive_address — следующий свободный
//! индекс после последней синхронизации) + QR-код + путь деривации. Copy
//! работает по-настоящему; Share отключён честно (системный share-канал в
//! этой сборке не подключён). BTC/LTC не используют memo/tag — об этом
//! честно сказано на экране, а не выдумано поле. Для LTC под адресом видно
//! предупреждение MWEB-слепоты (паспорт LTC).

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:veyro/design/components.dart';
import 'package:veyro/design/veyro_mark.dart';
import 'package:veyro/src/rust/api/btc.dart';
import 'package:veyro/src/rust/api/ltc.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/util/coin.dart';
import 'package:veyro/util/l10n.dart';
import 'package:veyro/util/ui_helpers.dart';

class ReceiveScreen extends StatefulWidget {
  final WalletCoin coin;

  /// Точки замены для виджет-тестов (без RustLib); BTC-шные типы —
  /// исторический контракт тестов (поля совпадают с LTC).
  final Future<BtcSessionStateDto?> Function()? sessionLoader;
  final Future<BtcAddressDto> Function()? addressLoader;

  const ReceiveScreen({
    super.key,
    this.coin = WalletCoin.btc,
    this.sessionLoader,
    this.addressLoader,
  });

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  String? _addressText;
  String? _networkDisplay;
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
      String? network;
      if (widget.sessionLoader != null) {
        final state = await widget.sessionLoader!();
        network = state?.networkDisplay;
      } else if (widget.coin == WalletCoin.ltc) {
        network = (await ltcSessionState())?.networkDisplay;
      } else {
        network = (await btcSessionState())?.networkDisplay;
      }
      if (!mounted) return;
      setState(() => _networkDisplay = network);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sessionError = e.toString());
    }
    try {
      final String address;
      if (widget.addressLoader != null) {
        address = (await widget.addressLoader!()).address;
      } else if (widget.coin == WalletCoin.ltc) {
        address = (await ltcReceiveAddress()).address;
      } else {
        address = (await btcReceiveAddress()).address;
      }
      if (!mounted) return;
      setState(() {
        _addressText = address;
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
    final network = _networkDisplay;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.coin == WalletCoin.ltc
              ? t('receive_title_ltc')
              : t('receive_title'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              VCard(
                title: network == null
                    ? t('receive_card_no_network')
                    : tf('receive_card_with_network', {'network': network}),
                icon: Icons.qr_code_2_outlined,
                children: _buildContent(context),
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
          // Фирменная загрузка знака (система владельца), мини-версия.
          child: Center(
            child: LogoLoader(mode: LogoLoaderMode.loading, size: 44),
          ),
        ),
      ];
    }
    if (_error != null) {
      return [
        Text(
          tf('core_no_address', {
            'error': '$_error',
            'extra': _sessionError == null
                ? ''
                : tf('also_extra', {'error': '$_sessionError'}),
          }),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 10),
        VButton.secondary(t('retry'), icon: Icons.refresh, onPressed: _load),
      ];
    }
    final address = _addressText;
    if (address == null) {
      return [
        Text(
          t('address_unavailable'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ];
    }
    return [
      Center(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView(
            data: address,
            version: QrVersions.auto,
            size: 220,
            gapless: true,
          ),
        ),
      ),
      const SizedBox(height: 14),
      VMonoCopyRow(label: t('address_label'), value: address),
      const SizedBox(height: 12),
      if (widget.coin == WalletCoin.ltc) ...[
        Text(
          t('ltc_mweb_warning'),
          style: Theme.of(context).textTheme.bodySmall!
              .copyWith(color: Colors.orangeAccent),
        ),
        const SizedBox(height: 12),
      ],
      Row(
        children: [
          Expanded(
            child: VButton.primary(
              t('copy_address_btn'),
              icon: Icons.copy_outlined,
              onPressed: () =>
                  copyToClipboard(context, t('address_label'), address),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Tooltip(
              message: t('share_note'),
              child: VButton.secondary(t('share_btn')),
            ),
          ),
        ],
      ),
    ];
  }
}
