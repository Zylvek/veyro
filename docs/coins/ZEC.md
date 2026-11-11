# Технический паспорт монеты: ZEC

- **Тикер(ы):** ZEC
- **Официальное название проекта:** Zcash
- **Официальный сайт:** https://z.cash (ECC), https://zfnd.org (Zcash
  Foundation)
- **Официальный репозиторий:** https://github.com/zcash (zcashd — EoL,
  архив; zallet; lightwalletd), https://github.com/ZcashFoundation/zebra
  (Zebra), https://github.com/zcash/librustzcash (Rust-SDK)
- **Официальная документация:** https://zcash.github.io (узлы),
  https://zebra.zfnd.org (книга Zebra), https://zcash.github.io/zallet
  (Zallet), https://zips.z.cash (ZIP)
- **Статус исследования:** завершено
- **Дата исследования / live-проверок:** 2026-11-11

## Идентификация сети

- **Mainnet:** Zcash L1; PoW Equihash (200,9); блок ~75 с; cap
  21 000 000 ZEC. Последние активации в mainnet:
  - **NU6.3 «Ironwood»** (~28.07.2026) — новый shielded-пул Ironwood
    (Ironwood-деревья в treestate Zebra; отражены в lightwallet-protocol
    и `z_viewtransaction`);
  - **NU7** — высота активации **3 543 405**; consensus branch ID
    **0x77190AD9** (live-подтверждение в GetLightdInfo трёх
    свет-серверов, 11.11.2026). NU7 внёс ZIP 218 (интервалы халвингов ×3;
    25-секундные интервалы на testnet) и ZIP 237 (reissuance через NSM —
    новый value pool; БД Zebra v29).
  - Live-tip на 11.11.2026 — **3 562 427**, идентичен (высота+hash) на
    zec.rocks / zec.0xrpc.io / zec-node.cakewallet.com.
- **КРИТИЧНО — zcashd мёртв:** `zcashd` автоматически остановился
  (halt) на блоке 3417100 **18.07.2026** (End-of-Life: не поддерживает
  NU6.3+); публично раскрытая 01.06.2026 причина — уязвимость Orchard в
  zcashd; репозиторий заархивирован 19.07.2026; последний релиз 6.20.0.
  Все руководства и библиотеки на стеке zcashd непригодны.
- **Версии софта (11.11.2026):** Zebra **7.0.0** (22.10.2026; NU7
  mainnet, БД v29; 7.1.0-alpha.0 — pre-release для майнеров); Zallet
  **0.1.0-beta.4** (02.11.2026); lightwalletd v0.5.4+ (на живых серверах
  — 0.6.1); Zaino (`zainod`) 0.8.0 (форум) — 0.10.1 на живом сервере.
- **Testnet:** есть; unified-адреса `utest1…`; P2P-порт Zebra 18233.
  Live свет-сервер testnet.zec.rocks (chain «test», бэкенд Zakura 1.7.0;
  проверено 11.11.2026).
- **Проверка идентичности:** тикер ZEC = Zcash (z.cash, zfnd.org);
  сетей-конфликтантов нет.

## Криптография и ключи

- **Формат адреса:** Unified Addresses (ZIP-316, bech32m): `u1…`
  (mainnet) / `utest1…` (testnet). Унаследованные: Sapling `zs1…`
  (bech32); transparent `t1…` (Base58 P2PKH) и `t3…` (P2SH), testnet
  `tm…`/`t2…`; Sprout `zc…` (legacy, не использовать).
- **Формат публичного ключа:** transparent — secp256k1 (Bitcoin-модель);
  shielded — ключи кривых Sapling (Jubjub) / Orchard (Pallas).
- **Схема деривации:** shielded — ZIP-32: `m/32'/133'/account'` (из
  одного seed — Sapling- и Orchard-ключи); transparent — BIP44
  `m/44'/133'/0'/…`. Seed кошельков современной модели (Zashi) — BIP39;
  единый стандарт сети НЕ ПОДТВЕРЖДЁН — сверять при интеграции.
- **Viewing-модель:** UFVK (unified full viewing key, bech32m
  `uview1…`) — видит входящие и исходящие; UIVK — только входящие.
  В Zallet `z_importviewingkey` — **только Sapling extended FVK**
  (migration guide); `z_exportviewingkey` — uview/uivk. Для собственного
  стека librustzcash UFVK/IVK — родные сущности (скан через compact
  blocks).
