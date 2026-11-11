# Технический паспорт монеты: KAS

> Заполнять только по официальным источникам. Всё недоказанное помечено
> `НЕ ПОДТВЕРЖДЕНО`. Данные актуальны на 11.11.2026, все критические параметры
> подтверждены минимум двумя независимыми источниками.

- **Тикер(ы):** KAS (пулы используют «KAS»). Альтернативных тикеров нет.
  Устаревшее обозначение старых кошельков/KDX: путь деривации coin type `972`
  («kaspanet») — легаси, не совместим с современными адресами (см. ниже).
- **Официальное название проекта:** Kaspa
- **Официальный сайт:** https://kaspa.org
- **Официальный репозиторий:** https://github.com/kaspanet/rusty-kaspa
  (Rust-реализация — референсная; Go-узел `kaspad` объявлен переписанным в
  Rust и более не является эталоном)
- **Официальная документация:** https://docs.kaspa.org (гайды, Toccata,
  programmability); https://kaspa.aspectron.org (WASM SDK, RPC-документация:
  PNN, Kaspa Resolver, ports, транзакции, кошельки); справочник Kaspalytics
  Developer Docs (network-parameters, RPC calls, SDKs — сторонний, но
  поддерживается в актуальном состоянии сообществом)
- **Статус исследования:** завершено (реализация не начата)

## Идентификация сети

- **Mainnet:** BlockDAG (GhostDAG), PoW kHeavyHash. Классического chain ID /
  magic-числа в стиле EVM нет — сеть идентифицируется набором консенсусных
  параметров, префиксом адресов и портами по умолчанию:
  - Genesis-блок (checkpoint-genesis): хэш начинается с байтов
    `0x58 0xc2 0xd4 0x19…` (полный хэш — в исходниках rusty-kaspa,
    `consensus/src/genesis/genesis.rs`); genesis timestamp `1637609671037`;
    DAA score genesis = `1312860`.
  - Префикс адресов Bech32: `kaspa:`.
  - Порты по умолчанию (mainnet): P2P `16111`, gRPC `16110` (по умолчанию
    слушает loopback), wRPC `17110` (Borsh) / `18110` (JSON) — wRPC по
    умолчанию **выключен**.
  - Скорость блоков: 10 BPS (blockrate 10 блоков/сек) с хардфорка Crescendo
    (5 мая 2025, ~15:00 UTC; до этого 1 BPS) — README rusty-kaspa,
    docs/crescendo-guide.md.
  - Хардфорк Toccata активирован в mainnet 30 июня 2026 ~16:15 UTC на DAA
    score `474,165,565` (KIP-16/17/20/21: ковенанты/covenant-скрипты,
    ZK-верификаторы, версия транзакции 2, P2P-протокол v10; актуальная
    версия узла — v2.1.0, сентябрь 2026).
- **Testnet:** **testnet-10 (TN10)** — активный публичный тестнет: префикс
  `kaspatest:`, порты P2P `16211`, gRPC `16210`, wRPC `17210`/`18210`; genesis
  начинается с байтов `0xf8 0x96 0xa3…`; Toccata включён там 18.05.2026
  (DAA `467,579,632`), докрывающий слой — 28.05.2026 (DAA `476,232,000`);
  кран https://faucet-testnet.kaspanet.io.
  **testnet-11 — мёртв**: поддержка удалена из rusty-kaspa в v0.17.0 (март
  2025); не использовать. **testnet-12** — временный ковенант-тестнет, не
  публичная цель. Есть devnet (`--devnet`, `kaspadev:`) и simnet (`kaspasim:`).
- **Проверка идентичности:** тикер KAS однозначен: coin type SLIP-44 `111111`
  зарегистрирован за Kaspa; пулы выплачивают на нативные адреса `kaspa:q…`;
  официальный сайт, репозиторий kaspanet и docs.cross-link-ят друг друга;
  explorer kaspa.org/build ↔ kaspa.stream согласованы. Двусмысленности нет.

## Криптография и ключи

