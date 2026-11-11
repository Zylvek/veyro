# Технический паспорт монеты: PRL

> Составлено 11.11.2026. Только проверенные факты; неподтверждённое помечено
> `НЕ ПОДТВЕРЖДЕНО`.

- **Тикер(ы):** **PRL** — основной тикер сети (используется пулом Kryptex, Ourbit, NEAR-обёрткой). На биржах SafeTrade/BigONE/Gateway базовый символ — **PEARL** (пары PEARL/USDT, PEARL/USDC). CoinGecko: symbol `pearl`, id `pearl-2`. CoinPaprika: `prl-pearl-1` (суффикс `-1` — короткий id занят историческим проектом Oyster Pearl (PRL, 2018, мёртв), не путать). NEAR-обёртка: `PRL.omft.near` (Rhea Finance / Near Intents).
- **Официальное название проекта:** Pearl (разработчик — Pearl Research Labs)
- **Официальный сайт:** https://pearlresearch.ai (инфраструктура сети — домен `*.pearlnetwork.net`: DNS-сиды, X: @prlnet)
- **Официальный репозиторий:** https://github.com/pearl-research-labs/pearl (Go, монорепозиторий); PIP-репозиторий: https://github.com/pearl-research-labs/pips
- **Официальная документация:** PIP-сайт https://pearl-research-labs.github.io/pips (PIP-0001 — процесс; PIP-0002 — Grouped-GEMM PoUW для MoE, статус Final; PIP-0003 — FP PoUW Certificates, Draft); whitepaper: https://pearlresearch.ai/Pearl_Whitepaper.pdf; научная база PoUW: arXiv 2504.09971
- **Статус исследования:** завершено

## Идентификация сети

- **Mainnet:**
  - Magic bytes (P2P wire): `0x50524C4D` — «PRLM» в ASCII (`node/wire/protocol.go`).
  - Genesis: timestamp `2026-04-27 09:00:00 UTC` (Unix 1777280400); merkle root `302f59c6f1239648bd38eddf16b22acc8c8df3c96de2e4f552bd2f38371675c1`; genesis-хэш задан в коде (`node/chaincfg/genesis.go`) массивом байтов `d7ad8dc5415fb548ff53efe75f10e0e27403d1a33f07dd0c8f61ffb793308da1` (в btcd-порядке отображения хэш-строки байты реверсируются: `a18d3093b7ff618f0cdd073fa3d10374e2e0105fe7ef53ff48b55f41c58dadd7`).
  - PoW: Proof-of-Useful-Work — майнинг = полезные вычисления (grouped GEMM / перемножение матриц для AI-нагрузок), корректность подтверждается zk-доказательствами Plonky2 (PIP-0002 Final; PIP-0003 Draft). PoW-лимит `2^208−1`, PowLimitBits `0x1b00ffff`.
  - Целевое время блока: **3 мин 14 с** (WTEMA-ретаргет, полупериод 168 ч). WhatToMine показывает фактические ~2 мин 50 с.
  - Coinbase maturity: **100 блоков**. Награда ~2177 PRL/блок, хэшрейт ~94,75 Ph/s (WhatToMine, 02.11.2026, волатильно). Высота ~137 000 (02.11.2026); в коде зашиты чекпойнты до 120 000.
  - Хард/софтфорки mainnet (по `chaincfg/params.go`): MoEFork 71 935 (сертификаты V2), DenseOnly 91 630, RankPenalty 96 251, SaltedSeed 99 000 (сертификаты V3) — три форка за первые ~100k блоков.
  - Порты: RPC **44107**, P2P **44108**, wallet **44207**. DNS-сиды: `reef/tide/stream.seeder.pearlnetwork.net`.
