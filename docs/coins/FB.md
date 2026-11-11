# Технический паспорт монеты: FB

> Паспорт составлен по состоянию на ноябрь 2026. Критические параметры — из
> официальных исходников fractal-bitcoin/fractal (branch fractal-29.x),
> docs.fractalbitcoin.io и FIP-документов. Неподтверждённое помечено
> `НЕ ПОДТВЕРЖДЕНО`.

- **Тикер(ы):** FB (Fractal Bitcoin). Внимание на коллизии: тикер «FB»
  исторически носили другие проекты (например, FewBit — FBIT, FortuneBlock —
  FTB); в майнинговом контексте ноября 2026 «FB» = Fractal Bitcoin
  (подтверждено WhatToMine coin 431 SHA-256d и пулами f2pool/ViaBTC).
- **Официальное название проекта:** Fractal Bitcoin
- **Официальный сайт:** https://fractalbitcoin.io (+ FAQ)
- **Официальный репозиторий:** https://github.com/fractal-bitcoin/fractal
  (branch `fractal-29.x`; база — Bitcoin Core 29.x; node-релизы:
  github.com/fractal-bitcoin/fractald-release)
- **Официальная документация:** https://docs.fractalbitcoin.io (включая
  llms.txt; markdown-версии страниц добавлением `.md`), FIP-репозиторий
  https://github.com/fractal-bitcoin/fips
- **Статус исследования:** завершено (desk research, ноябрь 2026; сетевые
  тесты не проводились)

## Идентификация сети

- **Mainnet:**
  - Genesis-хэш = генезис Bitcoin:
    `000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f`
    (Fractal — рекурсивный слой Bitcoin, стартует с того же генезиса).
    Блок 1 (pre-allocation **105,000,000 FB**):
    `00000000000000005a5c13fe33f6717c7ad81fc8837ae75e4693c16acbdd0f66`.
  - Magic bytes: `0xd99e94b9`
  - Порты (два источника, конфликт разрешён): в `chainparamsbase` дефолты как у
    Bitcoin — **P2P `8333`, RPC `8332`** (в docs майнинга bitcoin.conf также
    `rpcport=8332`); официальный же fractal-indexer-deploy публикует стек с
    **P2P `10333`, RPC `10332`, ZMQ `10330`/`10331`** (Docker-стек
    переопределяет дефолты; в этом же стеке майнер-пример подключается к
    10332). В паспорте фиксируются оба значения: для подключения к
    пользовательскому узлу ориентироваться на его конфиг; для VEYRO —
    конфигурируемо.
  - Блок: **30 секунд**; PoW **SHA256d**; сложность ASERT (halflife 3 часа).
  - Майнинг cadence **1:1:1**: merged mining / permissionless / index mining
    (последовательность блоков делится поровну).
  - Merged mining: механизм как Namecoin, **ChainID `0x2024`**, RPC
    `createauxblock`/`submitauxblock` (старый `getauxblock` НЕ поддержан);
    в RPC merged-данные вырезаются из `getblock`/`getblockheader` для
    совместимости.
  - Награда: старт 25 FB; халвинг каждые 2,100,000 блоков. **FIP-102 активирован
    на блоке 2,100,000 (~09.09.2026): двойной халвинг 25 → 12.5 → 6.25 FB за
    один блок** + эквивалентный бюджет 6.25 FB на распределение нативного FB
    в Bitcoin mainnet (rollout ~3 месяца, FIP-103: конвертация FB Fractal ↔
    FB на Bitcoin mainnet 1:1).
  - Эмиссия: pre-allocation 105M (блок 1) + майнинговая асимптота ~105M
    (геометрический ряд 25×2.1M/(1−½)); после FIP-102 основная награда на
    цепи — 6.25 FB/блок.
  - Требуемая версия узла: **fractald v0.4.0+** (координированный апгрейд к
    блоку 2,100,000).
  - DNS seeds: `dnsseed-mainnet.fractalbitcoin.io`,
    `dnsseed-mainnet.unisat.io`.
- **Testnet:** magic `0xe8ada3c8`, P2P `18333`, RPC `18332`, тот же
  Bitcoin-генезис (см. docs wallet-integration: testnet-эндпоинты
  mempool-testnet.fractalbitcoin.io и др.).
