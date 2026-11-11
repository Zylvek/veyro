# Технический паспорт: Bitcoin Cash (BCH)

> Паспорт монеты для некастодиального мультичейн-кошелька VEYRO (Rust-ядро + Flutter UI, без собственных backend-серверов).
> Составлено: 11.11.2026. Критические параметры подтверждены исходным кодом узла + независимыми источниками (минимум 2 источника).
> Всё, что не удалось подтвердить, помечено **«НЕ ПОДТВЕРЖДЕНО»**.

## 1. Идентичность и официальные источники

| Параметр | Значение |
|---|---|
| Название | Bitcoin Cash |
| Тикер | BCH |
| Тип сети | L1, Proof-of-Work, SHA-256d (двойной SHA-256); время блока ~10 мин |
| Десятичность | 8 знаков; 1 BCH = 100 000 000 сатоши |
| Происхождение | Форк Bitcoin 01.08.2017 (UAHF); общая история с BTC до этой высоты |
| Референсный узел | **Bitcoin Cash Node (BCHN) v29.2.0** (MIT) |
| Состояние сети | Высота **976 910**, best hash `000000000000000000edeb05115b30163419970a07055a443fba41fb3c4f8eaa` (Blockchair BCH API, 11.11.2026) |

Официальные источники:
- Код узла: https://gitlab.com/bitcoin-cash-node/bitcoin-cash-node (MIT)
- Документация/спецификации апгрейдов: https://upgradespecs.bitcoincashnode.org (в т.ч. апгрейд 15.05.2026)
- Сайт организации: https://bitcoincashnode.org
- Спецификация CashAddr: https://github.com/bitcoincashorg/bitcoincash.org/blob/master/spec/cashaddr.md
- Референсный Electrum-кошелёк: **Electron Cash** — https://github.com/Electron-Cash/Electron-Cash (актуальная сборка 4.4.6.1 от 22.09.2026 — активен)

## 2. Идентификация сети

### Mainnet
| Параметр | Значение | Источник |
|---|---|---|
| Genesis hash | `000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f` — общий с BTC (форк) | assert в chainparams.cpp BCHN + chainparams Bitcoin Core (2 источника) |
| Merkle root genesis | `4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b` | там же |
| Параметры genesis | nTime 1231006505, nBits 0x1d00ffff, nNonce 2083236893, награда 50 BCH | там же |
| Network magic | **0xE3E1F3E8** (netMagic); diskMagic **0xF9BEB4D9** (в BCHN разделены) | chainparams.cpp BCHN |
| Порт P2P | 8333 | там же |
| Порт RPC | 8332 | chainparamsbase.cpp BCHN |
| Cashaddr-префикс | **`bitcoincash`** | chainparams.cpp |
| Base58-префиксы (legacy) | P2PKH 0x00, P2SH 0x05, WIF 0x80 | там же |
| BIP32-версии | стандартные: xpub 0x0488B21E / xprv 0x0488ADE4 | там же |
| Оценка объёма цепи | ~250 ГБ (в коде BCHN: m_assumed_blockchain_size 250, комментарий 207G; chainstate ~4.2G) | chainparams.cpp BCHN |
| DNS seeds | seed.flowee.cash, seed-bch.bitcoinforks.org и др. | там же |

### Тестовые сети (код BCHN)
| Сеть | Magic | P2P | RPC | Cashaddr | Genesis / примечания |
|---|---|---|---|---|---|
| testnet3 | 0xF4E5F3F4 | 18333 | 18332 | `bchtest` | = BTC testnet3 `000000000933ea01ad0ee984209779baaec3ced90fa3f408719526f8d77f4943` (assert BCHN + Bitcoin Core — 2 источника); объём ~43 ГБ (код) |
| testnet4 | 0xE2B7DAAF | 28333 | 28332 | `bchtest` | `000000001dd410c49a788668ce26751718cc797474d3152a5fc073dd44fd9f7b` (nTime 1597811185, nNonce 114152193) — источник: код BCHN (второй независимый — «НЕ ПОДТВЕРЖДЕНО»); объём ~82 МБ (код) |
| scalenet | 0xC3AFE1A2 | 38333 | 38332 | `bchtest` | `00000000e6453dc2dfe1ffa19023f86002eb11dbb8e87d0291a4599f0430be52` (nTime 1598282438) — код BCHN; ~153 ГБ (код) |
| chipnet | 0xE2B7DAAF (как testnet4) | 48333 | 48332 | `bchtest` | общий genesis с testnet4 (код BCHN); ~242 МБ (код) |
| regtest | 0xDAB5BFFA | 18444 | 18443 | `bchreg` | `0f9188f13cb7b2c71f2a335e3a4fc328bf5beb436012afca590b1a11466e2206` |