- **Testnet:** testnet (P2P 44110, RPC 44109, wallet 44209, hrp `tprl`, magic «PRL1», genesis 2026-06-30) и testnet2 (P2P 44112, hrp `tprl`, magic «PRL2»). Локальные: regtest (18444, «PRLR»), simnet (18555, «PRLS»), signet (38333) — публичный signet не оперируется («Pearl does not currently operate a signet»).
- **Проверка идентичности:** тикер PRL в майнинговом контексте 2025–2026 = **Pearl (Pearl Research Labs)**, единственная живая PoW-сеть под этим тикером. Доказательства: пул Kryptex `pool.kryptex.com/prl` (официальные ссылки на pearlresearch.ai, выплаты на нативные адреса `prl1…`, endpoint `prl.kryptex.network:7048`); WhatToMine `/coins/469-prl-pearl`; CoinPaprika `prl-pearl-1` (тип coin, started 2026-05-27); CoinGecko `pearl-2` (категории AI / L1 / PoW); SafeTrade (PEARL/USDT, PEARL/USDC, PRL/BTC, PRL/USDT), BigONE, Gate, Ourbit (PRL/USDT); NEAR-обёртка `PRL.omft.near`; сам код сети (hrp `prl`, magic «PRLM», coin type 808276 из ASCII «PRL»). Исторический Oyster Pearl (PRL, 2018) мёртв и в майнинговых списках 2025–2026 отсутствует.

## Криптография и ключи

- **Формат адреса:** только Taproot, кодировка Bech32m (BIP350), HRP `prl` → адреса вида `prl1p…` (mainnet); `tprl` (testnet/testnet2), `rprl` (regtest/simnet). Префикс `prl1` зарегистрирован в chaincfg.
- **Формат публичного ключа:** secp256k1; кошелёк «Taproot-only» (в chaincfg: «Using BIP-84 (SegWit) versions for Taproot-only wallet»), т.е. x-only публичные ключи witness v1.
- **Формат приватного ключа:** WIF, версия-байт `0x80` (mainnet) / `0xef` (testnet, regtest) / `0x64` (simnet).
- **Схема деривации ключей:** BIP32/BIP44-совместимая (форк btcd/btcwallet). Coin type mainnet: **808276** (`HDCoinTypePearl`, производный от ASCII «PRL»: 0xC5554) — **не зарегистрирован в SLIP-0044** (проверено 11.11.2026, в реестре отсутствует). Тестнеты: coin type 1. Точный скрипт-путь (m/84'/808276'/… или m/86'/808276'/…): **НЕ ПОДТВЕРЖДЕНО** (в коде BIP84-версии zprv/zpub при Taproot-адресах). Расширенные ключи: `zprv`/`zpub` (mainnet), `vprv`/`vpub` (testnet), `sprv`/`spub` (simnet).
- **Мнемонический стандарт:** кошелёк Oyster — форк btcwallet (Lightning Labs); десктоп-кошелёк в `apps/apps/pearl-desktop-wallet`. Наличие/формат фразы восстановления (BIP39 или иной): **НЕ ПОДТВЕРЖДЕНО** (в исследованных файлах генератор фразы не проверен).
- **Алгоритм подписи:** Schnorr/BIP340 (Taproot). В монорепозитории также присутствует постквантовая реализация **XMSS** (hash-based, `xmss/external/`, лицензия CC0-1.0) — область применения (кошелёк/сертификаты): **НЕ ПОДТВЕРЖДЕНО**. PoUW-сертификаты блоков — zk-доказательства **Plonky2** (`plonky2/`, MIT OR Apache-2.0).
- **Совместимость восстановления из фразы:** детерминизм гарантируется BIP32/BIP44-деривацией от seed; конкретные несовместимости между кошельками Pearl **НЕ ИЗВЕСТНЫ / НЕ ПРОВЕРЕНЫ** (сторонних кошельков нет — сеть слишком молода).

## Транзакции

- **Структура транзакции:** btcd-совместимая wire-модель (UTXO, segwit, wtxid-relay); адреса/выходы только Taproot.
- **Расчёт комиссии:** btcd-модель (sat/vByte, relay-политика mempool); конкретные параметры fee: **НЕ ПОДТВЕРЖДЕНО**.
- **Блокировки/имматурность:** coinbase maturity **100 блоков**.
- **Модель баланса:** UTXO.
- **Особые поля:** заголовок блока содержит PoUW-сертификат (версии V1 → V2 → V3 по высотам форков; V2/V3 — MoE/dense proof, noise rank, salted noise-seed); в genesis — vanity-поле ProofData `0xdeadbeef`. Модель эмиссии (график, хвостовая эмиссия): **НЕ ПОДТВЕРЖДЕНО**.