- **Проверка идентичности:** Fractal Bitcoin — merge-mined SHA256d-чейн на базе
  Bitcoin Core 29 (mainnet сентябрь 2024; >900k держателей в первый месяц);
  >50% hashrate Bitcoin участвует в merged mining; листинги HTX, Gate.io,
  KuCoin, Bybit; WhatToMine ведёт FB (coin 431). «FB» ≠ любой другой
  исторический тикер FB — в матрице зафиксирована именно сеть Fractal.

## Криптография и ключи

- **Формат адреса:** **полностью идентичен Bitcoin** (base58/bech32 префиксы
  BTC: PUBKEY 0 → `1...`, SCRIPT 5 → `3...`, HRP `bc` → `bc1q...`,
  Taproot `bc1p...`). Прямые подтверждения: docs («Fractal uses the same
  address format as Bitcoin — wallet compatibility is seamless, no new setup
  or conversions required»), FAQ, wallet-integration. Это и главное
  удобство, и главный риск (см. «Безопасность»).
- **Формат публичного ключа:** SEC1 secp256k1 (как Bitcoin).
- **Формат приватного ключа:** WIF `0x80`; xprv/xpub стандартные Bitcoin
  (`0x0488ADE4`/`0x0488B21E`).
- **Схема деривации ключей:** BIP32/BIP39. **SLIP-44: регистрация для FB
  ОТСУТСТВУЕТ** (в списке satoshilabs нет Fractal). Основной кошелёк FB —
  UniSat Wallet — переиспользует Bitcoin-аккаунты (адреса BTC-формата);
  ожидаемая деривация — как у BTC (coin type 0, purposes 44/49/84/86), но
  точный path UniSat для Fractal-аккаунтов в исследовании напрямую не
  вскрыт — `НЕ ПОДТВЕРЖДЕНО`; сверить при интеграции. Для приёма выплат на
  уже существующие bc1p/bc1q-адреса майнера VEYRO должен уметь импортировать
  ключи стандартных BTC-дериваций.
- **Мнемонический стандарт:** BIP39 (UniSat/совместимые кошельки).
- **Алгоритм подписи:** ECDSA secp256k1 + Schnorr (Taproot).
- **Совместимость восстановления из фразы:** BIP39-фраза BTC-совместимого
  кошелька даёт те же адреса на Fractal (те же префиксы). Следствие: одна
  фраза управляет и BTC, и FB — VEYRO обязан чётко разделять сети в UI и
  бэкенде.

## Транзакции

- **Структура транзакции:** Bitcoin-совместимая UTXO (база Bitcoin Core 29):
  SegWit, Taproot (min_activation_height 709632), BIP34/65/66/CSV/SegWit —
  активны с высоты 1.
- **Расчёт комиссии:** sat/vByte, как Bitcoin; ориентир комиссий — официальный
  mempool-API (см. «Доступ к сети»).
- **Блокировки/имматурность:** coinbase maturity Bitcoin-стандарта 100 блоков
  (~50 минут при 30-сек блоках); `НЕ ПОДТВЕРЖДЕНО` прямым чтением consensus.h
  fractal — сверить при реализации.
- **Модель баланса:** UTXO.
- **Особые поля:** протоколы уровней (не обязательны для базовых выплат):
  Ordinals (активация с высоты 21,000), BRC-20 (тикеры 6–12 байт, self_mint),
  Runes (высота 84,000), CAT20 (OP_CAT); FIP-101 indexer-параметры (высота
  1,500,000); FIP-102/103 — нативный FB на Bitcoin mainnet с конвертацией
  1:1 (влияет на отображение «FB на BTC» — отдельный актив, вне scope).

## Доступ к сети

- **Методы RPC:** полный набор Bitcoin Core + `createauxblock`/`submitauxblock`
  (merged mining); RPC-порт `8332` (дефолт) или `10332` (индексер-стек).
- **P2P-протокол:** порт `8333` (дефолт) / `10333` (публикуемый в официальных
  deploy-стеках); wire Bitcoin-совместимый (magic `0xd99e94b9`).
- **Лёгкий клиент:** Electrum-совместимой инфраструктуры для FB **не
  обнаружено** (`НЕ ПОДТВЕРЖДЕНО` существование публичных Electrum-серверов);
  BIP157/158 (CB-filters) в Core-линии отсутствуют; доступные модели:
  (а) RPC пользовательского/знакомого узла (fractald), (б) BIP37 bloom SPV
  (опциональная поддержка на стороне узла, как в Bitcoin Core), (в)
  централизованные API (UniSat Open API, mempool-API Fractal) — с явными
  оговорками приватности/централизации. Для честной модели VEYRO — primary
  RPC пользовательского fractald.
