# Технический паспорт монеты: QUAI

> Паспорт составлен по состоянию на 11 ноября 2026. Chain ID, генезис,
> лимиты getLogs, строгий EIP-55 и protobuf-формат транзакций проверены
> прямыми RPC. Coin type подтверждён исходниками официального SDK + SLIP-44.
> Неподтверждённое помечено `НЕ ПОДТВЕРЖДЕНО`.

- **Тикер(ы):** QUAI (Quai Network; второй нативный актив — QI, UTXO-леджер;
  у пулов используется QUAI)
- **Официальное название проекта:** Quai Network (sharded PoW, консенсус
  PoEM — Proof of Entropy Minima)
- **Официальный сайт:** https://qu.ai
- **Официальный репозиторий:** https://github.com/dominant-strategies/go-quai
  (узел; GPL-3.0; активен, ~2,4 тыс. звёзд); SDK —
  https://github.com/dominant-strategies/quais.js
- **Официальная документация:** https://docs.qu.ai (полный индекс —
  docs.qu.ai/llms.txt; сборка, транзакции, SDK, майнинг, токеномика)
- **Статус исследования:** завершено (desk research + прямые RPC-проверки,
  ноябрь 2026; транзакционные тесты не проводились)

## Идентификация сети

- **Mainnet:**
  - Запуск mainnet — январь 2025 (29.01.2025 по данным экосистемы/прессы;
    в рамках исследования дата напрямую не перепроверялась).
  - Шардированная сеть; **единственный активный шард — cyprus-1** (region 0,
    zone 0). Остальные шарды (cyprus-2/3, paxos-1/2/3, hydra-1/2/3)
    задокументированы, но не запущены (официальные доки).
  - Chain ID **9** (`0x9`) для cyprus-1 — проверено напрямую RPC `eth_chainId`
    на официальном эндпоинте `https://rpc.quai.network/cyprus1`;
    подтверждено официальными доками (chainId 9 mainnet). RPC принимает
    методы с префиксами и `eth_*`, и `quai_*` (проверено).
  - Genesis-хэш cyprus-1:
    `0xac81c28f1a72591b87b5f16c9793cdc0e87c45c6d426d1a364c3b8f6386b5b8b`
    (получен RPC `eth_getBlockByNumber("0x0")`; вторым независимым
    источником НЕ ПОДТВЕРЖДЁН).
  - Сеть жива: ~10,78 млн блоков (RPC, 2026-11-11); цена ≈ $0,0067,
    капитализация ≈ $7,75 млн (CoinGecko, 2026-11-11).
  - Токеномика: эмиссия = генезисные разлоки (после «Singularity Fork»
    база 1 332 840 016 QUAI) + майнинг; программа SOAP перенаправляет
    субсидии merge-mining родительских цепей (BCH/LTC/DOGE/RVN) на выкуп
    QUAI и сжигание (~180 млн QUAI/год).
- **Testnet:** **Orchard**, chain ID **15000** (cyprus-1); RPC
  `https://orchard.rpc.quai.network/cyprus1`, GraphQL
  orchard.graph.quai.network, кран `https://orchard.faucet.quai.network`;
  локальная сеть — chain ID 1337. По официальным докам; RPC-проверка Orchard
  НЕ ПРОВЕРЯЛАСЬ.
- **Проверка идентичности:** двусмысленности нет: QUAI — Quai Network
  (официальный RPC + доки + эксплореры; SLIP-44 994 = QUAI, 969 = QI).
  Критический нюанс: **два нативных актива** — QUAI (account-модель,
  EVM-подобный) и Qi (UTXO-модель, приватность); поддерживаются разными
  типами транзакций и разными coin types (см. ниже).

## Криптография и ключи

- **Формат адреса:** `0x`-hex, 20 символов (40 hex), чексумма **EIP-55
  строгая** (RPC отклоняет адрес с неверной чексуммой — проверено). Первый
  9 бит адреса — идентификационный префикс шарда: биты 0–3 — region, биты
  4–7 — zone, бит 8 — леджер (0 = Quai, 1 = Qi). Активному шарду cyprus-1
  соответствуют Quai-адреса с префиксом `0x00…`/`0x0…` и Qi-адреса с
  битом 8 = 1. В SDK — валидаторы `isQuaiAddress`/`isQiAddress` и зона по
  префиксу.
- **Формат публичного ключа:** secp256k1 (33/66 hex для Qi-входов).
- **Формат приватного ключа:** 32 байта; hex `0x…` (класс `Wallet`).
- **Схема деривации ключей:** BIP32/BIP44, два coin type'а:
  - QUAI — coin type **994** (`m/44'/994'/a'/0/i`): константа `_coinType
    = 994` в исходнике `QuaiHDWallet` официального SDK + регистрация
    SLIP-44 (994 = QUAI);
  - Qi — coin type **969**: константа `_coinType = 969` в исходнике
    `QiHDWallet` + SLIP-44 (969 = QI); внешние/сдачные адреса
    `m/44'/969'/a'/0/i` (BIP44-кошельки external/change), платёжные коды
    BIP47 — `m/47'/969'`.