- **Формат адреса:** Bech32 (по образцу BIP-173), префикс `kaspa:`
  (mainnet) / `kaspatest:` / `kaspadev:` / `kaspasim:`, нижний регистр.
  Version-байты (payload):
  - `0x00` — P2PK (Schnorr/secp256k1): адрес начинается с `kaspa:q…`;
  - `0x01` — P2PK-ECDSA (легаси);
  - `0x08` — P2SH: адрес начинается с `kaspa:p…`.
  Для приёма выплат пула используется обычный P2PK `kaspa:q…`.
- **Формат публичного ключа:** secp256k1, сжатый (33 байта).
- **Формат приватного ключа:** WIF **не поддерживается**; XPrv (BIP32,
  расширенный ключ) либо «сырой» seed. Кошелёк оперирует мнемоникой →
  seed → XPrv (крейты `kaspa-bip32`, `kaspa-wallet-core`).
- **Схема деривации ключей:** BIP32/BIP44, coin type `111111`:
  стандартный одиночный адрес — `m/44'/111111'/0'/0/0`; multisig — purpose
  `45'`. Легаси-путь `972'` (старые kaspanet/KDX-кошельки) даёт другие
  адреса и считается устаревшим.
- **Мнемонический стандарт:** BIP39 (12/24 слова; SDK wallet-core).
- **Алгоритм подписи:** Schnorr над secp256k1 (по умолчанию); ECDSA для
  legacy-адресов `0x01`. Sighash — keyed blake2b-256 с ключом
  `TransactionSigningHash`; поддерживаются типы подписи ALL/ANYONECANPAY и
  комбинированные (в v2.1.0 исправлено сопоставление `AllAnyOneCanPay`).
- **Совместимость восстановления из фразы:** BIP39-фраза + путь
  `m/44'/111111'` восстанавливает те же адреса во всех актуальных кошельках
  экосистемы (Kaspa NG, web/CLI-кошелёли, WASM/Python SDK). Известная
  несовместимость — только легаси-кошельки пути `972'`.

## Транзакции

- **Структура транзакции:** UTXO-транзакция BlockDAG: inputs (outpoint,
  signatureScript, sigOpCount), outputs (value в sompi, scriptPublicKey
  {version, script}, опциональный payload), общий mass; версия 1
  (до Toccata) / 2 (Toccata: поля ковенантов). P2P-лимит на wire-блок — 2 МБ
  (v2.1.0). Единица: 1 KAS = 10^8 **sompi**.
- **Расчёт комиссии:** модель **mass** (не vByte и не gas):
  - mass транзакции = compute grams + storage grams + transient grams;
    лимит mass блока — 500 000 grams; после Toccata transient-компонент
    нормализован («≈ 2 × размер транзакции в байтах»).
  - комиссия = feeRate × mass; минимальный стандартный relay-fee после
    Toccata: **100 sompi × max(compute grams, 2 × размер tx в байтах)** —
    это policy/mempool-правило узла, а НЕ консенсусное (нулевые комиссии
    остаются консенсусно-валидными). Подтверждено release-notes rusty-kaspa
    (v1.3.0-toc.5) и Kaspalytics.
  - оценка комиссии — RPC `getFeeEstimate` (бакеты по приоритету).
- **Блокировки/имматурность:** coinbase-транзакции тратятся после
  **1000 блоков** (immaturity). Выплаты пула приходят обычными транзакциями —
  ограничения на них не распространяются; критично только для соло-майнинга
  напрямую в кошелёк.
- **Модель баланса:** UTXO поверх BlockDAG; «подтверждения» считаются по
  blue score виртуального выбранного родительского множества (VSPC).
- **Особые поля:** у выходов есть поле payload (данные, аналог OP_RETURN);
  максимальный размер payload — НЕ ПОДТВЕРЖДЕНО. Payment ID / memo в
  стандартном потоке кошелька отсутствуют. URI-схема `kaspa:` для QR-платежей
  с параметром amount — НЕ ПОДТВЕРЖДЕНО (адрес в QR подтверждён).