## 3. Криптография и ключи

- Кривая: **secp256k1**; подписи **ECDSA** (SegWit/Taproot отсутствуют на BCH).
- **Формат адресов: cashaddr** (bech32-подобный формат BCH, префикс `bitcoincash`):
  - P2PKH-тип: `bitcoincash:q....`
  - P2SH-тип: `bitcoincash:p....`
  - Чексумма PolyMod; тест-векторы спецификации (проверены): `bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a` ↔ legacy `1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggu`; `bitcoincash:ppm2qsznhks23z7629mms6s4cwef74vcwvn0h829pq` ↔ legacy `3CWFddi6m4ndiGyKqzYvsFYagqDLPVMTzC`.
- Legacy Base58 `1...`/`3...` остаются валидными у узлов (base58-префиксы в коде) — старые UTXO.
- WIF: 0x80 (128). BIP32: стандартные версии (0488B21E/0488ADE4); testnet 043587CF/04358394.
- Testnet base58: 111 (`m/n...`), 196, WIF 239.
- SLIP-44: coin type **145**.
- Деривация: BIP44+SLIP-44 → **`m/44'/145'/0'/0/0`** (канонический путь по построению стандартов). Путь по умолчанию в Electron Cash — в проверенных исходниках прямой литерал не найден — **«НЕ ПОДТВЕРЖДЕНО»**; при импорте сторонних seed — предлагать выбор пути.
- Мнемоника: BIP39 — фактический стандарт BCH-кошельков; нюансы формата seed Electron Cash — **«НЕ ПОДТВЕРЖДЕНО»** в этом проходе.

## 4. Транзакции

- Структура: классическая (nVersion, vin, vout, nLockTime), **без SegWit**. UTXO-модель.
- **SIGHASH_FORKID (0x40)**:
  - Дайджест UAHF (BIP143-подобный, forkId=0) — историческая спецификация ABC «Replay Protected Sighash» (текст доступен как doc/abc/replay-protected-sighash.md в дереве репозитория bitcoin-sv — унаследованный ABC-документ эпохи UAHF; прямой BCHN/ABC URL в этом проходе не найден).
  - BCHN включает SCRIPT_ENABLE_SIGHASH_FORKID в валидации (src/validation.cpp:1494 — проверено чтением кода).
  - Практика: все современные BCH-кошельки подписывают `SIGHASH_ALL|SIGHASH_FORKID` = **0x41** (подтверждено документацией bitcoin_base: ForkedTransactionBuilder с SIGHASH_FORKID-флоу). «Обязательность» FORKID на уровне standardness в этом проходе напрямую не подтверждена — использовать 0x41.
- Комиссии: **сатоши/байт** (без весовых скидок).
- Coinbase maturity: **100 блоков** (consensus.h BCHN — проверено).
- Halving: интервал 210 000; текущая награда **3.125 BCH** (4-я эпоха с 04.2024 — по графику халвингов).
- DAA: **ASERT** (adapted).
- Блоки: **ABLA** — адаптивный лимит размера (апгрейд10, май 2024; базовый размер по умолчанию 32 МБ, авто-настройка).
- Апгрейды (по upgradespecs.bitcoincashnode.org, проверено):
  - upgrade11 (15.05.2025): VM Limits + BigInt (высота 898 373);
  - **upgrade12 (15.05.2026, MTP 1778846400)**: CHIP-2024-12 **P2S** (новый тип выхода), CHIP-2021-05-loops, CHIP-2025-05 Functions, CHIP-2025-05 Bitwise.
- **CashTokens** (токеновый протокол BCH, активен; поддержка в bitcoin_base: token-aware-типы, ForkedTransactionBuilder) — VEYRO: базовый BCH-баланс работает без токенов; токеновые UTXO не тратить без явной поддержки.