- **Мнемонический стандарт:** BIP39.
- **Алгоритм подписи:** QUAI — ECDSA secp256k1 (v/r/s); Qi — **Schnorr**
  (один вход) и **MuSig** (агрегированная подпись при нескольких входах);
  в SDK используются `@noble/curves/secp256k1` (schnorr) и
  `@brandonblack/musig`.
- **Совместимость восстановления из фразы:** одна BIP39-фраза даёт два
  независимых набора адресов (994' — QUAI, 969' — Qi). Ключи
  secp256k1-совместимы с Ethereum по кривой, но адресное пространство
  шардированное; сторонних кошельков с 994'/969' мало — восстановление
  в других кошельках ограничено (Pelagus, MetaMask Snap).

## Транзакции

- **Кодировка:** **Protobuf wire-format, не RLP** (проверено: RPC
  `eth_sendRawTransaction` отклонил RLP-сырые данные — «proto: cannot
  parse invalid wire-format data»). Для VEYRO нужен protobuf-энкодер
  транзакций (генерация .proto по официальным докам/исходникам).
- **Типы транзакций** (официальные доки):
  - **Type 0 — Quai** (account-модель, один шард): EVM-подобная структура
    (from, to, value, gas, gasPrice, nonce, input, accessList); подписи
    ECDSA (v/r/s); chainId + nonce — защита от повторного воспроизведения;
    **EIP-1559-стиль** ценообразования газа; поддержка accessList
    (EIP-2930-стиль). Это рабочий тип для переводов QUAI в cyprus-1.
  - **Type 1 — ETX (External Transaction)**: протокольные транзакции
    (7 подтипов: кросс-шардовые, coinbase, conversion, coinbaseLockup,
    wrapQi, conversionRevert, unwrapQi) — **пользователем не создаются**,
    подписей не содержат.
  - **Type 2 — Qi** (UTXO): входы `txIns` (previousOutPoint + pubkey),
    выходы `txOuts` (адрес + denomination); подписи Schnorr/MuSig; полей
    gas/data нет. В SDK: coin-селекторы (Fewest/Aggregate/Conversion),
    статусы адресов (USED/UNUSED/ATTEMPTED_USE), gap-limit сканирование,
    мелкая единица «Qits» (1000 Qits = 1 Qi — из исходника SDK; полная
    таблица номиналов НЕ ПРОВЕРЕНА).
- **Конвертация QUAI ↔ Qi** — протокольная (Type 1): RPC-методы
  `quaiToQi`/`qiToQuai`/`calculateConversionAmount`, в SDK —
  `convertToQuai`.
- **Расчёт комиссии:** Quai — газ EIP-1559-стиля (`eth_feeHistory`,
  `eth_gasPrice`, `eth_estimateGas`); Qi — фиксированная комиссия
  (оценивается RPC-методом провайдера `estimateFeeForQi`; детали
  НЕ ПРОВЕРЕНЫ).
- **Блокировки/имматурность:** для QUAI (account-модель) — как в EVM;
  для Qi — возможны lock-выходы (поле lock, проверка по высоте) — детали
  НЕ ПРОВЕРЕНЫ.
- **Модель баланса:** QUAI — account/nonce; Qi — UTXO (outpoints).
- **Особые поля:** шард-префикс адреса (маршрутизация); ETX-поля для
  кросс-шард операций (в начальный охват не входят — активен один шард).

## Доступ к сети

- **Методы RPC:** полный набор `eth_*` (баланс, nonce, gas, sendRawTransaction,
  receipts, getLogs, call, blocks) + namespace `quai_*`; playground в доках.
  Проверено напрямую 2026-11-11: eth_chainId, eth_blockNumber,
  eth_getBlockByNumber (генезис), валидация чексуммы адресов (отклонение
  неверной), `eth_getLogs` — **работает, лимит диапазона 10 000 блоков**
  (проверено: больший диапазон отклоняется), отправка protobuf/отклонение
  RLP.
- **P2P-протокол:** собственный (стек go-quai); кошельком не используется.
- **Лёгкий клиент:** нет — доступ через RPC.
- **Узел:** `dominant-strategies/go-quai` (GPL-3.0; активен). Майнинг:
  KawPoW-софт (SRBMiner-Multi, Rigel, WildRig Multi), пулы (2Miners,
  HeroMiners, Kryptex, K1Pool «quaikawpow», StratumX, AlphaPool, PowerPool,
  MiningDutch и др.) + merge-mining AuxPoW с родительскими цепями
  (BCH/LTC/DOGE/RVN) через SOAP.