## Доступ к сети

- **Методы RPC:** два транспорта с общим набором операций:
  - **wRPC** (WebSocket; кодировки Borsh — для клиентов из той же кодовой
    базы, и JSON — даталогически-агностичная, подключается любой WS-библиотекой)
    — используется всеми SDK; включается флагами `--rpclisten-borsh` /
    `--rpclisten-json` (по умолчанию выключен; `=default` берёт порты сети);
  - **gRPC** (protobuf; единый bidirectional-stream метод-фасад: все
    операции мультиплексируются в одном стриме — нужны сгенерированные
    стаб-клиенты; по умолчанию слушает `127.0.0.1:16110` в mainnet).
  Необходимый кошельку набор: `getServerInfo`, `getInfo`, `getBlockDagInfo`,
  `getFeeEstimate`, `getBalanceByAddress(es)`, `getUtxosByAddresses`,
  `getMempoolEntriesByAddress(es)`, `submitTransaction`,
  `getVirtualChainFromBlock` / **`GetVirtualChainFromBlockV2`** (opcode 151,
  verbosity-уровни + `minConfirmationCount` — по официальной формулировке,
  «интеграция Kaspa теперь ближе к классической цепочке»), уведомления: `utxos-changed`,
  `virtual-chain-changed`, `block-added`, `sink-blue-score-changed`,
  `virtual-daa-score-changed`.
  **Важно:** методы `getUtxosByAddresses`/`getBalanceByAddress(es)` требуют
  узла, запущенного с `--utxoindex` (README: «needed when using wallets»).
- **P2P-протокол:** порт `16111` (mainnet) / `16211` (TN10); wire-протокол
  Kaspa P2P, с v2.1.0 — протокол v11 (чанковый IBD по 20 МиБ), обратная
  совместимость с v10; для кошелька не используется (surface узлов).
  Bootstrap через DNS-seeder (kaspanet/dnsseeder).
- **Лёгкий клиент:** SPV-клиента нет. «Лёгкий» режим = локальное подписание
  (wallet-core) + RPC к узлу (своему или публичному); браузерный WASM SDK
  работает полностью на клиенте, включая UTXO-мониторинг (UtxoProcessor /
  UtxoContext).
- **Узел:** rusty-kaspa **v2.1.0** (последний релиз, 22.09.2026); сборка из
  исходников (Rust 1.88+/edition 2024, protobuf, LLVM/clang, RocksDB) или
  Docker `kaspanet/rusty-kaspad:latest` (открывает gRPC 16110); схема БД v6.
  Требования к диску для mainnet-узла с `--utxoindex` — НЕ ПОДТВЕРЖДЕНО
  (замерить при развёртывании; архивные узлы существенно больше pruning-
  конфигураций). В комплекте релизов: `kaspad`, интерактивный терминальный
  кошелёк `kaspa-wallet` (совместим с WASM Wallet API и Kaspa NG), stratum
  bridge.
- **Публичные RPC:** **PNN (Public Node Network)** — децентрализованный пул
  комьюнити-узлов за балансировщиком **Kaspa Resolver** (REST ALB, встроен в
  Rust/WASM/Python SDK как объект `Resolver`; при недоступности узла клиент
  автоматически переключается). Статус узлов: https://pnn.kaspa.stream.
  Официальная позиция: PNN «для разработки и тестирования; не рекомендуется
  для production/бирж» (kaspa.aspectron.org/rpc/pnn.html), комьюнити-API
  «best-effort, без SLA» (kaspa.org/build). Дополнительный публичный REST
  API: https://api.kaspa.org/docs (дампы БД: db-dl.kaspa.org).
  **Приватность:** публичные узлы видят адреса и IP пользователя; для
  production официальная рекомендация — собственный узел.
- **Explorer:** https://kaspa.stream (официальный, ссылки на транзакции/адреса);
  визуализатор DAG: kgi.kaspad.net; тестнет-кран: faucet-testnet.kaspanet.io.

## SDK и библиотеки

