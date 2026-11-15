//! Реестр активов VEYRO — данные переносены из утверждённой матрицы
//! совместимости (docs/COIN_COMPATIBILITY.md, 26 строк после решения
//! владельца от 12.11.2026: удалены фиктивный тикер XTR и незапущенный
//! Tari L2/Ootle «TARI» — сети и кошелька нет, показывать нельзя).
//! ЗАПРЕЩЕНО выдавать researched-актив за реализованный: баланс и
//! транзакции показываются только для активов с реальным адаптером
//! (сейчас — BTC и LTC receive-only).
//!
//! Синхронизация: при изменении матрицы — обновить таблицу и тест-счётчики
//! (ui_spec_group2_test.dart).

import 'package:veyro/design/components.dart';
import 'package:veyro/util/l10n.dart';

/// Жизненный цикл актив: только по вердиктам матрицы.
enum AssetLifecycle {
  /// Исследование завершено; реализации и тестов не было.
  researched('Исследовано', VChipKind.neutral),

  /// Отправка проверена на тестнете; полный цикл не заявлен (BTC).
  sendSupported('Отправка проверена (testnet)', VChipKind.success),

  /// Приём проверен вживую (genesis-чек + адрес + баланс/история);
  /// отправка ещё не заявлена (LTC, receive-only milestone).
  receiveSupported('Приём проверен (live)', VChipKind.success),

  /// Исследование не завершено.
  researchRequired('Требует изучения', VChipKind.warning),

  /// Нет безопасной реализации; блокер указан.
  blocked('Заблокировано', VChipKind.error),

  /// Исторический тикер, не актив.
  historical('Исторический тикер', VChipKind.neutral);

  final String label;
  final VChipKind chipKind;
  const AssetLifecycle(this.label, this.chipKind);

  /// Локализованная метка статуса (словарь l10n); [label] — русская
  /// база для тестов и логов.
  String get labelLocalized {
    switch (this) {
      case researched:
        return t('lc_researched');
      case sendSupported:
        return t('lc_send_supported');
      case receiveSupported:
        return t('lc_receive_supported');
      case researchRequired:
        return t('lc_research_required');
      case blocked:
        return t('lc_blocked');
      case historical:
        return t('lc_historical');
    }
  }
}

/// Актив реестра. `note` — сжатая версия матричной строки; полные
/// исследования лежат в docs/coins/<ТИКЕР>.md (см. [passport]).
class VeyroAsset {
  /// Номер строки в матрице (для трассировки).
  final int row;

  /// Верифицированный тикер (по матрице).
  final String ticker;

  /// Официальное имя.
  final String name;

  /// Короткая сетевая идентичность (уровень, тип).
  final String network;

  /// Вердикт матрицы.
  final AssetLifecycle lifecycle;

  /// Реализован ли адаптер в ядре (есть реальные балансы/транзакции).
  final bool implemented;

  /// Паспорт исследования в репозитории.
  final String passport;

  /// Сжатое честное примечание.
  final String note;

  const VeyroAsset({
    required this.row,
    required this.ticker,
    required this.name,
    required this.network,
    required this.lifecycle,
    this.implemented = false,
    required this.passport,
    required this.note,
  });
}