- **Узел:** fractald v0.4.0+ (Bitcoin Core 29-база); полная цепь + индекс —
  >3 TB для индексер-стеков (официальная оценка fractal-indexer-deploy; сам
  узел без индекса меньше — точно `НЕ ПОДТВЕРЖДЕНО`); pruning — по
  возможностям Core-базы.
- **Публичные RPC:** официальных публичных RPC-нод нет; UniSat Open API —
  ключ через developer.unisat.io (централизованный, rate-limited;
  использовать только как fallback и для эксплорер-данных).
- **Explorer:**
  - **mempool.fractalbitcoin.io** — официальный mempool-инстанс (mainnet);
    mempool-API для комиссий (testnet: mempool-testnet.fractalbitcoin.io)
  - **UniScan: uniscan.cc/fractal** — brc-20/ординалы-эксплорер UniSat
  - Ordinals-сервер: ordinals-testnet.fractalbitcoin.io (тестнет)

## SDK и библиотеки

- **Официальные SDK:** узел (fractald, C++/Core-29), fractal-indexer,
  fractal-proof-publisher (FIP-101 proofs); UniSat Open API (Swagger:
  open-api-fractal.unisat.io) — REST, не SDK; UniSat Wallet (браузерное
  расширение) — reference-кошелёк.
- **Rust-библиотеки:** **прямо применим `rust-bitcoin`** (MIT OR
  Apache-2.0) — адреса, скрипты, подписи, PSBT полностью Bitcoin-совместимы;
  из отличий сети — только chainparams (magic, genesis post-1, target
  spacing 30 с, ASERT 3 ч) и порт. Это самая дешёвая интеграция из пяти
  исследуемых монет на уровне ядра.
- **Flutter/Dart-интеграции:** готового пакета нет; FFI к Rust-ядру (модуль
  BTC переиспользуется почти целиком).
- **Лицензии зависимостей:** fractal/fractald — лицензия Bitcoin Core (MIT);
  rust-bitcoin — MIT OR Apache-2.0. Совместимо с ядром VEYRO.

## Совместимость кошелька

Отметка = реализуемо существующими средствами (фактический статус — только
после тестов):

- [x] Создание кошелька — BIP39 + BTC-деривации (44/49/84/86, coin 0);
  явная маркировка сети FB в UI
- [x] Импорт кошелька — WIF, xprv, фраза (BTC-совместимые; с предупреждением,
  что фраза может управлять и BTC)
- [x] Восстановление — сканирование стандартных BTC-путей в сети FB
- [x] Получение — `bc1p...`/`bc1q...`/`1...`/`3...` (пулы платят на
  Bitcoin-формат: подтверждено docs — coinbase-addr `bc1q...` в примере
  майнинга)
- [x] Баланс — UTXO через RPC (`scantxoutset`/`gettxout`-сканирование или
  собственный индекс по ZMQ/`getblock`)
- [x] История транзакций — RPC (+ ссылки на mempool.fractalbitcoin.io)
- [x] Отправка — построение/подпись rust-bitcoin, бродкаст `sendrawtransaction`
- [x] Мониторинг подтверждений — заголовки P2P/RPC (30-сек блоки → быстрые
  подтверждения)

## Безопасность и ограничения

- **ГЛАВНЫЙ РИСК — кросс-чейн путаница BTC ↔ FB:** форматы адресов, WIF,
  xprv/xpub и деривации полностью идентичны Bitcoin. Ошибка сети = безвозвратная
  потеря средств (BTC отправлены на FB-адрес или наоборот). Требования VEYRO:
  - отдельные, визуально различные сетевые профили FB/BTC;
  - бродкаст только в сеть FB с проверкой magic/генезиса подключённого узла;
  - при импорте фразы явное предупреждение о совместимости ключей с BTC;
  - проверку баланса вести только против FB-узлов (не BTC-эндпоинтов).
- **FIP-102 (сентябрь 2026) уже активирован:** все бэкенды VEYRO-совместимые
  должны быть fractald ≥ v0.4.0; правила награды 6.25 FB/блок + распределение
  на Bitcoin mainnet — учитывать при отображении наград/событий.