- **Официальные SDK** (все — из одной Rust-кодовой базы rusty-kaspa):
  - **Rust**: крейты `kaspa-wallet-core`, `kaspa-wrpc-client`,
    `kaspa-rpc-core`, `kaspa-addresses`, `kaspa-consensus-core`,
    `kaspa-txscript`, `kaspa-bip32` и др. — код самого узла; активность
    эталонная (v2.1.0, сентябрь 2026).
  - **WASM SDK** (JS/TS, браузер и Node.js): полная поддержка RPC + Wallet
    SDK (ключи, деривация, генерация транзакций); дистрибутив — zip
    `kaspa-wasm32-sdk-*.zip` из GitHub Releases; **npm-пакеты `kaspa` и
    `kaspa-wasm32-sdk` устарели — не использовать**.
  - **Python SDK**: `pip install kaspa` (PyPI актуален: 2.0.1 stable /
    2.0.2rc1 на август 2026; Python 3.10–3.14; статус Production/Stable);
    RPC-клиент + Wallet SDK + managed wallet (`Wallet`).
- **Rust-библиотеки:** см. выше — это референсная реализация сети
  (идеальный вариант для Rust-ядра VEYRO). **Публикации на crates.io устарели:
  заперты на 0.15.0 (сентябрь 2024, до Crescendo)** — подключать только
  git-зависимостью с пином на тег релиза:
  `kaspa-wrpc-client = { git = "https://github.com/kaspanet/rusty-kaspa" }`.
- **Flutter/Dart-интеграции:** официального Dart SDK нет. Реалистичные пути:
  (а) FFI-обёртка над `kaspa-wallet-core` (рекомендуется — тот же код, что в
  официальных кошельках); (б) собственный Dart-клиент поверх wRPC-JSON
  (протокол даталогически-агностичный, достаточно WebSocket-библиотеки —
  README rusty-kaspa); (в) связка с WASM SDK.
- **Лицензии зависимостей (совместимость с MIT OR Apache-2.0):**
  rusty-kaspa — **ISC**; kaspa-python-sdk — **ISC**; secp256k1 — MIT;
  типовые зависимости (tokio, rocksdb, borsh и пр.) — MIT/Apache-2.0.
  ISC функционально эквивалентен MIT → **совместимо** с политикой лицензий
  VEYRO. Риск: устаревшие артефакты в crates.io/npm → жёсткий пин git-тегов.

## Совместимость кошелька

Реализуемость полного цикла **без серверов VEYRO** (пометки — технический
маршрут; ничего не считается поддержанным до тестов):

- [ ] Создание кошелька — локально: BIP39 + kaspa-wallet-core (Rust-FFI)
- [ ] Импорт кошелька — XPrv / seed, локально
- [ ] Восстановление — BIP39-фраза → `m/44'/111111'/0'/0/0`, локально
- [ ] Получение (адрес/QR/URI) — Bech32 `kaspa:q…` + QR; URI — НЕ ПОДТВЕРЖДЕНО
- [ ] Баланс — `getBalanceByAddress(es)` / UtxoProcessor; нужен узел с
      `--utxoindex` (свой или PNN)
- [ ] История транзакций — отслеживание UTXO + `getVirtualChainFromBlockV2`
      (minConfirmationCount) на своём узле; либо explorer kaspa.stream /
      api.kaspa.org для ссылок
- [ ] Отправка — генерация tx wallet-core (mass/fee) + локальная подпись
      Schnorr + `submitTransaction` по wRPC
- [ ] Мониторинг подтверждений — события `virtual-chain-changed` /
      `sink-blue-score-changed`, blue score вместо «N подтверждений»

## Безопасность и ограничения

- **Известные ограничения:** wRPC выключен по умолчанию (нужен флаг);
  кошелёные RPC требуют `--utxoindex`; публичная инфраструктура (PNN) —
  best-effort без SLA; crates.io/npm-публикации устарели.