- **Публичные RPC:** `https://rpc.quai.network/cyprus1` (официальный, https;
  жив, проверен) + wss-аналог и GraphQL `https://graph.quai.network` (по
  докам; wss НЕ ПРОВЕРЕН). Orchard — см. «Testnet». Другие публичные
  провайдеры НЕ ПОДТВЕРЖДЕНЫ; допускать пользовательские эндпоинты.
- **Explorer:** https://quaiscan.io (mainnet), https://orchard.quaiscan.io
  (Orchard), https://explorer.qu.ai; API-лимиты НЕ ПРОВЕРЕНЫ.
- **Кошельки экосистемы:** Pelagus (браузерное расширение), MetaMask Snap.

## SDK и библиотеки

- **Официальные SDK:** `quais.js` (npm `quais`; **MIT**, форк ethers v6,
  активно развивается): классы `Wallet` (приватный ключ), `QuaiHDWallet`
  (BIP44, 994), `QiHDWallet` (BIP44, 969 + BIP47-платёжные коды),
  `JsonRpcProvider`/`BrowserProvider`, транзакции Quai/Qi, конвертации.
- **Rust-библиотеки:** официальный **Rust SDK** `quai-sdk`
  **0.1.0-alpha.14** (crates.io; семейство: quai-primitives, quai-abi,
  quai-rpc, quai-provider — quai-provider 0.1.0-alpha.3, MIT, релиз
  15.09.2026). Состав: типизированный RPC, точные суммы/адреса, подпись
  Quai/Qi-транзакций, HD-кошельки, платёжные коды, ABI, «durable native
  wallet». **Статус — экспериментальная альфа, «not approved for
  production wallet use»** (заявление сопровождающих на lib.rs). Для
  протокола подписи — `k256`/чистые реализации Schnorr (MIT OR
  Apache-2.0) + собственный protobuf-энкодер.
- **Flutter/Dart-интеграции:** готовых нет; использовать Rust-ядро VEYRO
  (нативный путь: адаптация quai-sdk после стабилизации или собственная
  реализация по quais.js как эталону).
- **Лицензии зависимостей:** узел go-quai — GPL-3.0 (в кошелёк не
  включается); quais.js — MIT; quai-sdk — MIT (но альфа); secp256k1/Schnorr
  — MIT OR Apache-2.0. Совместимо с ядром VEYRO.

## Совместимость кошелька

Отметка = реализуемо существующими средствами (фактический статус — только
после тестов). Начальный охват — **только QUAI (Type 0) в cyprus-1**:

- [x] Создание кошелька — BIP39/BIP32, coin type 994 (совместимо с
  quais.js/Pelagus)
- [x] Импорт кошелька — фраза / приватный ключ (класс Wallet)
- [x] Восстановление — `m/44'/994'` (стандарт официального SDK)
- [x] Получение — `0x` EIP-55 (строгая валидация чексуммы + префикса
  cyprus-1); URI-схема для платёжных ссылок НЕ ПОДТВЕРЖДЕНА (в доках не
  описана — определить при реализации)
- [x] Баланс — `eth_getBalance` (проверено)
- [x] История транзакций — `eth_getLogs` окнами ≤ 10 000 блоков (проверено)
  + поллинг блоков; для готовой истории — API quaiscan (лимиты НЕ
  ПРОВЕРЕНЫ)
- [x] Отправка — Type 0: сборка, подпись ECDSA, **protobuf-кодирование**
  (отдельная реализация — генерация энкодера по .proto), бродкаст
  `eth_sendRawTransaction`
- [x] Мониторинг подтверждений — `eth_getTransactionReceipt` + поллинг
  (wss НЕ ПРОВЕРЕН)
- [ ] Qi (Type 2) — вне начального охвата: UTXO-модель, Schnorr/MuSig,
  coin-selection, gap-limit-сканирование, платёжные коды BIP47 — большой
  отдельный объём работ; Rust SDK — альфа, blindly в продакшн не брать

## Безопасность и ограничения

- **Молодая сеть и микрокапитализация** (mainnet 2025, ≈ $7,75 млн):
  повышенный риск делистингов, волатильности, экономических атак.
- **Один активный шард:** шардированная архитектура не развёрнута;
  кросс-шард механика (ETX) неактуальна до запуска новых шардов, но
  усложняет протокол.
- **Protobuf вместо RLP:** стандартные EVM-сериализаторы неприменимы —
  нужен собственный энкодер/десериализатор транзакций Quai (риск
  несовместимости при изменении схемы).