- **Нет лёгкой инфраструктуры:** без Electrum/BIP157 SPV-доступ возможен
  только через RPC узла (или централизованные API) — противоречит лёгкой
  модели, но совместимо с ограничением VEYRO «RPC пользовательских узлов»;
  пользователь обязан подключать свой/доверенный fractald.
- **Pre-allocation 105M FB (блок 1)** — централизованная часть эмиссии
  (управляется командой проекта) — экономический, не технический риск.
- **Merged mining** упрощает безопасность (наследует >50% hashrate Bitcoin),
  но структура блоков содержит aux-данные — парсеры должны учитывать их
  отсутствие в RPC-ответах.
- **Блокеры:** нет для базового цикла через RPC узла; лёгкий клиент
  (Electrum/SPV) отсутствует — это ограничение модели доступа, не блокер при
  RPC-подходе.

## Вывод для матрицы

- **Идентичность:** подтверждена (официальный сайт/репозиторий Fractal
  Bitcoin; WhatToMine coin 431 = FB SHA-256d; FIP-документы; пулы f2pool/
  ViaBTC; НЕ тикеры-омонимы прошлых лет — зафиксировано в матрице ранее).
- **Реализуемость:** полная на уровне ядра (rust-bitcoin + chainparams), но
  модель доступа — только RPC пользовательского узла (лёгкой инфраструктуры
  нет).
- **Главный риск:** кросс-чейн путаница BTC ↔ FB из-за идентичных
  адресов/ключей — требует специальных UX- и сетевых защит; плюс отсутствие
  SLIP-44/стандартизированной деривации (свобода + опасность).
- **Предлагаемый статус:** `Research required` → кандидат на
  `Receive supported` (приём выплат) сразу после тестов приёма/баланса;
  `Full support` — после отработки полного цикла через RPC пользовательского
  узла с кросс-чейн защитами. До тестов статус не менять.

## Источники

1. https://github.com/fractal-bitcoin/fractal — официальный репозиторий узла
   (branch fractal-29.x, база Bitcoin Core 29): chainparams (genesis =
   Bitcoin genesis, magic 0xd99e94b9, spacing 30 с, ASERT 3 ч, порты,
   ChainID/fStrictChainId, Taproot, DNS seeds, indexerParams FIP-101)
2. https://fractalbitcoin.io — официальный сайт (introduction, FAQ:
   «same address format as Bitcoin», «UniSat Wallet is fully integrated»,
   merged mining >50% hashrate BTC, биржи HTX/Gate.io/KuCoin/Bybit)
3. https://docs.fractalbitcoin.io — документация: wallet-integration (testnet,
   RPC & API, UniSat Open API), for-miners (SHA256d, merged mining ChainID
   0x2024, createauxblock/submitauxblock, coinbase-addr `bc1q...`),
   llms.txt-индекс
4. https://github.com/fractal-bitcoin/fips/blob/main/FIP-102/FIP-102_Native_FB_on_Bitcoin_Mainnet_final.md —
   FIP-102 (финальный): активация на блоке 2,100,000 (~09.09.2026),
   двойной халвинг 25→12.5→6.25 FB, распределение нативного FB на Bitcoin
   mainnet, fractald v0.4.0 rc
5. https://github.com/fractal-bitcoin/fractal-indexer-deploy — официальные
   deploy-стеки: порты P2P 10333 / RPC 10332 / ZMQ 10330-10331 (при дефолтах
   chainparamsbase 8333/8332); требование полного узла+индекса >3 TB для
   индексера; broadcast через sendrawtransaction
6. https://uniscan.cc/fractal и https://mempool.fractalbitcoin.io —
   официальные эксплореры (UniScan; mempool-инстанс Fractal)
7. https://developer.unisat.io / https://open-api-fractal.unisat.io — UniSat
   Open API (Swagger; ключи) — централизованный fallback
8. https://github.com/satoshilabs/slips/blob/master/slip-0044.md — SLIP-44:
   регистрации для Fractal Bitcoin НЕТ (проверено по полному списку)
9. WhatToMine (coin 431, SHA-256d) и пулы f2pool/ViaBTC (merged mining FB) —
   независимое подтверждение идентичности тикера в майнинговом контексте
   ноября 2026