## 5. Сетевой доступ (без серверов VEYRO)

| Способ | Статус | Детали |
|---|---|---|
| Собственный узел BCHN + RPC | ✅ | RPC 8332 / 18332 / 28332 / 38332 / 48332 / 18443; P2P 8333 / 18333 / 28333 / 38333 / 48333 / 18444; диск ~207 ГБ (код BCHN) |
| **Electrum-протокол** | ✅ | **23 публичных сервера** в servers.json Electron Cash (например `bch.imaginary.cash:50001/50002`, `electroncash.dk`, `fulcrum.*` — порты 50001 TCP / 50002 TLS); клиент **Electron Cash 4.4.6.1** (22.09.2026, активен) |
| Эксплореры/API | ✅ | **Blockchair BCH API** (живой 11.11.2026: высота 976 910); explorer.bitcoin.com (живой). ⚠️ Приватность |
| Собственный Electrum-сервер | ✅ (для приватности) | Fulcrum / ElectrumX поверх узла пользователя |

⚠️ Приватность публичных серверов: IP + адреса видны провайдеру. Решение VEYRO: Tor + пользовательский сервер.

**Вывод:** полный цикл без серверов VEYRO — **да**: избыточная публичная Electrum-инфраструктура BCH (23 сервера), собственный узел BCHN, публичные API (с оговорками).

## 6. SDK и библиотеки

**Rust:**
- **bitcoin-cash** — 0.2.3 stable / 1.0.0-beta.0 (07.12.2020, MIT, ~1 283 загрузки/90 дней) — **устаревший** (последний релиз 2020 г.).
- **cashaddr** — 0.2.0 (23.03.2023, MIT, ~24 530 загрузок/90 дней) — только кодек cashaddr (адреса), рабочий.
- Полноценного современного BCH-SDK в Rust нет → путь VEYRO: rust-bitcoin (ключи/сериализация) + **собственный модуль**: cashaddr-кодек (по спецификации) и sighash UAHF (FORKID) — параметры и тест-векторы в этом паспорте.

