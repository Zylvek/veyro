# Технический паспорт монеты: ETC

> Паспорт составлен по состоянию на 11 ноября 2026. Критические параметры
> подтверждены минимум двумя независимыми источниками; ключевые
> идентификаторы (chain ID, генезис, coin type) — прямыми JSON-RPC-проверками
> публичных эндпоинтов. Неподтверждённое помечено `НЕ ПОДТВЕРЖДЕНО`.

- **Тикер(ы):** ETC (Ethereum Classic; у пулов синонимов нет)
- **Официальное название проекта:** Ethereum Classic
- **Официальный сайт:** https://ethereumclassic.com (график апгрейдов,
  счётчик эмиссии); сайт сообщества https://ethereumclassic.org
- **Официальный репозиторий:** «официального» клиента проект не назначает
  (дисклеймер: нет официального разработчика/клиента/сайта). Исторически
  поддерживаемый клиент — https://github.com/etclabscore/core-geth (форк
  go-ethereum); спорный дубль — https://github.com/ethereumclassic/core-geth
  (см. «Безопасность»)
- **Официальная документация:** https://ethereumclassic.com/upgrades
  (хардфорки и ECIP), https://github.com/ethereumclassic/ECIPs
- **Статус исследования:** завершено (desk research + прямые RPC-проверки,
  ноябрь 2026; транзакционные тесты не проводились)

## Идентификация сети

- **Mainnet:**
  - Chain ID **61** (`0x3d`) — проверено RPC `eth_chainId` на двух независимых
    эндпоинтах (`etc.etcdesktop.com`, `rpc.etcmc.xyz`); подтверждено реестрами
    (ethereum-lists/chains, chainlist). Network ID **1** — проверено RPC
    `net_version` (унаследован от исходной цепи Ethereum).
  - Genesis-хэш:
    `0xd4e56740f876aef8c010b86a40d5f56745a118d0906a34e69aec8c0db1cb8fa3`
    (получен напрямую `eth_getBlockByNumber("0x0")` на двух эндпоинтах) —
    канонический генезис Ethereum mainnet: ETC продолжает исходную цепь
    Ethereum после раскола на блоке 1 920 000 (июль 2016, The DAO).
  - Consensus: PoW **Etchash** (ECIP-1099 «Thanos», активация ноябрь 2020 —
    модифицированный Ethash с уменьшенной эпохой DAG; до этого Ethash).
    Блок ≈ 13 с.
  - Эмиссия ECIP-1017 «5M20»: −20 % каждые 5 000 000 блоков. Текущая эра 6 —
    с блока 25 000 001 (~22.07.2026): **1,6384 ETC/блок** (таблица эмиссии в
    Википедии, официальный счётчик ethereumclassic.com, независимые трекеры).
    Полной крычки предложения нет (эмиссия асимптотическая).
  - Сеть жива: ~25,71 млн блоков (etc.blockscout.com), цена ≈ $6,70
    (CoinGecko, 2026-11-11).
- **Testnet:** **Mordor**, chain ID **63** (`0x3f`) — проверено RPC
  (`rpc.mordor.etccooperative.org`); genesis
  `0xa68ebde7932eccb177d38d55dcc6461a019dd795a681e59b5a3e4f3a7259a3f1`
  (получен RPC; extraData «phoenix chicken absurd banana», 2019-10-03).
- **Проверка идентичности:** двусмысленности нет. ETC — оригинальная цепь
  Ethereum (тот же генезис, network ID 1, chain ID 61, Etchash-PoW, coin type
  61 в SLIP-44); тикер закреплён пулами и биржами.

## Криптография и ключи

- **Формат адреса:** `0x`-hex, 20 байт, чексумма EIP-55 (стандарт EVM).
- **Формат публичного ключа:** secp256k1, 64/65 байт (как Ethereum).
- **Формат приватного ключа:** 32 байта; hex `0x…`, keystore JSON (V3) —
  форматы Ethereum, совместимы.
- **Схема деривации ключей:** BIP32/BIP44, SLIP-44 coin type **61**:
  `m/44'/61'/a'/0/i` (регистрация SLIP-44 + таблица путей прошивки Trezor).
- **Мнемонический стандарт:** BIP39.
- **Алгоритм подписи:** ECDSA secp256k1; защита от повторного воспроизведения —
  EIP-155 с chainId 61.
- **Совместимость восстановления из фразы:** основная сетевая практика —
  `m/44'/61'`. Возможные расхождения (использование ETH-пути 60' в части
  кошельков) в рамках исследования НЕ ПРОВЕРЕНЫ — при импорте фразы сверять
  адрес с эталонным кошельком; расширенный импорт с выбором пути (61'/60')
  повышает совместимость.