## Доступ к сети

- **Методы RPC:** нода `pearld` — btcd-совместимый JSON-RPC (порт 44107); кошелёк Oyster — отдельный JSON-RPC (порт 44207); утилита `prlctl`. Полный список методов не проверялся — ориентироваться на btcd-стандарт (getbestblockhash, getblock, getblockchaininfo, sendrawtransaction и т.п.): **НЕ ПОДТВЕРЖДЕНО** для специфичных методов.
- **P2P-протокол:** порт 44108, btcd wire-протокол (addrv2, BIP339 wtxid relay, BIP157/158 compact filters — в `node/wire` есть msgcfheaders/msgcfcheckpt/msggetcfilters).
- **Лёгкий клиент:** есть — SPV-клиент на базе форка **neutrino** (`spv/`, MIT, Lightning Labs), компактные фильтры блоков.
- **Узел:** `pearld` (Go). Установка: `install.ps1` (Windows) и скрипты репозитория. Требования к диску/памяти: **НЕ ПОДТВЕРЖДЕНЫ**.
- **Публичные RPC:** **НЕ ПОДТВЕРЖДЕНО** (публичных шлюзов не найдено; для интеграции поднимать свой узел; DNS-сиды доступны).
- **Explorer:** https://explorer.pearlresearch.ai (форк blockbook). Прямой blockbook-API `/api/v2/…` при проверке из этого окружения возвращал HTML-оболочку (404) — для ссылок на транзакции использовать web-интерфейс; API-доступ **НЕ ПОДТВЕРЖДЁН**.

## SDK и библиотеки

- **Официальные SDK:** только **Go** (монорепозиторий): `node/` (нода, ISC), `wallet/` (Oyster, ISC), `spv/` (SPV, MIT), `miner/pearl-gemm` (майнер на базе vLLM/CUTLASS), `plonky2/`, `xmss/`, `coredns-dnsseed/`, `apps/apps/pearl-desktop-wallet` (десктоп-кошелёк, React/TypeScript).
- **Rust-библиотеки:** официальных нет. Сторонних активных крейтов не найдено.
- **Flutter/Dart-интеграции:** официальных нет. Для VEYRO — только JSON-RPC/wire-протокол (самостоятельная реализация) или gRPC-подобных обвязок нет.
- **Лицензии зависимостей:** ISC (node/wallet), MIT (spv), MIT OR Apache-2.0 (plonky2), CC0-1.0 (xmss external), BSD-3-Clause (NVIDIA CUTLASS в pearl-gemm) — все совместимы с MIT OR Apache-2.0. Форки btcd/btcwallet/neutrino наследуют их ISC/MIT-лицензии.

### Майнинг-инфраструктура

- Алгоритм в списках пулов: **PearlHash** (miningpoolstats), `pearlhash`/`pearl` в майнерах. Суть — PoUW (GEMM + zk-сертификаты).
- Пулы: **Kryptex** — `prl.kryptex.network:7048` (PPS+ 3% / SOLO 1%, min payout 1 PRL, ~109k воркеров, выплаты на нативные `prl1…` или авто-конверт в USDT/BTC); **maxpool.pro/pool/prl** (США, PPLNS 0,5% — по данным miningpoolstats.stream/pearl). Другие пулы: **НЕ ПОДТВЕРЖДЕНЫ**.
- Майнеры: официальный `pearl-gemm` (GPU, vLLM); сторонние: **KRig** (Kryptex), **SRBMiner-MULTI** (`--algorithm pearlhash`), **PeakMiner** (`--coin pearl`), **lpminer** (`--algo pearl`). XMrig PRL не поддерживает.

## Совместимость кошелька