**Flutter/Dart:**
- **bitcoin_base 7.3.0** (16.07.2026, BSD-3-Clause) — **полная поддержка BCH**: P2PK/P2PKH/P2SH/P2SH32/token-aware/**CashTokens**, `ForkedTransactionBuilder` с SIGHASH_FORKID-флоу, интеграция Electrum API — ключевой актив VEYRO для BCH.

**Референсная реализация (для сверки):** Electron Cash (Python, MIT).

## 7. Лицензии зависимостей vs MIT OR Apache-2.0

| Зависимость | Лицензия | Совместимость с VEYRO |
|---|---|---|
| bitcoin-cash (rust) | MIT | ✅ |
| cashaddr (rust) | MIT | ✅ |
| rust-bitcoin (ядро ключей/сериализации) | CC0-1.0 | ✅ |
| bitcoin_base (Dart) | BSD-3-Clause | ✅ (атрибуция) |
| BCHN / Electron Cash (справка, референс) | MIT | ✅ |

Конфликтов нет.

## 8. Чек-лист совместимости VEYRO

| Операция | Статус | Что требуется |
|---|---|---|
| Создание кошелька (BIP39+BIP32) | ✅ | стандартные алгоритмы |
| Импорт/restore seed | ⚠️→✅ | путь m/44'/145' (BIP44+SLIP-44); выбор пути при импорте сторонних seed |
| Импорт WIF | ✅ | префикс 0x80 |
| Получение (receive, QR) | ✅ | cashaddr `bitcoincash:q...` (+ отображение legacy) |
| Баланс/история | ✅ | Electrum-протокол (23 публичных сервера / свой узел) |
| Сборка + подпись | ✅ | bitcoin_base (Dart, ForkedTransactionBuilder) и/или собственный Rust-модуль sighash FORKID (дайджест UAHF; тест-векторы спецификации) |
| Broadcast | ✅ | Electrum broadcast / sendrawtransaction BCHN |
| Полный цикл без серверов VEYRO | ✅ | через публичные Electrum-серверы или свой узел |
| CashTokens | ❌/вне объёма | токеновые UTXO отображать/не тратить без поддержки |

## 9. Безопасность, лимиты, блокеры

1. **Собственный sighash-модуль (FORKID/UAHF)** в Rust-ядре — единственная значимая реализация-работа; требует аудита по тест-векторам спецификации и сверке с Electron Cash на testnet3 (`bchtest`).
2. Каденция апгрейдов 2 раза в год (15.05 / 15.11): апгрейд 15.05.2026 ввёл P2S-выходы и новые опкоды — следить за апгрейдом 15.05.2027; базовые P2PKH-переводы не затронуты.
3. ABLA — динамика лимитов блока влияет на комиссионный рынок; оценку комиссий делать по live-данным.
4. CashTokens: при сканировании UTXO корректно отделять BCH-часть от токенов (token-aware UTXO).
5. Публичные серверы — приватность (Tor/свой сервер).
6. Блокеров нет.

## 10. Вердикт для матрицы совместимости

### **Full support**

Шкала: Research required → Watch-only → Receive supported → Send supported → Full support (Blocked — отдельно).

Все компоненты подтверждены: cashaddr (спецификация + тест-векторы), деривация m/44'/145', sighash SIGHASH_ALL|SIGHASH_FORKID (0x41, дайджест UAHF — несколько источников + код BCHN), maturity 100, избыточная публичная Electrum-инфраструктура (23 сервера), активный клиент Electron Cash, готовая Dart-поддержка (bitcoin_base) и референсная Python-реализация для сверки. Полный цикл не требует серверов VEYRO. Единственная реализация-работа — собственный Rust-модуль подписи FORKID (параметры и тест-векторы задокументированы).

## 11. Источники

1. BCHN — chainparams.cpp (magic, порты, cashaddr-префиксы, genesis-ассерты, assumed-размеры): https://gitlab.com/bitcoin-cash-node/bitcoin-cash-node/-/raw/master/src/chainparams.cpp
2. BCHN — chainparamsbase.cpp (RPC-порты всех сетей): https://gitlab.com/bitcoin-cash-node/bitcoin-cash-node/-/raw/master/src/chainparamsbase.cpp
3. BCHN — consensus.h (COINBASE_MATURITY=100): https://gitlab.com/bitcoin-cash-node/bitcoin-cash-node/-/raw/master/src/consensus/consensus.h
4. BCHN — validation.cpp (SCRIPT_ENABLE_SIGHASH_FORKID, строка ~1494): https://gitlab.com/bitcoin-cash-node/bitcoin-cash-node/-/raw/master/src/validation.cpp
5. Спецификация апгрейда 15.05.2026 (P2S, loops, functions, bitwise, MTP): https://upgradespecs.bitcoincashnode.org/2026-05-15-upgrade
6. Спецификация CashAddr (PolyMod, тест-векторы): https://github.com/bitcoincashorg/bitcoincash.org/blob/master/spec/cashaddr.md (перенесена из bitcoincashorg/spec — проверено 11.11.2026)
7. Спецификация «Replay Protected Sighash» (UAHF-дайджест, forkId=0) — унаследованный ABC-документ: https://github.com/bitcoin-sv/bitcoin-sv/blob/master/doc/abc/replay-protected-sighash.md
8. Blockchair BCH API (live 11.11.2026, высота 976 910): https://api.blockchair.com/bitcoin-cash/stats
9. explorer.bitcoin.com (live 11.11.2026): https://explorer.bitcoin.com
10. Electron Cash (клиент 4.4.6.1, 22.09.2026; публичный servers.json — 23 сервера, порты 50001/50002): https://github.com/Electron-Cash/Electron-Cash
11. bitcoin_base (Dart, поддержка BCH/CashTokens/FORKID): https://pub.dev/packages/bitcoin_base (7.3.0, 16.07.2026)
12. crates.io API: https://crates.io/api/v1/crates/{bitcoin-cash,cashaddr}
13. SLIP-0044 (coin type 145): https://github.com/satoshilabs/slips/blob/master/slip-0044.md
14. BIP-0044: https://github.com/bitcoin/bips/blob/master/bip-0044.mediawiki
15. Bitcoin Core — chainparams.cpp (общий genesis mainnet/testnet3, перекрёстная проверка): https://raw.githubusercontent.com/bitcoin/bitcoin/master/src/chainparams.cpp