## Транзакции

- **Структура транзакции:** стандартная EVM: legacy type-0 (RLP; nonce,
  gasPrice, gasLimit, to, value, data, v/r/s). EIP-1559 на mainnet **не
  активирован** — `eth_feeHistory` возвращает baseFee = 0 (проверено RPC);
  отправлять legacy-транзакции с `gasPrice`.
- **Расчёт комиссии:** gas × gasPrice; оценка — `eth_gasPrice` +
  `eth_estimateGas`.
- **Блокировки/имматурность:** аккаунтная модель, coinbase-имматурности для
  получателей нет; из-за PoW-реоргов переводы подтверждать несколькими
  блоками.
- **Модель баланса:** account/nonce.
- **Особые поля:** нет (memo/tag отсутствуют).

## Доступ к сети

- **Методы RPC:** стандартный EVM-набор: `eth_chainId`, `net_version`,
  `eth_blockNumber`, `eth_getBalance`, `eth_getTransactionCount`,
  `eth_gasPrice`, `eth_estimateGas`, `eth_feeHistory`,
  `eth_sendRawTransaction`, `eth_getTransactionReceipt`,
  `eth_getBlockByNumber`, `eth_getLogs`, `eth_call`. Ключевые методы
  проверены напрямую 2026-11-11 (chainId, net_version, feeHistory, getLogs,
  генезис/высота).
- **P2P-протокол:** devp2p (стек go-ethereum); кошельком не используется.
- **Лёгкий клиент:** отсутствует (нативного SPV нет) — доступ через RPC.
- **Узел:** основной клиент — **Core Geth** (`etclabscore/core-geth`, форк
  go-ethereum v1.13.14; лицензии LGPL-3.0/GPL-3.0). Поддерживаемая линия
  релизов: **Argos v1.12.23** (предшественники: Aegis v1.12.21, Hermes
  v1.12.22). Клиентское разнообразие есть: **Getc** (Rust), **Nethermind**
  (плагин ETC), **Hyperledger Besu** (плагин ETC).
- **Публичные RPC:** `https://etc.etcdesktop.com`, `https://rpc.etcmc.xyz`
  (проверены, живы); из chainlist дополнительно: 0xrpc.io/etc, tatum.io,
  swiftnodes, routeme.sh (живость НЕ ПРОВЕРЯЛАСЬ). Mordor:
  rpc.mordor.etccooperative.org (проверен), geth-mordor.etc-network.info,
  0xrpc.io/mordor. Приватность: публичный RPC видит запрашиваемые адреса —
  допускать пользовательские эндпоинты, не направлять все запросы на один
  сервер.
- **Explorer:** https://etc.blockscout.com (Blockscout; REST API v2 работает —
  проверено), https://etcerscan.com, OKLink (ETC), tokenview.com (живость
  последних НЕ ПРОВЕРЯЛАСЬ).

## SDK и библиотеки

- **Официальные SDK:** ETC-специфичные не требуются — стандартный EVM-стек
  (ethers.js, web3.js, alloy). Отличия от Ethereum: chainId 61, coin type 61',
  legacy-газ.
- **Rust-библиотеки:** `alloy`/`ethers-rs` (MIT OR Apache-2.0) — транзакции,
  подпись, RLP; `k256` (MIT OR Apache-2.0) — secp256k1.
- **Flutter/Dart-интеграции:** готовые Dart-EVM-клиенты существуют (web3dart
  и аналоги; лицензии проверить при подключении); подпись держать в
  Rust-ядре VEYRO.
- **Лицензии зависимостей:** узловое ПО (Core Geth, GPL/LGPL) в кошелёк не
  включается; кошелечный стек (alloy, k256, BIP32/39) — MIT OR Apache-2.0.
  Совместимо с ядром VEYRO.

## Совместимость кошелька

Отметка = реализуемо существующими средствами (фактический статус — только
после тестов):

- [x] Создание кошелька — BIP39/BIP32, coin type 61
- [x] Импорт кошелька — фраза / приватный ключ / keystore
- [x] Восстановление — `m/44'/61'` (сетевой стандарт)
- [x] Получение — `0x` EIP-55; URI `ethereum:0x…@61` (EIP-681)
- [x] Баланс — `eth_getBalance`
- [x] История транзакций — `eth_getLogs` по адресам окнами (проверено);
  для нативных переводов (не ERC-20) — сканирование блоков или публичный
  Blockscout API v2 (etc.blockscout.com/api/v2)