- [x] Создание кошелька — через JSON-RPC Oyster / десктоп-кошелёк
- [x] Импорт кошелька — WIF/расширенные ключи (zprv); импорт мнемоники — **НЕ ПРОВЕРЕНО**
- [ ] Восстановление — **НЕ ПОДТВЕРЖДЕНО**: формат фразы восстановления не установлен, воспроизводимость между клиентами не проверялась
- [x] Получение (адрес/QR/URI) — адреса `prl1p…` (Bech32m, Taproot-only); URI-схема: **НЕ ПОДТВЕРЖДЕНО**
- [x] Баланс — через wallet JSON-RPC (btcd/btcwallet-совместимые методы)
- [x] История транзакций — через explorer.pearlresearch.ai / RPC
- [x] Отправка (построение, подпись, бродкаст) — Taproot (Schnorr) через wallet RPC
- [x] Мониторинг подтверждений — RPC ноды + чекпойнты/высота

Все пункты реализуемы только через собственный Go-узел/JSON-RPC — готовых Rust/Dart/Flutter SDK нет.

## Безопасность и ограничения

- **Известные ограничения:** очень молодая сеть (mainnet ~апрель–май 2026, CoinPaprika started 2026-05-27); три форка за ~100k блоков (71935/91630/96251/99000) — консенсус ещё «плывёт»; нестандартный coin type 808276 (не в SLIP-44 — риск для межкошельковых стандартов); единственный крупный пул — Kryptex (централизация хэшрейта и выплат); PoUW привязывает экономику сети к рынку GPU/AI-вычислений.
- **Риски безопасности:** Taproot-only + экспериментальные zk-сертификаты (PIP-0003 ещё Draft); гигантские PoUW-параметры (PowLimit 2^208) — новая, малоизученная криптография; отсутствие сторонних аудитов кода: **НЕ ПОДТВЕРЖДЕНО** (аудитов не найдено).
- **Блокеры:** для полной поддержки кошелька VEYRO — отсутствие официальных SDK вне Go (придётся реализовывать wire/RPC/деривацию самостоятельно) и неподтверждённый формат мнемоники. Критического (запрещающего) блокера нет.

## Вывод для матрицы поддержки

Актив идентифицирован однозначно: **PRL = Pearl (Pearl Research Labs)**, PoUW L1 (майнинг = AI-вычисления). Предлагаемый статус матрицы: **«Технически реализуемо / Research required → done»** — интеграция возможна по btcd-совместимому стеку (JSON-RPC 44107/44207, SPV-neutrino), но требует собственной реализации клиента (нет Rust/Dart SDK) и проверки формата мнемоники до включения функции восстановления. Главный риск: возраст сети и PoUW-специфика (консенсус стабилизируется, экономика зависит от GPU/AI-рынка).

## Источники

1. https://pearlresearch.ai — официальный сайт
2. https://github.com/pearl-research-labs/pearl — монорепозиторий (chaincfg/params.go, chaincfg/genesis.go, wire/protocol.go, LICENSE)
3. https://pearl-research-labs.github.io/pips/ — PIP-0001/0002/0003
4. https://github.com/pearl-research-labs/pips — PIP-репозиторий (CC0)
5. https://explorer.pearlresearch.ai — эксплорер (форк blockbook)
6. https://pool.kryptex.com/prl и /prl/about-coin — пул Kryptex (endpoint, комиссии, мин. выплата)
7. https://pool.kryptex.com/articles/pearl-miners-en — настройка SRBMiner/PeakMiner/lpminer
8. https://miningpoolstats.stream/pearl — PearlHash, maxpool.pro, цена
9. https://whattomine.com/coin/469-prl-pearl — параметры сети (BT, BR, hashrate)
10. https://coinpaprika.com/coin/prl-pearl-1/ и https://www.coingecko.com/en/coins/pearl-2 — листинги
11. https://arxiv.org/abs/2504.09971 — научная база PoUW
12. https://pearlresearch.ai/Pearl_Whitepaper.pdf — whitepaper
