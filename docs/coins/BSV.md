# Технический паспорт: Bitcoin SV (BSV)

> Паспорт монеты для некастодиального мультичейн-кошелька VEYRO (Rust-ядро + Flutter UI, без собственных backend-серверов).
> Составлено: 11.11.2026. Критические параметры подтверждены исходным кодом узла + независимыми источниками (минимум 2 источника).
> Всё, что не удалось подтвердить, помечено **«НЕ ПОДТВЕРЖДЕНО»**.

## 1. Идентичность и официальные источники

| Параметр | Значение |
|---|---|
| Название | Bitcoin SV («Satoshi's Vision») |
| Тикер | BSV |
| Тип сети | L1, Proof-of-Work, SHA-256d (двойной SHA-256), без SegWit |
| Десятичность | 8 знаков; 1 BSV = 100 000 000 сатоши |
| Происхождение | Форк Bitcoin Cash 15.11.2018; до этого общая история с BTC до 01.08.2017 (UAHF) |
| Состояние сети | Высота **975 049** блоков, best hash `00000000000000000d3bee72ff1bdbb44f75c709aa8f1f7426ed862de3e1dd31`, difficulty ~2.92e10 (Whatsonchain API, 11.11.2026) |

Официальные/первичные источники:
- Референсный узел: **SV Node** — https://github.com/bitcoin-sv/bitcoin-sv — ⚠️ лицензия **Open BSV License** (не MIT/Apache; см. §7)
- Тяжёлый узел: **Teranode** — https://github.com/bitcoin-sv/teranode (v0.16.1-beta-5 от 01.11.2026 — по предыдущей проверке)
- Официальная документация: **BSV Hub** — https://hub.bsvblockchain.org (BSV Skills Center / BSV Academy)
- Вики: https://wiki.bitcoinsv.io
- Официальный эксплорер/API: https://whatsonchain.com (документация: https://docs.whatsonchain.com)
- Управление протоколом: BSV Blockchain Association (BSVA); правовые механизмы DAR / Network Access Rules — см. §9

Смежные эксплореры: bitails, satoshi.io — проверены на предыдущих этапах исследования; повторно в текущем проходе не проверялись (**«НЕ ПОДТВЕРЖДЕНО» повторно**).

## 2. Идентификация сети

### Mainnet
| Параметр | Значение | Источник |
|---|---|---|
| Genesis hash | `000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f` — общий с Bitcoin mainnet | assert в chainparams.cpp SV Node + chainparams Bitcoin Core (2 источника) |
| Merkle root genesis | `4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b` | там же |
| Параметры genesis | nTime 1231006505, nBits 0x1d00ffff, nNonce 2083236893, награда 50 BSV | там же |
| Network magic | **0xE3E1F3E8** | chainparams.cpp (netMagic[0..3]) |
| Порт P2P | 8333 | там же |
| Порт RPC | 8332 | chainparamsbase.cpp |
| DNS seeds | seed.bitcoinsv.io, seed.satoshisvision.network, seed.bitcoinseed.directory | chainparams.cpp |

### Тестовые сети
| Сеть | Magic | P2P | RPC | Genesis |
|---|---|---|---|---|
| testnet3 | 0xF4E5F3F4 | 18333 | 18332 | `000000000933ea01ad0ee984209779baaec3ced90fa3f408719526f8d77f4943` (= BTC testnet3; assert в коде SV Node + Bitcoin Core — 2 источника) |
| STN (Scaling Testnet) | 0xFBCEC4F9 | 9333 | 9332 | тот же genesis BTC testnet3 (nTime 1296688602, nNonce 414098458; assert в коде SV Node) |
| regtest | 0xDAB5BFFA | 18444 | 18332 (как в коде SV Node) | `0f9188f13cb7b2c71f2a335e3a4fc328bf5beb436012afca590b1a11466e2206` |

- STN периодически сбрасывается (последний сброс — февраль 2024, по предыдущей проверке; URL для цитирования недоступен — **«НЕ ПОДТВЕРЖДЕНО» повторно**).
- Префиксы base58: mainnet P2PKH 0 / P2SH 5 / WIF 128 / xpub 0x0488B21E / xprv 0x0488ADE4; testnet3+STN+regtest: P2PKH 111 (`m/n...`), P2SH 196, WIF 239, xpub 0x043587CF / xprv 0x04358394 (код SV Node).
- ⚠️ ВАЖНО (2026): 07.04.2026 активирован релиз **Chronicle** (высота ~943 816 — по предыдущей проверке). Интерпретатор SV Node поддерживает эры Post-Genesis / Post-Chronicle: в коде (interpreter.cpp) — «Post-Chronicle, malleability is permitted if txn version > 1».

## 3. Криптография и ключи

- Кривая: **secp256k1**. Подписи: **ECDSA** (Schnorr/Taproot на BSV отсутствуют).
- Публичный ключ: сжатый (33 байта) — стандарт.
- **Формат адресов: только Base58Check (legacy)** — в chainparams SV Node отсутствуют bech32/cashaddr HRPs (проверено чтением кода):
  - P2PKH: байт-префикс 0x00 → адреса `1...`
  - P2SH: байт-префикс 0x05 → адреса `3...` — ⚠️ P2SH **удалён из протокола** при Genesis-обновлении 04.02.2020 (высота 620538 — по предыдущей проверке); исторические P2SH-выходы существуют, новые P2SH нестандартны.
- Примеры адресов (из живых транзакций Whatsonchain API, 11.11.2026):
  - `198fZubHNnhsdENHbktQLw96eDMnhZ4xXM` — P2PKH, coinbase-выход блока 975 048 (3.12502485 BSV)
  - `1Jxk6QK5N9JEJpAevzvYvyeMtgmspK517h` — P2PKH, обычная транзакция того же блока
- WIF: префикс 0x80 (128) mainnet; 0xEF (239) testnet.
- BIP32: стандартные версии mainnet (0x0488B21E / 0x0488ADE4); тестовые 0x043587CF / 0x04358394.
- SLIP-44: coin type **236**.
- Деривация:
  - Канонический путь по BIP44+SLIP-44: `m/44'/236'/0'/0/0`.
  - ⚠️ Фактические BSV-кошельки исторически не едины: унаследованные дофорковые BTC-бэкапы — `m/44'/0'/...`; специфичные пути BSV-кошельков — **«НЕ ПОДТВЕРЖДЕНО»**. Для VEYRO: основной путь `m/44'/236'`, опция «legacy m/44'/0'» для старых бэкапов, честное предупреждение пользователю.
- Мнемоника: BIP39 не является гарантированным стандартом экосистемы BSV; кросс-восстановление между BSV-кошельками — **«НЕ ПОДТВЕРЖДЕНО»**.

## 4. Транзакции

- Структура: классическая (nVersion, vin[], vout[], nLockTime). **Без SegWit** — witness-структуры не используются.
- Модель баланса: UTXO.
- **Sighash — подтверждено кодом узла + 3 независимыми источниками:**
  - Флаги (`src/script/sighashtype.h`): SIGHASH_ALL=0x01, SIGHASH_NONE=0x02, SIGHASH_SINGLE=0x03, **SIGHASH_CHRONICLE=0x20**, **SIGHASH_FORKID=0x40**, SIGHASH_ANYONECANPAY=0x80; маска базовых флагов 0x1F.
  - Выбор дайджеста (`src/script/interpreter.cpp`, SignatureHash, строки ~2112–2124): флаг FORKID (без CHRONICLE) → **BIP143-подобный дайджест UAHF**; иначе — **оригинальный (pre-fork TDA)**.
  - До Chronicle все стандартные подписи используют `SIGHASH_ALL|SIGHASH_FORKID` = 0x41 (BSV Hub, BSV Wiki). После Chronicle (07.04.2026) допускаются оба алгоритма; бит SIGHASH_CHRONICLE принуждает оригинальный дайджест и легален только в эру Chronicle (код узла + документация bsv-rs).
  - **Рекомендация для VEYRO: `SIGHASH_ALL|SIGHASH_FORKID` (0x41)** — совместим с обеими эрами.
- Комиссии: сатоши/байт; весовых скидок нет (SegWit отсутствует).
- Coinbase maturity: **100 блоков** (consensus.h SV Node; проверено ранее).
- Halving: интервал 210 000 (виден в коде SV Node; подтверждается живой coinbase-наградой 3.125 BSV в блоке 975 048 — 4-я эпоха). Следующий ~2028 г.
- Post-Chronicle: разрешена маллеируемость транзакций с nVersion > 1 (interpreter.cpp) — на базовый P2PKH-флоу не влияет.
- Размер блока: протокольно не ограничен (после Genesis 2020); фактические лимиты определяются майнерами/Network Access Rules — точные значения **«НЕ ПОДТВЕРЖДЕНО»**.

## 5. Сетевой доступ (без серверов VEYRO)

| Способ | Статус | Детали |
|---|---|---|
| Собственный узел SV Node + RPC | ✅ | JSON-RPC (bitcoin-cli-совместимый): 8332 mainnet / 18332 testnet3 / 9332 STN. Диск/RAM — **«НЕ ПОДТВЕРЖДЕНО»** (в chainparams SV Node нет assumed-констант) |
| P2P | ✅ | 8333 / 18333 / 9333 (STN) / 18444 (regtest); DNS-сид-лист в коде узла |
| Electrum-протокол | ⚠️ | Клиент ElectrumSVP 0.2.0 существует (по предыдущей проверке); публичная серверная инфраструктура BSV минимальна — список живых серверов **«НЕ ПОДТВЕРЖДЕНО»** |
| Публичный API Whatsonchain | ✅ (с оговорками) | REST: chain info, block, tx, **broadcast**; Mainnet + Testnet; лимит 3 req/s (free). Проверен живым 11.11.2026 (chain info, block-by-height, tx). ⚠️ Приватность: провайдер видит IP и все запрашиваемые адреса |
| ARC (TAAL / GorillaPool) | ⚠️ | Инфраструктура broadcast майнеров; централизована (по предыдущей проверке) |

Эксплореры: whatsonchain.com (живой, проверен 11.11.2026); bitails, satoshi.io (проверены ранее).

**Вывод:** полный цикл (баланс/история/broadcast) реализуем без серверов VEYRO двумя путями: (a) собственный SV Node, (b) публичный Whatsonchain API — с предупреждением о приватности и лимите 3 req/s. Лёгкого публичного пути уровня Electrum с избыточностью серверов — нет.

## 6. SDK и библиотеки

**Rust:**
- **bsv-rs** — стабильная **0.8.5** (пререлиз 0.9.0-beta.7), обновление **10.11.2026**, ~10 000 загрузок/90 дней, лицензия **MIT OR Apache-2.0**. Поддерживает: sighash (FORKID/CHRONICLE), BIP143-преимажи, SighashCache, парсинг транзакций, ECDSA (RFC 6979). Подтверждено: crates.io API + docs.rs, 11.11.2026. — активная, рекомендованная зависимость.
- bsv (rust) — 2.1.1 (11.12.2023), MIT, ~534 загрузок/90 дней — устаревает (crates.io).
- Альтернатива: rust-bitcoin (ключи/скрипты/сериализация) + собственный модуль BSV-sighash (дайджесты UAHF/BIP143 + оригинальный) — все параметры приведены в этом паспорте.

**Flutter/Dart:**
- bitcoin_base 7.3.0 (16.07.2026) — поддержка BSV: **P2PK/P2PKH** (по предыдущей проверке документации пакета).
- bsv (Dart, pub.dev) 1.0.11 (2022) — устаревший.

Официальных кошельковых SDK нет; BSV Hub документирует концепции (sighash, script) для самостоятельной реализации.

## 7. Лицензии зависимостей vs MIT OR Apache-2.0

| Зависимость | Лицензия | Совместимость с VEYRO |
|---|---|---|
| bsv-rs | MIT OR Apache-2.0 | ✅ |
| bsv (rust) | MIT | ✅ |
| bitcoin_base (Dart) | BSD-3-Clause | ✅ (атрибуция) |
| **SV Node / Teranode (референсный код)** | **Open BSV License** | ❌ **не пермиссивная** — не включать код узла в продукт; использовать только документацию/спецификации |

Для проприетарного продукта VEYRO: допустимы bsv-rs / rust-bitcoin / bitcoin_base; любое заимствование исходников SV Node / Teranode исключить.

## 8. Чек-лист совместимости VEYRO

| Операция | Статус | Что требуется |
|---|---|---|
| Создание кошелька (BIP39+BIP32) | ✅ | стандартные алгоритмы |
| Импорт seed (восстановление) | ⚠️ | нет единого стандарта деривации: поддержать `m/44'/236'` (SLIP-44) + опцию `m/44'/0'` (наследие BTC); предупреждать пользователя |
| Импорт WIF | ✅ | префикс 0x80 |
| Получение (receive, QR) | ✅ | base58 P2PKH `1...` |
| Баланс | ✅ | WOC API / свой узел |
| История | ✅ | WOC API / свой узел |
| Сборка + подпись транзакции | ✅ | bsv-rs (sighash FORKID/CHRONICLE поддержаны) или rust-bitcoin + собственный дайджест |
| Broadcast | ✅ | WOC API (broadcast) / sendrawtransaction своего узла; ⚠️ зависимость от малого числа провайдеров |
| Полный цикл без серверов VEYRO | ✅ технически | через WOC (публичный) или собственный узел |

## 9. Безопасность, лимиты, блокеры

1. **Правовые / governance-риски**: протокол контролируется единственной организацией (BSVA/nChain); механизмы DAR (Digital Asset Recovery) и Network Access Rules создают прецедент вмешательства в «неизменяемость» (по предыдущим проверкам) — репутационный риск для некастодиального кошелька.
2. **Chronicle-эра (07.04.2026)**: правила недавно менялись (допуск оригинального дайджеста, маллеируемость nVersion>1) — необходим регулярный аудит против актуального SV Node.
3. **Инфраструктура**: публичные API/broadcast сконцентрированы (WOC, ARC TAAL/GorillaPool); отказ провайдера = недоступность send/broadcast без собственного узла.
4. **Деривации**: отсутствие стандарта — риск потери доступа при восстановлении «чужими» seed-фразами; нужен явный выбор пути в UI.
5. **Сжимающаяся клиентская экосистема**: пример — Edge wallet исключил поддержку BSV в июле 2026 (по предыдущей проверке).
6. Лимиты публичного API (3 req/s WOC) — приемлемы для одного пользователя, непригодны для агрегированных сервисов.

## 10. Вердикт для матрицы совместимости

### **Research required**

Шкала: Research required → Watch-only → Receive supported → Send supported → Full support (Blocked — отдельно).

Параметры сети и криптографии подтверждены полностью (адреса, sighash, genesis, порты, maturity), полный цикл технически реализуем без серверов VEYRO. Статус понижен из-за:
- правовых рисков и единого контролёра протокола (BSVA / DAR / Network Access Rules);
- отсутствия стандартизированной деривации/seed (риск при восстановлении);
- тонкой публичной инфраструктуры (зависимость от WOC/ARC);
- непермиссивной лицензии референсного узла (Open BSV License);
- недавней смены правил (Chronicle, апрель 2026).

Условия пересмотра статуса в сторону «Send supported»: аудит правил пост-Chronicle на живой цепи, зафиксированное решение по деривациям, наличие ≥2 независимых публичных путей broadcast/API, правовая оценка DAR/Network Access Rules.

## 11. Источники

1. SV Node — chainparams.cpp (magic, порты, base58-префиксы, genesis-ассерты, seeds): https://raw.githubusercontent.com/bitcoin-sv/bitcoin-sv/master/src/chainparams.cpp
2. SV Node — chainparamsbase.cpp (RPC-порты): https://raw.githubusercontent.com/bitcoin-sv/bitcoin-sv/master/src/chainparamsbase.cpp
3. SV Node — sighashtype.h (флаги SIGHASH): https://raw.githubusercontent.com/bitcoin-sv/bitcoin-sv/master/src/script/sighashtype.h
4. SV Node — interpreter.cpp (выбор дайджеста ~стр. 2112–2124; Chronicle-эра ~стр. 36–49, 296–303): https://raw.githubusercontent.com/bitcoin-sv/bitcoin-sv/master/src/script/interpreter.cpp
5. SV Node — consensus.h (COINBASE_MATURITY; предыдущая проверка): https://github.com/bitcoin-sv/bitcoin-sv/blob/master/src/consensus/consensus.h
6. BSV Hub — Sighash Flags: https://hub.bsvblockchain.org/bsv-skills-center/important-concepts/details/sighash-flags
7. BSV Wiki — SIGHASH flags: https://wiki.bitcoinsv.io/index.php/SIGHASH_flags
8. bsv-rs (Rust): https://docs.rs/bsv-rs/latest/bsv_rs/primitives/bsv/sighash/index.html и https://crates.io/api/v1/crates/bsv-rs (11.11.2026)
9. Whatsonchain API (живые запросы 11.11.2026): https://api.whatsonchain.com/v1/bsv/main/chain/info ; https://api.whatsonchain.com/v1/bsv/main/block/height/975048 ; https://api.whatsonchain.com/v1/bsv/main/tx/2271cd59b1e662860ca07345dd405bff7cc1dbd0c6e0fd5cb562c3e0d4ca9057
10. Документация WOC API: https://docs.whatsonchain.com
11. crates.io API (bsv): https://crates.io/api/v1/crates/bsv
12. pub.dev (Dart bsv): https://pub.dev/packages/bsv ; bitcoin_base: https://pub.dev/packages/bitcoin_base
13. SLIP-0044 (coin type 236): https://github.com/satoshilabs/slips/blob/master/slip-0044.md
14. BIP-0044: https://github.com/bitcoin/bips/blob/master/bip-0044.mediawiki
15. Bitcoin Core — chainparams.cpp (общий genesis mainnet/testnet3): https://raw.githubusercontent.com/bitcoin/bitcoin/master/src/chainparams.cpp
16. Пункты, проверенные на предыдущих этапах этого исследования без сохранённого URL (Teranode v0.16.1-beta-5; STN reset 02.2024; Edge delisting 07.2026; Chronicle h 943 816; удаление P2SH h 620538; ElectrumSVP 0.2.0) — **«НЕ ПОДТВЕРЖДЕНО повторно»**, требуют повторной сверки перед публичной публикацией паспорта.