- [x] Отправка — сборка legacy-tx, подпись ECDSA EIP-155 (chainId 61),
  `eth_sendRawTransaction`
- [x] Мониторинг подтверждений — `eth_getTransactionReceipt` + поллинг
  (wss-подписки на публичных RPC НЕ ПРОВЕРЕНЫ)

## Безопасность и ограничения

- **Клиентский конфликт (сентябрь 2026, операционный риск):** 14.09.2026
  репозиторий `ethereumclassic/core-geth` выпустил v1.13.0 (96 коммитов за
  56 часов без внешнего ревью), продвигался аккаунтом @ETC_Network как
  «обновление безопасности»; релиз повторно включил MESS (выключен через
  ECIP-1110) и заменил bootnode/дискавери-инфраструктуру. Инцидент-репорт
  Classix (16.09.2026) классифицировал релиз как «rogue» и рекомендовал
  Argos v1.12.23; затронутые узлы пулов (2Miners) откатились. Блоков и
  средств не потеряно. Для кошелька некритично (узел не запускаем), но это
  индикатор спора мейнтейнеров вокруг инфраструктуры ETC.
- **51%-атаки:** в августе 2020 зафиксированы три атаки с реоргами (тысячи
  блоков). MESS-защита отключена (ECIP-1110). Входящие переводы подтверждать
  несколькими блоками; для крупных сумм — повышенный порог подтверждений.
- **Legacy-газ:** не отправлять EIP-1559-структуры (baseFee = 0).
- **Приватность:** публичные RPC видят адреса.
- **Блокеры:** нет.

## Вывод для матрицы

- **Идентичность:** подтверждена (генезис/chain ID/network ID — RPC на двух
  независимых эндпоинтах + реестры; coin 61 — SLIP-44 + Trezor; ≥ 2
  источника по каждому критическому параметру).
- **Реализуемость:** полная — минимальные отличия от Ethereum (chainId, coin
  type, legacy-газ); EVM-стек VEYRO переиспользуется целиком.
- **Главный риск:** PoW-уязвимость к реоргам (история 51%-атак 2020) и
  клиентская смута вокруг Core Geth v1.13.0.
- **Предлагаемый статус:** `Research required` → после полного тестового
  цикла кандидат на `Full support` (среди пяти EVM-активов — первый по
  простоте реализации). До тестов статус не менять.

## Источники

1. Прямые RPC-проверки 2026-11-11: `etc.etcdesktop.com`, `rpc.etcmc.xyz`,
   `rpc.mordor.etccooperative.org` — eth_chainId (0x3d), net_version (1),
   eth_getBlockByNumber (генезис 0xd4e56740…; Mordor genesis
   0xa68ebde7…), eth_feeHistory (baseFee=0), eth_getLogs
2. https://ethereumclassic.com/upgrades — официальный график хардфорков ETC
   (в т.ч. ECIP-1099 «Thanos»/Etchash)
3. https://ethereumclassic.com/block-reward-countdown — официальная модель
   эмиссии 5M20 (−20 % каждые 5 000 000 блоков, ~13 с/блок)
4. https://en.wikipedia.org/wiki/Ethereum_Classic — таблица эмиссии
   (25 000 001 → 1,6384 ETC), Etchash, история сети (раскол на блоке
   1 920 000)
5. https://github.com/satoshilabs/slips/blob/master/slip-0044.md — SLIP-44:
   coin type 61 (ETC)
6. https://docs.trezor.io/trezor-firmware/misc/coins-bip44-paths.html —
   путь 44'/61' в прошивке Trezor (независимое подтверждение)
7. https://github.com/etclabscore/core-geth — поддерживаемый клиент (форк
   go-ethereum v1.13.14); линия релизов Aegis/Hermes/Argos (v1.12.21–23)
8. https://crypto.news/ethereum-classic-miners-reverse-core-geth-v1-13-0-migration-after-warning/ —
   разбор инцидента Core Geth v1.13.0 (14–17.09.2026): rogue-релиз, MESS,
   замена дискавери-инфраструктуры, рекомендация Argos v1.12.23; упоминание
   51%-атак августа 2020
9. https://etc.blockscout.com — Blockscout-инстанс ETC (API v2 проверен;
   высота ~25,71 млн блоков)
10. https://chainlist.org/chain/61 — публичные RPC mainnet/Mordor
11. https://www.coingecko.com/en/coins/ethereum-classic — цена ≈ $6,70
    (2026-11-11)
