//! Экран 8: настройки сети. Выбор сети (mainnet / testnet3 / testnet4) и
//! адрес Electrum-сервера; пользовательский сервер сохраняется в db-настройке
//! `node_endpoints.<code>` (ключ из плана PHASE 4 §5), сеть — в `btc.network`.
//!
//! Честные гарантии (пишем как есть):
//! - seed и приватные ключи не отправляются на сервер — только публичные
//!   Electrum-запросы (скрипты-хэши, истории, broadcast);
//! - генезис-проверка в Rust отклоняет сервер чужой сети при разблокировке;
//! - дефолтный сервер для testnet4 не верифицирован — поле пустое.

import 'package:flutter/material.dart';

import 'package:veyro/util/network_config.dart';
import 'package:veyro/util/ui_helpers.dart';

class NetworkSettingsScreen extends StatefulWidget {
  const NetworkSettingsScreen({super.key});

  @override
  State<NetworkSettingsScreen> createState() => _NetworkSettingsScreenState();
}

class _NetworkSettingsScreenState extends State<NetworkSettingsScreen> {
  int _networkCode = 1;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  final _serverController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final code = await loadNetworkCode();
      final url = await loadServerUrl(code);
      setState(() {
        _networkCode = code;
        _serverController.text = url;
        _loadError = null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _chooseNetwork(int code) async {
    if (code == _networkCode) return;
    final url = await loadServerUrl(code);
    setState(() {
      _networkCode = code;
      _serverController.text = url;
    });
  }

  String? _validateUrl(String url) {
    final lower = url.trim().toLowerCase();
    if (lower.isEmpty) {
      return 'Укажите сервер (tcp://host:port или ssl://host:port).';
    }
    if (!lower.startsWith('tcp://') && !lower.startsWith('ssl://')) {
      return 'URL должен начинаться с tcp:// или ssl:// (пример: '
          'ssl://electrum.qtornado.com:50002).';
    }
    return null;
  }

  Future<void> _save() async {
    final url = _serverController.text.trim();
    final error = _validateUrl(url);
    if (error != null) {
      showError(context, error);
      return;
    }
    if (_networkCode == 0) {
      final ok = await confirmAction(
        context,
        title: 'Переключиться на mainnet?',
        body: 'Mainnet — реальные средства по реальным адресам. Ошибочная '
            'отправка необратима. Для испытаний рекомендуется testnet.',
        confirmLabel: 'Mainnet',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      await saveServerUrl(_networkCode, url);
      await saveNetworkCode(_networkCode);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Сохранено: сеть ${BtcNetworkChoice.byCode(_networkCode)!.title}, '
            'сервер $url'),
      ));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки сети')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_loadError != null)
                Text('Ошибка загрузки настроек: $_loadError')
              else ...[
                SectionCard(
                  title: 'Сеть Bitcoin',
                  icon: Icons.public_outlined,
                  children: [
                    RadioGroup<int>(
                      groupValue: _networkCode,
                      onChanged: (v) {
                        if (v != null) _chooseNetwork(v);
                      },
                      child: Column(
                        children: [
                          for (final choice in BtcNetworkChoice.all)
                            RadioListTile<int>(
                              value: choice.code,
                              title: Text(choice.title),
                              subtitle: Text(choice.note,
                                  style: const TextStyle(fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: 'Electrum-сервер',
                  icon: Icons.dns_outlined,
                  children: [
                    TextField(
                      controller: _serverController,
                      autocorrect: false,
                      enableIMEPersonalizedLearning: false,
                      decoration: InputDecoration(
                        labelText: 'Адрес сервера',
                        hintText: defaultServerUrl(_networkCode) ??
                            'например, ssl://мой-сервер:50002',
                        helperText: _networkCode == 2
                            ? 'Верифицированного testnet4-сервера в списке '
                                'docs/coins/BTC.md нет — укажите свой.'
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Пользовательский адрес сохраняется в настройке '
                      '«node_endpoints.$_networkCode» и применяется при следующей '
                      'разблокировке BTC. Приоритет — над дефолтом.',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Сохранение…' : 'Сохранить'),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Безопасность подключения',
                  icon: Icons.security_outlined,
                  children: const [
                    Text(
                      '• Seed и приватные ключи никогда не покидают Rust-ядро: '
                      'на сервер уходят только хэши скриптов и публичные запросы.\n'
                      '• При разблокировке ядро сверяет genesis-хэш сервера с '
                      'ожидаемым генезисом выбранной сети — сервер чужой сети '
                      'отклоняется.\n'
                      '• По умолчанию выбран testnet3, чтобы не рисковать '
                      'реальными средствами.',
                      style: TextStyle(height: 1.5),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