- **Риски безопасности:** (1) зависимость от чужих узлов при отказе от
  собственного — приватность (публичный узел связывает адреса с IP) и
  доступность; (2) сложная модель mass/fee — заниженная комиссия = застрявшие
  транзакции (использовать `getFeeEstimate` и post-Toccata форму floor);
  (3) DAG-семантика подтверждений (blue score) — нельзя механически
  переносить «N подтверждений» из классических цепочек; (4) Toccata-эра:
  транзакции v2/ковенанты — держать зависимости на 2.x-ветке; (5) supply-chain
  риск устаревших пакетов — только git-пины.
- **Блокеры:** **нет**. Полный цикл реализуем полностью на стороне клиента
  (Rust-ядро VEYRO может использовать те же крейты, что и официальный узел);
  требуется только доступ к узлу — PNN для старта, собственный rusty-kaspa-узел
  с `--utxoindex` для production.

## Вывод и предлагаемый статус в матрице

- **Идентичность:** подтверждена (KAS = Kaspa, coin type 111111).
- **Полный цикл без серверов VEYRO:** да — локальное подписание + RPC
  (PNN/Resolver по умолчанию для «облачного» старта, собственный узел
  рекомендуется для надёжности и приватности).
- **Наибольший риск:** доступность и приватность внешних узлов + устаревшие
  публикации пакетов (нужен строгий пин git-зависимостей rusty-kaspa v2.1.0).
- **Предлагаемый статус:** до тестов — Research required; после реализации и
  полного тестового цикла (`docs/COIN_COMPATIBILITY.md`) — кандидат на
  **Full support**. Промежуточно: Receive supported → Send supported.
- Для майнинг-выплат: пулы (PPLNS, min payout 1–100 KAS) платят обычными
  транзакциями на P2PK `kaspa:q…` — immaturity 1000 блоков на приём не влияет.

## Источники

1. https://kaspa.org/build/ — официальный обзор стека, PNN/Resolver, node v2.1.0, Toccata live 30.06.2026, api.kaspa.org, kaspa.stream, db-dl.kaspa.org
2. https://github.com/kaspanet/rusty-kaspa — README (Crescendo 05.05.2025 1→10 BPS; `--utxoindex` для кошельков; wRPC выключен по умолчанию; Docker/gRPC 16110), releases v2.0.0 / v2.0.1 / v2.1.0 / v1.3.0-toc.5 (Toccata DAA 474 165 565; мин. relay fee `100 sompi × max(compute grams, 2×bytes)`; policy, не консенсус) / tn10-toc2, tn10-toc3 (TN10 активен), `consensus/src/genesis/genesis.rs`, `docs/crescendo-guide.md`, `docs/toccata-guide.md`
3. https://kaspa.aspectron.org/rpc/pnn.html, /rpc/kaspa-resolver.html — PNN/Resolver: назначение, статус-страница pnn.kaspa.stream, официальное «не для production»
4. https://docs.kaspa.org, /toccata, /programmability — гайды Toccata/программируемости
5. Kaspalytics Developer Docs (kaspalytics.com/developer-docs): network-parameters (порты 16111/16110/17110/18110 и TN10/TN11; префиксы адресов; version bytes 0x00/0x01/0x08), rpc-calls (getBalanceByAddress, getUtxosByAddresses, getFeeEstimate, getVirtualChainFromBlockV2 и др.), sdks (crates.io stale 0.15.0 → git-зависимости; npm stale; PyPI `kaspa` актуален)
6. https://github.com/kaspanet/kaspa-python-sdk — ISC, PyPI 2.0.1/2.0.2rc1, Python 3.10–3.14, события RPC (utxos-changed, virtual-chain-changed и др.)
7. https://kaspanet.github.io/kaspa-python-sdk — API/документация (Resolver, Wallet, storage_mass post-Toccata)
8. https://kaspa.stream — официальный explorer; https://api.kaspa.org/docs — публичный REST API; https://faucet-testnet.kaspanet.io — кран TN10
9. https://github.com/kaspanet/kips — KIP-16/17/20/21 (Toccata); https://gi