- **Алгоритм подписи:** transparent — ECDSA secp256k1; Sapling — Groth16
  (исторический trusted setup, церемония завершена) + RedJubjub;
  Orchard — Halo2 (без trusted setup) + RedPallas. Shielded-траты —
  zk-доказательства.
- **Совместимость восстановления из фразы:** seed → ZIP-32 → все
  аккаунты. Восстановление = скан shielded-цепи; в librustzcash-стеке
  поддерживается birthday-высота старта скана (сверять API при
  интеграции). Лёгкой модели «без цепи» не существует — скан идёт по
  compact-блокам свет-сервера или по полной ноде.

## Транзакции

- **Структура транзакции:** transparent (Bitcoin-подобная) + shielded-
  пулы: Sapling (spends/outputs), Orchard (actions) и **Ironwood** (новый
  shielded-пул с NU6.3); nullifiers против двойной траты; зашифрованные
  memo (до 512 Б).
- **Расчёт комиссии:** ZIP-317 (conventional fee — формула от числа
  actions; в Zebra — `getstandardfee`; в Zallet/PCZT-пайплайне — ZIP 317);
  transparent — Bitcoin-модель (vByte).
- **Блокировки/имматурность:** coinbase-зрелость 100 блоков.
- **Модель баланса:** UTXO (transparent) + notes (shielded).
- **Особые поля:** unified receivers (ZIP-316), memo; **PCZT** — формат
  пошаговой сборки/подписи транзакции (shielded-аналог PSBT; крейт
  `pczt`); ZIP-321 (payment request URI) — сверять параметры при
  интеграции; ZIP 237 (NSM) — механика reissuance с NU7.

## Доступ к сети