- **Строгий EIP-55:** RPC отклоняет адреса с неверной чексуммой (проверено)
  — валидация обязательна на всех уровнях (нельзя слать lowercase-адреса).
- **Два coin type'а (994/969):** восстановление фразы в сторонних
  кошельках ограничено; UX должен разделять QUAI/Qi-активы.
- **Rust SDK в альфе** — для production-кошелька VEYRO опираться на
  собственную реализацию протокола подписи по quais.js/докам.
- **Централизация инфраструктуры:** один официальный публичный RPC
  (rpc.quai.network).
- **Блокеры:** для QUAI (Type 0) технических нет — требуется
  protobuf-кодер; для Qi — вне MVP (объём работ как отдельная сеть).

## Вывод для матрицы

- **Идентичность:** подтверждена (chainId 9 — RPC + официальные доки;
  coin types 994/969 — исходники SDK + SLIP-44; генезис — RPC).
- **Реализуемость:** частичная. QUAI (Type 0, cyprus-1) — полный цикл
  реализуем после написания protobuf-энкодера транзакций (единственная
  содержательная доработка); Qi (Type 2) — отдельный большой проект
  (UTXO + Schnorr/MuSig + платёжные коды), не входит в MVP.
- **Главный риск:** нестандартный protobuf-формат транзакций (риск
  несовместимости при эволюции протокола) + сложность Qi + микрокап
  молодой сети.
- **Предлагаемый статус:** `Research required` → QUAI: после тестового
  цикла кандидат на `Send supported` → `Full support` (при условии
  protobuf-кодера); Qi: оставить `Research required`/отложить (не
  блокер для QUAI). До тестов статус не менять.

## Источники

1. Прямые RPC-проверки 2026-11-11: `https://rpc.quai.network/cyprus1` —
   eth_chainId (0x9), eth_blockNumber (~10,78 млн), eth_getBlockByNumber
   (генезис 0xac81c28f…), eth_getLogs (лимит диапазона 10 000 блоков),
   отклонение адреса с неверной чексуммой EIP-55, отклонение RLP-сырых
   транзакций («proto: cannot parse invalid wire-format data»)
2. https://docs.qu.ai/llms.txt — официальный индекс документации:
   chainId 9 (mainnet cyprus-1) / 15000 (Orchard) / 1337 (local), RPC
   https/wss, GraphQL, кран, эксплореры, «единственный активный шард
   cyprus-1»
3. https://docs.qu.ai/build/transactions/types — типы транзакций:
   Type 0 (ECDSA, chainId+nonce, 1559-стиль, accessList), Type 1 ETX
   (7 протокольных подтипов, без подписей), Type 2 Qi (UTXO,
   Schnorr/Musig)
4. https://docs.qu.ai/sdk/static/address и
   https://docs.qu.ai/learn/advanced-introduction/hierarchical-structure/sharding —
   9-битный префикс адреса (region/zone/ledger), примеры Quai/Qi-адресов,
   isQuaiAddress/isQiAddress
5. Исходники quais.js (github.com/dominant-strategies/quais.js, коммит
   c1c12d43f…): `src/wallet/quai-hdwallet.ts` (`_coinType = 994`),
   `src/wallet/qi-hdwallet.ts` (`_coinType = 969`, пути m/44'/969'…,
   BIP47 m/47'/969', Schnorr через @noble/curves, MuSig через
   @brandonblack/musig, «1000 Qits = 1 Qi»), `src/wallet/abstract-hdwallet.ts`
   (parentPath `m/44'/coin_type'`, сериализация)
6. https://github.com/satoshilabs/slips/blob/master/slip-0044.md — SLIP-44:
   coin type 994 (QUAI), 969 (QI)
7. https://docs.qu.ai/learn/tokenomics/quai-emissions — эмиссия: Singularity
   Fork (база 1 332 840 016 QUAI), SOAP (merge-mining BCH/LTC/DOGE/RVN,
   выкуп-сжигание ~180 млн QUAI/год)
8. https://docs.qu.ai/guides/miner/pools-software — KawPoW-софт
   (SRBMiner-Multi, Rigel, WildRig) и пулы (2Miners, HeroMiners, Kryptex,
   K1Pool и др.)
9. https://lib.rs/crates/quai-sdk и https://docs.rs/quai-provider —
   официальный Rust SDK (0.1.0-alpha.14; quai-provider 0.1.0-alpha.3, MIT,
   15.09.2026; статус «experimental alpha, not approved for production
   wallet use»)
10. https://github.com/dominant-strategies/go-quai — официальный узел
    (GPL-3.0, активен)
11. https://www.coingecko.com/en/coins/quai-network — цена ≈ $0,0067,
    капитализация ≈ $7,75 млн (2026-11-11)