/// Полный реестр — 28 строк матрицы, порядок сохранён.
const List<VeyroAsset> kAssetRegistry = [
  VeyroAsset(
    row: 1,
    ticker: 'PRL',
    name: 'Pearl',
    network: 'L1 · PoUW (AI-вычисления)',
    lifecycle: AssetLifecycle.researched,
    passport: 'docs/coins/PRL.md',
    note: 'Taproot-only; SDK только Go — клиент пишем сами; формат '
        'мнемоники не подтверждён — восстановление не обещать.',
  ),
  VeyroAsset(
    row: 2,
    ticker: 'QTC',
    name: 'Quantus Network',
    network: 'L1 · Substrate · постквантовая',
    lifecycle: AssetLifecycle.researched,
    passport: 'docs/coins/QTC.md',
    note: 'ML-DSA-87; BIP39-24. Конфликт тикера с Qubitcoin — сверять '
        'по сети/адресу, предупреждение в UI обязательно.',
  ),
  VeyroAsset(
    row: 3,
    ticker: 'QUAI',
    name: 'Quai Network',
    network: 'L1 · sharded PoW',
    lifecycle: AssetLifecycle.researched,
    passport: 'docs/coins/QUAI.md',
    note: 'Активен шард cyprus-1; транзакции protobuf; Qi (UTXO) вне '
        'MVP; узел/SDK GPL-3.0 — только внешний доступ.',
  ),
  VeyroAsset(
    row: 4,
    ticker: 'XTM',
    name: 'Minotari (Tari L1)',
    network: 'L1 · Mimblewimble · гибридный PoW',
    lifecycle: AssetLifecycle.researched,
    passport: 'docs/coins/XTM.md',
    note: 'Seed 24 слова — НЕ BIP39 (cipher seed); Tari L2/Ootle — '
        'протокол без запущенной сети, кошелька нет: активом не '
        'считается (решение владельца).',
  ),
  VeyroAsset(
    row: 6,
    ticker: 'IRON',
    name: 'Iron Fish',
    network: 'L1 · PoW (privacy)',
    lifecycle: AssetLifecycle.blocked,
    passport: 'docs/coins/IRON.md',
    note: 'Блокер: непропатченный consensus-инфляционный баг, миграции '
        'балансов нет, официальная поддержка снята 30.10.2026.',
  ),
  VeyroAsset(
    row: 7,
    ticker: 'XEL',
    name: 'XELIS',
    network: 'L1 · BlockDAG (Rust)',
    lifecycle: AssetLifecycle.researched,
    passport: 'docs/coins/XEL.md',
    note: 'Нативная мнемоника 24+1 (не BIP39); bech32 `xel:`; privacy-'
        'очередь №3.',
  ),
  VeyroAsset(
    row: 8,
    ticker: 'RVN',
    name: 'Ravencoin',
    network: 'L1 · PoW KAWPOW',
    lifecycle: AssetLifecycle.researched,
    passport: 'docs/coins/RVN.md',
    note: 'Base58 R…/r… (без SegWit); зрелый Electrum-стек; бэкенды '
        'только Core ≥ v4.8.0.',
  ),
  VeyroAsset(
    row: 9,
    ticker: 'ERG',
    name: 'Ergo',
    network: 'L1 · eUTXO + Sigma',
    lifecycle: AssetLifecycle.researched,
    passport: 'docs/coins/ERG.md',
    note: 'Адреса P2PK `9…`; ergo-lib (CC0) — лучший профиль группы; '
        'storage rent ~4 года — предупреждение майнеру.',
  ),
  VeyroAsset(
    row: 10,
    ticker: 'CFX',
    name: 'Conflux Network',
    network: 'L1 · eSpace (EVM) + Core Space',
    lifecycle: AssetLifecycle.researched,
    passport: 'docs/coins/CFX.md',
    note: 'Приоритет eSpace (chain 1030, полный EVM); Core Space вне MVP; '
        'предупреждение о путанице пространств.',
  ),
  VeyroAsset(
    row: 11,
    ticker: 'NEXA',
    name: 'Nexa',
    network: 'L1 · Bitcoin Unlimited',
    lifecycle: AssetLifecycle.researched,
    passport: 'docs/coins/NEXA.md',
    note: 'Cashaddr `nexa:`; Schnorr; «Big»-ключи — модуль BTC не '
        'переиспользуется; maturity 5000 блоков.',
  ),
  VeyroAsset(
    row: 12,
    ticker: 'XNA',
    name: 'Neurai',
    network: 'L1 · PoW KAWPOW',
    lifecycle: AssetLifecycle.researched,
    passport: 'docs/coins/XNA.md',
    note: 'Двойная деривация (coin 0 и 1900) — импорт сканирует оба '
        'пути; майнинговые выплаты — legacy N…',
  ),
  VeyroAsset(
    row: 13,
    ticker: 'XMR',
    name: 'Monero',
    network: 'L1 · CryptoNote PoW',
    lifecycle: AssetLifecycle.researched,
    passport: 'docs/coins/XMR.md',
    note: 'Полный цикл без нашего сервера: remote node или локальная '
        'нода; privacy-очередь №1; предупреждение о приватности '
        'remote nodes.',
  ),
  VeyroAsset(
    row: 14,
    ticker: 'ZEPH',
    name: 'Zephyr Protocol',
    network: 'L1 · форк Monero',
    lifecycle: AssetLifecycle.researched,
    passport: 'docs/coins/ZEPH.md',
    note: '4 нативных актива (ZPH/ZSD/ZRS/ZYS), asset_type в RPC; '
        'privacy-очередь №2 после XMR.',
  ),
  VeyroAsset(
    row: 15,
    ticker: 'ETC',
    name: 'Ethereum Classic',
    network: 'L1 · EVM (chain 61)',
    lifecycle: AssetLifecycle.researched,
    passport: 'docs/coins/ETC.md',
    note: 'Legacy-газ без EIP-1559; testnet Mordor; первый кандидат '
        'EVM-группы по простоте.',
  ),
  VeyroAsset(
    row: 16,
    ticker: 'ETHW',
    name: 'EthereumPoW',
    network: 'L1 · EVM (Ethash)',
    lifecycle: AssetLifecycle.researched,
    passport: 'docs/coins/ETHW.md',
    note: 'Chain 10001; ключи идентичны Ethereum — анти-путаница в UI; '
        'testnet нет, один публичный RPC.',
  ),
  VeyroAsset(
    row: 17,
    ticker: 'OCTA',
    name: 'OctaSpace',
    network: 'L1 · EVM-форк (GPU-рынок)',
    lifecycle: AssetLifecycle.researched,
    passport: 'docs/coins/OCTA.md',
    note: 'Chain 800001; микрокап: узел заморожен, единственный публичный '
        'RPC — хрупкость; приоритет низкий.',
  ),
  VeyroAsset(
    row: 18,
    ticker: 'ALPH',
    name: 'Alephium',
    network: 'L1 · BlockFlow (16 цепей)',
    lifecycle: AssetLifecycle.researched,
    passport: 'docs/coins/ALPH.md',
    note: 'Официальный SDK только TS (LGPL) — критичное реализуем сами; '
        'консолидация мелких UTXO обязательна.',
  ),
  VeyroAsset(
    row: 19,
    ticker: 'BTC',
    name: 'Bitcoin',
    network: 'L1 · PoW SHA-256d',
    lifecycle: AssetLifecycle.sendSupported,
    implemented: true,
    passport: 'docs/coins/BTC.md',
    note: 'Единственный реализованный адаптер: полный живой цикл на '
        'testnet4 (faucet → self-transfer → broadcast → mempool → '
        'история → lock). Full support не заявляется до app-уровневого '
        'цикла. BIP84 bech32; верифицированные Electrum-серверы; '
        'локальная BIP143-подпись.',
  ),
  VeyroAsset(
    row: 20,
    ticker: 'BCH',
    name: 'Bitcoin Cash',
    network: 'L1 · PoW SHA-256d (форк BTC)',
    lifecycle: AssetLifecycle.researched,
    passport: 'docs/coins/BCH.md',
    note: 'Cashaddr обязателен; sighash ALL|FORKID 0x41 — свой модуль '
        'подписи; 23 живых Electrum-сервера; полугодовые апгрейды.',
  ),
  VeyroAsset(
    row: 21,
    ticker: 'BSV',
    name: 'Bitcoin SV',
    network: 'L1 · PoW (форк BCH)',
    lifecycle: AssetLifecycle.researched,
    passport: 'docs/coins/BSV.md',
    note: 'Внедрение отложено: Electrum-инфраструктуры нет; единый '
        'контролёр протокола; код SV Node в продукт не включать.',
  ),
  VeyroAsset(
    row: 22,
    ticker: 'FB',
    name: 'Fractal Bitcoin',
    network: 'L1 · merge-mined SHA256d',
    lifecycle: AssetLifecycle.researched,
    passport: 'docs/coins/FB.md',
    note: 'Главный риск — путаница BTC↔FB: адреса/ключи идентичны '
        'Bitcoin (защиты обязательны); лёгкой инфраструктуры нет.',
  ),
  VeyroAsset(
    row: 23,
    ticker: 'XEC',
    name: 'eCash',
    network: 'L1 · PoW (форк BCH)',
    lifecycle: AssetLifecycle.researched,
    passport: 'docs/coins/XEC.md',
    note: 'Cashaddr `ecash:`; раскол деривации 899/1899 — сканировать '
        'оба; 3 независимых лёгких пути (Chronik/Electrum/узел).',
  ),
  VeyroAsset(
    row: 24,
    ticker: 'DGB',
    name: 'DigiByte',
    network: 'L1 · PoW (5 алгоритмов)',
    lifecycle: AssetLifecycle.researched,
    passport: 'docs/coins/DGB.md',
    note: 'SPV обязан проверять пер-алго ретаргетинг; официального '
        'SPV/Electrum нет — community-серверы.',
  ),
  VeyroAsset(
    row: 25,
    ticker: 'LTC',
    name: 'Litecoin',
    network: 'L1 · PoW Scrypt',
    lifecycle: AssetLifecycle.receiveSupported,
    implemented: true,
    passport: 'docs/coins/LTC.md',
    note: 'Ядро + UI полностью: ltc1 bech32, m/84\'/2\', genesis-чек, '
        'живые серверы electrum-ltc; приём/баланс/история live, отправка '
        'через общую tx-машину (живой цикл не заявлен). Без MWEB: '
        'обязательное предупреждение о MWEB-слепоте (баланс может быть '
        'неполным ).',
  ),
  VeyroAsset(
    row: 26,
    ticker: 'KAS',
    name: 'Kaspa',
    network: 'L1 · BlockDAG GHOSTDAG',
    lifecycle: AssetLifecycle.researched,
    passport: 'docs/coins/KAS.md',
    note: 'Комиссия по модели mass; подтверждения — blue score; '
        'rusty-kaspa (ISC); для RPC нужен узел с --utxoindex.',
  ),
  VeyroAsset(
    row: 27,
    ticker: 'ZEC',
    name: 'Zcash',
    network: 'L1 · PoW (transparent + shielded)',
    lifecycle: AssetLifecycle.researched,
    passport: 'docs/coins/ZEC.md',
    note: 'Transparent и watch-only (UFVK) — Researched; полный '
        'shielded-цикл — Research required, не заявлять.',
  ),
];

/// Реализованные активы (реальные балансы/транзакции возможны).
List<VeyroAsset> get implementedAssets =>
    kAssetRegistry.where((a) => a.implemented).toList();

/// Честный ценз реестра для отображения (из матрицы).
const int kRegistryResearchedCount = 24;
const int kRegistrySendSupportedCount = 1;
const int kRegistryResearchRequiredCount = 1;
const int kRegistryBlockedCount = 1;
const int kRegistryHistoricalCount = 1;