- **Узел — Zebra** (`zebrad`, Rust, Zcash Foundation; MIT OR
  Apache-2.0): консенсус-нода БЕЗ кошелька; RPC по умолчанию выключен;
  порты 8233 (mainnet) / 18233 (testnet); поддерживаемые платформы:
  Tier 1 — Linux x86_64/aarch64 (бинарники + Docker), Tier 2 — Linux CI,
  **Tier 3 — macOS x86_64/aarch64 и x86_64-pc-windows-msvc (код есть,
  тестированием не покрывается)**.
  - **RPC Zebra (владение по migration guide):** полный —
    `getaddressbalance`, `getaddresstxids`, `getaddressutxos`,
    `getbestblockheightandhash` (Zebra-only), `getstandardfee` (ZIP 317,
    Zebra-only), `rpc.discover` (Zebra-only); частичный — `getblock`,
    `getblockchaininfo`, `getblockcount`, `getinfo`, `getrawmempool`,
    `getrawtransaction`, `sendrawtransaction` (`allowhighfees`
    игнорируется), `validateaddress`, `z_gettreestate`,
    `z_listunifiedreceivers`, `z_converttex`; плюс индексер-gRPC
    (`indexer_listen_addr`, :8230).
  - **Экспериментальный native CompactTxStreamer в zebrad** (с 6.4.0;
    PR #10953, 18.08.2026): `rpc.lightwalletd_listen_addr`, 18 методов
    ZIP-307; plaintext HTTP/2 — привязывать к loopback и терминировать
    TLS прокси (nginx/Caddy); по книге Zebra «не запускать на машине
    пользователя»; совместимость с мобильными SDK не проверена
    (issue #11158).
- **Кошельковые надстройки:**
  - **Zallet 0.1.0-beta.4** (02.11.2026; требует zebrad 7.0.0+, NU7):
    full-node кошелёк поверх ко-локального zebrad (читает его state-DB;
    Zaino-бэкенд удалён в beta.4). Релиз-артефакты — только Linux
    amd64/arm64 (musl); **на Windows zallet-core и launcher собираются и
    unit-тесты проходят в CI (MSVC), но релиз-артефактов нет и
    chain-backend отсутствует (zebra backend Linux-only)**; macOS —
    Tier 2; Android/iOS не поддерживаются; hardening отстаёт от zcashd.
    RPC: `z_sendmany` (PCZT-пайплайн, ZIP 317, transparent spends, поле
    broadcast), `z_getbalanceforaccount`, `z_listunspent` (включая
    transparent pool, `is_watch_only`), `z_viewtransaction` (с
    transparent tIn/tOut), `z_importviewingkey` (только Sapling
    extended FVK), `z_exportviewingkey` (uview/uivk),
    `z_getnewaccount`, `z_getaddressforaccount`, `z_shieldcoinbase`,
    PCZT-методы (issue #99 — в работе; заменяют
    createrawtransaction/fundrawtransaction/signrawtransaction),
    `migrate-zcashd-wallet`.
  - **zecd 0.6.0** (zecd.org): stateless wallet-сервер (bitcoind-стиля
    RPC) поверх локального Zebra; watch-only через UFVK; умеет
    lightwalletd gRPC URL; сайт жив (200, 11.11.2026).
- **Экосистема ZIP-307 gRPC-серверов** (обзор на форуме, обновлён
  09.11.2026): lightwalletd (Go, 1.26.10+/1.27.3 toolchain; бэкенд через
  JSON-RPC :8232 zebrad), Zaino/`zainod` (ZcashFoundation), native
  zebrad (эксперим.), ztreamer (Zakura, P2Pv2), lightwalletd-rs, Zinder;
  Zakura 1.8.3 — форк Zebra (Shielded Labs); Z3 = Zebra+Zaino+Zallet
  (репозиторий ZcashFoundation/z3). На этот протокол говорят:
  zcash_client_backend (`CompactTxStreamerClient`, tonic), zingolib,
  Zashi/ZODL SDK, Ywallet, @ledgerhq/zcash-utils. Спецификация — ZIP-307
  (репозиторий zcash/lightwallet-protocol).
- **Живые публичные lightwalletd-эндпоинты** — см. таблицу ниже
  (live-проверка 11.11.2026).
- **Мобильные SDK:** ECC zcash-android-wallet-sdk и
  zcash-swift-wallet-sdk — финальные 4.0.0, **End of Support при
  активации NU7** (Maven Central `cash.z.ecc.android:zcash-android-sdk`,
  последний pom 15.10.2026). Преемники ZODL (`zodl-inc/zodl-android-
  wallet-sdk`, zodl-swift-wallet-sdk) — **AGPL-3.0-only** (коммерческие
  лицензии отдельно; производны от ECC MIT SDK): код ZODL для VEYRO
  непригоден; Rust-крейты librustzcash лицензированы отдельно и остаются
  MIT OR Apache-2.0.
- **Transparent-данные через HTTP-API:** Blockchair жив
  (api.blockchair.com/zcash/stats — tip 3 562 426; адресные запросы —
  200; live 11.11.2026) — альтернатива прозрачному watch-only без gRPC;
  zecd.org жив; zfnd.org отдаёт 403; api.zcashblockexplorer.com
  недоступен с тестовой машины (ECONNRESET).
- **Explorer:** официального нет; shielded-данные в эксплорерах не
  видны (следствие протокола); прозрачные адреса/потоки — Blockchair и
  community-эксплореры.

### lightwalletd-переоценка (пересмотр прежнего вывода)

- **Прежний вывод** («lightwalletd требует собственный сервер → для
  VEYRO не подходит») **пересмотрен**. Public light-сервер — та же
  модель доверия, что public Electrum-сервер (BTC) и remote node (XMR):
  клиент сам сканирует цепь локально, сервер не владеет ключами.
- **Схема:** свет-сервер (lightwalletd / Zaino / native zebrad / …)
  фронтит полную ноду; клиент держит UFVK/IVK локально, тянет ZIP-307
  compact-блоки (GetChainTips/GetLatestBlock, GetBlockRange с Compact-
  данными пулов), сканирует их в собственном ядре (zcash_client_sqlite
  или своё хранилище); бродкаст — `SendTransaction`; прозрачные данные —
  `GetTaddressBalance` / `GetAddressUtxos`.
- **Что видит сервер:** IP, тайминги, запрашиваемые диапазоны блоков,
  запросы по прозрачным адресам, передаваемые транзакции. **Не видит:**
  viewing-ключи, shielded-баланс, shielded-получателей (скан локальный).
  Уровень утечки сопоставим с Electrum; для приватности — Tor (в
  zcash_client_backend присутствует интеграция Arti, скрывающая IP;
  сверить флаги/версию при интеграции), собственный сервер (опция для
  продвинутых пользователей), ротация серверов из списка.
- **Требования VEYRO:** пользовательский конфигурируемый список
  свет-серверов (по умолчанию — проверенные live), проверка chain и
  consensus branch при подключении (GetLightdInfo: chain «main»,
  branch `77190ad9`), предупреждение о приватности в UI; server-side
  скан/индексация по ключам пользователя — не используется.
- **История:** публичные серверы Zecwallet (`lwd.zecwallet.com`) мертвы
  (подтверждено форумом); актуальность серверов отслеживать по
  hosh.zec.rocks / status.zec.rocks.

### Живые публичные gRPC-эндпоинты (live 11.11.2026)

| Эндпоинт | Реализация | Бэкенд | Проверки (grpc-status 0, GetLightdInfo) |
|---|---|---|---|
| https://zec.rocks (+ na./eu./ap./sa.) | lightwalletd 0.6.1 | Zebra 7.0.0+git | branch `77190ad9`, NU7 |
| https://zec-node.cakewallet.com | lightwalletd 0.6.1 | Zakura 1.8.3 | branch `77190ad9` |
| https://zec.0xrpc.io | ZainoD 0.10.1 (ZingoLabs) | Zebra 7.0.0 | branch `77190ad9` |
| https://testnet.zec.rocks | lightwalletd | Zakura 1.7.0 | chain «test» |

- **GetLatestBlock (live):** высота **3 562 427**, идентичный hash на
  трёх серверах — согласованность сетевого состояния.
- **Прозрачный watch-only по gRPC (live):** `GetTaddressBalance` для
  реального mainnet t-адреса t1cpC3SS8okUsMQwTqWgzyA1k237B3WCeco
  (источник адреса — Blockchair API) = **46 485,230705 ZEC** —
  идентичный ответ на zec.rocks / zec-node.cakewallet.com /
  zec.0xrpc.io.
- **Путь бродкаста (live):** `SendTransaction` отвечает осмысленной
  ошибкой валидации на фиктивный tx (grpc-status 3 «bad transaction
  data», zec.rocks) — RPC жив и доходит до бэкенда; приём транзакций на
  бродкаст требует штатной сборки в VEYRO (не тестировалось).
- Недоступные: `lwd.zecwallet.com` (мертв), `zaino.unsafe.zec.rocks`
  (503, 11.11.2026).

## SDK и библиотеки

- **Rust-стек librustzcash** (crates.io, проверено 11.11.2026; все —
  MIT OR Apache-2.0):
  - `zcash_client_backend` 0.25.0 (21.10.2026) — client-логика, скан
    compact-блоков, gRPC-клиент ZIP-307 (tonic); README
    документирует CompactTxStreamer-интерфейс;
  - `zcash_client_sqlite` 0.23.0 (21.10.2026) — SQLite-хранилище
    счета/транзакций;
  - `zcash_primitives` 0.31.0, `zcash_keys` 0.17.0, `zcash_protocol`
    0.11.0, `zcash_address` 0.14.0, `zip32` 0.3.0 (деривация ZIP-32);
  - `orchard` 0.16.0 (30.09.2026), `pczt` 0.10.0 (10.11.2026; есть
    pre-release-ветка «keystone»);
  - Sapling-доказательства — Groth16 (файлы параметров), Orchard —
    Halo2 (параметры в составе крейта) — сверять загрузку/объём при
    интеграции.
- **Референс-реализации:** Zashi (мобильный, ECC), Zingolib/Zingo,
  Ywallet — все работают поверх ZIP-307 gRPC и librustzcash;
  zcashd-стиль RPC — Zallet (Linux)/zecd.
- **Flutter/Dart-интеграции:** официальной нет; путь VEYRO —
  собственное Rust-ядро (librustzcash) + FFI (uniffi/bridge);
  мобильные ECC SDK — EoS, ZODL SDK — AGPL (не заимствовать).
- **Лицензии зависимостей:** librustzcash, Zebra, Zallet, lightwalletd
  — MIT OR Apache-2.0 (совместимо с требованиями VEYRO); ZODL SDK —
  AGPL-3.0-only (исключить из заимствования).

### Rust-стек и сборка по платформам

- **Windows native (MSVC, x64):** крейты librustzcash — pure Rust,
  ожидаемо строятся (MSRV ~1.89+, сверить в Cargo.toml при интеграции);
  gRPC — tonic/rustls (HTTP/2); VEYRO-сборок пока нет — подтвердить
  первой интеграцией. Zebra — Tier 3 «может собраться, не тестируется»;
  Zallet — без chain-backend на Windows. Вывод: для Windows native
  годится только собственный кошельковый контур на librustzcash поверх
  публичного/своего lightwalletd gRPC.
- **Android (NDK, aarch64-linux-android):** тот же Rust-контур;
  существование рабочих сборок подтверждено ECC SDK 4.0.0 (Maven,
  MIT) — proof of concept переносимости; собственная интеграция VEYRO —
  не тестировалась. Код ZODL (AGPL) не заимствовать.
- **Linux (x86_64/aarch64):** полный серверный стек есть в релизах:
  zebrad 7.0.0 (деб-пакеты/Docker), Zallet beta.4 (musl amd64/arm64),
  lightwalletd, zainod. Tier 1 поддержка.
- **WSL2/Docker на Windows:** способ запустить Zebra+Zallet/Zaino для
  разработки и тестов (Linux-окружение внутри WSL2); не является
  «нативной» поддержкой в приложении — только dev-скрипты.
- **iOS:** аналогично Android (Rust-контур переносим — ECC Swift SDK
  4.0.0 как доказательство); вне приоритета VEYRO.

## Совместимость кошелька

Реализуемость подтверждена на уровне архитектуры и live-проверок
инфраструктуры; **в VEYRO ничего не реализовано и не тестировалось** —
галочки не проставлены.

- [ ] Создание кошелька — seed (ZIP-32/BIP39) → zcash_client_sqlite
- [ ] Импорт кошелька — seed / UFVK (watch-only)
- [ ] Восстановление — скан от birthday; watch-only — скан по UFVK
- [ ] Получение — unified `u1…` (а также прозрачный `t1…`); QR; URI
      (ZIP-321 — сверить параметры)
- [ ] Баланс — shielded: локальный скан compact-блоков; transparent:
      GetTaddressBalance/GetAddressUtxos (live подтверждено) или
      wallet-стек
- [ ] История транзакций — wallet-стек (скан); прозрачные адреса —
      свет-сервер/Blockchair
- [ ] Отправка — transparent: UTXO-сборка + SendTransaction; shielded:
      PCZT/скрытые траты (только после реализации; не заявлять)
- [ ] Мониторинг подтверждений — GetLatestBlock/GetBlockRange (compact),
      подсчёт подтверждений по высоте

### Матрица VEYRO: платформа × режимы

Оценка архитектурной реализуемости (не факт поддержки; в VEYRO ничего
не тестировалось). Шкала: Research required / Researched / Watch-only /
Receive / Send / Full / Blocked.

| Платформа | Полный shielded-цикл | Shielded watch-only | Transparent (t) |
|---|---|---|---|
| Windows native (MSVC) | Research required | Researched | Researched |
| Windows WSL2/Docker (dev) | Researched (beta-стек Zebra+Zallet) | Researched | Researched |
| Linux (x86_64/aarch64) | Researched (Zallet beta.4 + zebrad) | Researched | Researched |
| Android (NDK + Rust-ядро) | Research required (собственный контур; ECC SDK как proof-of-portability) | Researched | Researched |

- Полный shielded-цикл на нативных клиентах = собственный Rust-контур
  (скан + build/spend через pczt/librustzcash) поверх ZIP-307 gRPC;
  готовых desktop/Android-сборок такого контура в экосистеме под
  совместимой лицензией нет (Zashi/ZODL — мобильные референсы, ZODL под
  AGPL; Zallet — Linux-only).
- Shielded watch-only = UFVK/IVK-скан compact-блоков через
  zcash_client_backend — самый зрелый и переносимый кусок стека.
- Transparent = Bitcoin-подобные UTXO + ZIP-307
  (GetAddressUtxos/GetTaddressBalance/SendTransaction) — live
  подтверждено на публичных серверах 11.11.2026.

### Режимы работы без серверов VEYRO (архитектурное требование)

- **Без своего сервера и без любой ноды: НЕТ.** Минимум нужен
  свет-сервер (ZIP-307 gRPC) — индексный сервис, оффлайн-сканирование
  невозможно.
- **Без своего сервера, через публичный свет-сервер: ДА** (аналог
  Electrum/remote node). Полный прозрачный цикл и shielded-скан
  локально; траты shielded — контуром librustzcash (не тестировано).
  Цена: доверие третьей стороне на уровне видимости «IP + диапазоны
  блоков + t-адресные запросы»; пользовательский список серверов,
  проверка chain/branch, предупреждение в UI; Tor — опция.
- **Без своего сервера, с локальной/своей нодой: ДА (Linux/WSL).**
  Zebra + (Zallet | zecd | Zaino/lightwalletd на loopback) — максимум
  приватности; на Windows native полная нода — Tier 3 (не тест),
  практическая опция — только dev окружение.
- **Полный оффлайн:** невозможно (кроме подписания заранее построенной
  транзакции в PCZT-стиле — сверять при интеграции).

## Безопасность и ограничения

- **Известные ограничения:** zcashd мёртв (EoL 18.07.2026) — старые
  руководства/библиотеки непригодны; мобильные SDK ECC — EoS (NU7);
  приёмники ZODL — AGPL; Zallet — beta (hardening отстаёт), Linux-only
  chain-backend; PCZT-методы Zallet ещё не полные (issue #99);
  экспериментальный native gRPC zebrad — plaintext и «не для машин
  пользователей»; публичные свет-серверы — доверие третьей стороне.
- **Риски безопасности:** публично раскрытая 01.06.2026 уязвимость
  Orchard в zcashd (показывает важность немедленного обновления
  клиентского Rust-стека); Sapling — исторический trusted setup
  (церемония завершена; Orchard его не требует); NU7 свежа —
  консенсус-правила продолжают меняться между апгрейдами; privacy —
  свет-сервер видит метаданные запросов (см. раздел переоценки).
- **Блокеры для полного shielded-цикла:** отсутствие
  протестированного в VEYRO spend-контура и готового
  лиценз-совместимого референса; на Windows native — отсутствие
  Zallet-бэкенда (не блокирует собственный стек, но усложняет
  валидацию против референса).

## Вывод для матрицы

- **Идентичность:** подтверждена (ZEC = Zcash).
- **Динамика:** прежний вердикт «Blocked: нет нативной
  Windows-инфраструктуры» снят. Он ошибочно приравнивал консенсусную
  ноду (Zebra) и Zallet к кошельку: лёгкий клиент VEYRO не требует
  полной ноды и работает поверх ZIP-307 gRPC свет-серверов (аналогия
  Electrum/remote node подтверждена live-проверками 11.11.2026).
- **Рекомендуемый статус: Researched.**
  - Transparent-режим (получение/отправка по t-адресам, UTXO-модель):
    Researched, реализуем одним собственным Rust-контуром на всех
    целевых платформах (Windows/WSL/Android/Linux); инфраструктура
    публичных свет-серверов подтверждена живыми проверками.
  - Shielded watch-only (UFVK/IVK-скан compact-блоков через
    zcash_client_backend): Researched — зрелый переносимый стек; в
    реализации и тестах VEYRO не был.
  - Полный shielded-цикл (скан + скрытые траты): **Research required** —
    не заявлять в матрице до собственной реализации и прохождения
    тестов; референсы под совместимой лицензией отсутствуют (ZODL —
    AGPL, Zallet — Linux beta).
  - После реализации прозрачного цикла статус по шкале может подниматься
    до Watch-only/Receive/Send/Full по факту проверок (см. чек-лист).
- **Главные риски:** (1) собственная spend-реализация shielded —
  единственный путь Full (высокая сложность zk-части); (2) зависимость
  от публичных свет-серверов — их смерть/смена политики (история:
  Zecwallet-серверы мертвы); обязательны список серверов, проверка
  chain/branch и Tor-опция; (3) быстрая эволюция протокола (NU7→ далее,
  ZIP 218/237) и beta-статус Zallet — версионировать зависимости и
  держать консенсус-ветку в конфиге.

## Источники

1. https://zcash.github.io/zcash/user/end-of-life.html — EoL zcashd
   (halt 18.07.2026, блок 3417100); раскрытие Orchard-уязвимости
   01.06.2026 (дата по релизным заметкам ECC).
2. https://github.com/zcash/zcash — архив zcashd; последний релиз 6.20.0.
3. https://github.com/ZcashFoundation/zebra/releases — Zebra 7.0.0
   (22.10.2026; NU7 mainnet, БД v29), 7.1.0-alpha.0 (30.10.2026);
   PR #10953 (native CompactTxStreamer), issue #11158.
4. https://zebra.zfnd.org/user/supported-platforms.html — Tier 1/2/3
   (Windows/macOS — Tier 3); MSRV.
5. https://zebra.zfnd.org/user/zcashd-api-migration-guide.html —
   владение RPC Zebra (getaddress*/getraw*/z_* и Zebra-only методы).
6. https://zebra.zfnd.org/user/lightwalletd.html — запуск lightwalletd
   перед zebrad :8232; экспериментальный direct serving (plaintext,
   TLS-прокси, unverified vs SDK).
7. https://github.com/zcash/zallet/releases — Zallet v0.1.0-beta.4
   (02.11.2026); релизные артефакты Linux musl amd64/arm64.
8. https://zcash.github.io/zallet/guide/platform-support.html —
   платформы Zallet (Windows: сборка в CI, Linux-only chain backend).
9. https://github.com/zcash/lightwalletd — lightwalletd (Go;
   README на zebrad-бэкенд); на живых серверах 0.6.1 (live,
   11.11.2026).
10. https://github.com/zcash/lightwallet-protocol — ZIP-307 protos
    (CompactTxStreamer).
11. https://forum.zcashcommunity.com/t/current-ways-to-connect-to-grpc-
    in-the-zcash-stack-lwd-zaino-zebrad-zakura-ztreamer/57539 — обзор
    gRPC-стека (обновлён 09.11.2026): lwd/Zaino/zebrad/Zakura/ztreamer;
    смерть серверов Zecwallet.
12. https://zips.z.cash — ZIP-316 (UA), ZIP-32 (деривация), ZIP-317
    (комиссии), ZIP-321 (URI), ZIP 218/237 (NU7), ZIP-259 (branch ID).
13. https://crates.io/crates/zcash_client_backend (0.25.0),
    /zcash_client_sqlite (0.23.0), /zcash_primitives (0.31.0),
    /zcash_keys (0.17.0), /zcash_protocol (0.11.0), /zcash_address
    (0.14.0), /zip32 (0.3.0), /orchard (0.16.0), /pczt (0.10.0) —
    версии и лицензии (проверено 11.11.2026).
14. https://github.com/zcash/zcash-android-wallet-sdk и
    https://github.com/zcash/zcash-swift-wallet-sdk — финальные 4.0.0,
    EoS при NU7 (MIT); Maven Central cash.z.ecc.android (pom
    15.10.2026).
15. https://github.com/zodl-inc/zodl-android-wallet-sdk — преемник
    ECC SDK, лицензия AGPL-3.0-only (для VEYRO непригоден; Rust-крейты
    под своими MIT/Apache лицензиями).
16. https://github.com/ZcashFoundation/z3 — связка Zebra+Zaino+Zallet.
17. Live-проверки 11.11.2026 (gRPC по node http2+TLS, GetLightdInfo /
    GetLatestBlock / GetTaddressBalance / SendTransaction): 
    https://zec.rocks (+ na./eu./ap./sa.; оператор zecrocks/zcash-stack,
    реестр hosh.zec.rocks / status.zec.rocks),
    https://zec-node.cakewallet.com, https://zec.0xrpc.io,
    https://testnet.zec.rocks; tip 3 562 427; branch `77190ad9`;
    t-баланс t1cpC3SS8okUsMQwTqWgzyA1k237B3WCeco = 46 485,230705 ZEC
    (адрес — из Blockchair API).
18. https://api.blockchair.com/zcash/stats — Blockchair Zcash API
    (tip 3 562 426; адресные запросы; live 11.11.2026).
19. https://zecd.org — zecd 0.6.0 (site 200, live 11.11.2026).

---

*Паспорт обновлён: 2026-11-11. Live-проверки (gRPC-пробы, HTTP-API)
выполнены в этот день; всё остальное — первоисточники с датами из
раздела «Источники».*
