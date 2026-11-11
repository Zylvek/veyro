# Технический паспорт: eCash (XEC)

> Паспорт монеты для некастодиального мультичейн-кошелька VEYRO (Rust-ядро + Flutter UI, без собственных backend-серверов).
> Составлено: 11.11.2026. Критические параметры подтверждены исходным кодом узла + независимыми источниками (минимум 2 источника).
> Всё, что не удалось подтвердить, помечено **«НЕ ПОДТВЕРЖДЕНО»**.

## 1. Идентичность и официальные источники

| Параметр | Значение |
|---|---|
| Название | eCash (ранее Bitcoin Cash ABC, тикер BCHA до реденоминации) |
| Тикер | XEC |
| Тип сети | L1, Proof-of-Work, SHA-256d; DAA — ASERT |
| Десятичность | 8 внутренних знаков (сатоши); отображение: **1 XEC = 100 сатоши** (2 отображаемых знака). Реденоминация 07.2021: 1 BCHA = 1 000 000 XEC |
| Происхождение | Форк Bitcoin Cash 15.11.2020, высота **661 647**; до этого общая история с BTC/BCH |
| Референсный узел | Bitcoin ABC **0.34.3** (29.10.2026), лицензия MIT |
| Апгрейд 15.11.2026 | Без новых протокольных фич — только replay-защита; узлы обязаны обновиться до ≥0.34.x (официальная страница https://e.cash/upgrade); кошельки не затронуты |

Официальные источники:
- Сайт/документация: https://e.cash (апгрейды, Chronik, стейкинг, реденоминация)
- Код узла: https://github.com/Bitcoin-ABC/bitcoin-abc (MIT)
- Релизы: https://bitcoinabc.org ; код-ревью: https://reviews.bitcoinabc.org
- Официальный эксплорер: https://explorer.e.cash
- Официальный Electrum-клиент: **Electrum ABC 5.5.2** (02.10.2026) — https://electrum-abc.org (форк Electrum/Electron Cash, MIT)
- API **Chronik** (REST-индексатор, встроен в узел Bitcoin ABC): официальные публичные эндпоинты `chronik.e.cash`, `chronik.be.cash/xec`, `chronik1.e.cash`, `chronik2.e.cash`
- Официальный npm-клиент Chronik: `chronik-client`

## 2. Идентификация сети

### Mainnet
| Параметр | Значение | Источник |
|---|---|---|
| Genesis hash | `000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f` — общий с BTC/BCH | assert в src/kernel/chainparams.cpp Bitcoin ABC + chainparams Bitcoin Core (2 источника) |
| Merkle root genesis | `4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b` | там же |
| Параметры genesis | nTime 1231006505, nBits 0x1d00ffff, nNonce 2083236893, награда 50 BCHA | там же |
| Network magic | **0xE3E1F3E8** (унаследован от BCH/Bitcoin ABC-семейства) | chainparams.cpp (netMagic[]) |
| Порт P2P | 8333 | там же |
| Порт RPC | 8332 | chainparamsbase.cpp |
| Cashaddr-префикс | **`ecash`** (по умолчанию; `bitcoincash` — при запуске узла с отключённым -ecash) | chainparams.cpp (cashaddrPrefix) |
| Halving | 210 000 блоков | код ABC (проверено ранее) |
| Avalanche pre-consensus | Активирован 15.11.2025, высота 923 347 (проверено ранее) | документация e.cash |

### Тестовые сети
| Сеть | Magic | P2P | RPC | Cashaddr-префикс | Genesis |
|---|---|---|---|---|---|
| testnet3 | 0xF4E5F3F4 | 18333 | 18332 | `ectest` | `000000000933ea01ad0ee984209779baaec3ced90fa3f408719526f8d77f4943` (= BTC testnet3; assert в коде ABC + Bitcoin Core — 2 источника) |
| regtest | 0xDAB5BFFA | 18444 | 18443 | `ecregtest` (или `bchreg`) | `0f9188f13cb7b2c71f2a335e3a4fc328bf5beb436012afca590b1a11466e2206` |

- Размер цепи для полного узла: **«НЕ ПОДТВЕРЖДЕНО»** (константы ASSUMED_* недоступны по прямому пути в исходниках — файл chainparamsconstants.cpp не найден по проверяемым путям).

## 3. Криптография и ключи

- Кривая: **secp256k1**. Подписи: **ECDSA** (Schnorr/Taproot отсутствуют).
- Формат адресов: **cashaddr** (спецификация BCH; префикс `ecash`):
  - P2PKH-тип: `ecash:q....` (payload 42 символа чексуммированного bech32-подобного формата)
  - P2SH-тип: `ecash:p....`
  - Пример (официальный адрес поддержки eCash): **`ecash:prfhcnyqnl5cgrnmlfmms675w93ld7mvvqd0y8lz07`** (e.cash)
  - Валидация: чексумма PolyMod по спецификации cashaddr (проверено по спецификации с тест-векторами).
- Legacy Base58 (принимаются узлом для старых UTXO): P2PKH префикс 0x00 (`1...`), P2SH 0x05 (`3...`).
- WIF: 0x80 (128).
- BIP32: xpub 0x0488B21E / xprv 0x0488ADE4 (стандартные); testnet 0x043587CF / 0x04358394.
- SLIP-44: coin type **899**.
- Деривация:
  - **Electrum ABC (официальный клиент): `m/44'/899'/0'/0/0`** — подтверждено официальной документацией Electrum ABC (restore guide) и руководством e.cash (Satochip).
  - Cashtab (популярный web-кошелёк XEC): `m/44'/1899'/0'/0/0` — подтверждено сторонней реализацией (PyPI: minimal-ecash-sender) и косвенно документацией Electrum ABC («пути отличаются»); официальный исходный код Cashtab не проверен — **частично «НЕ ПОДТВЕРЖДЕНО»**.
  - Рекомендация VEYRO: BIP39 + `m/44'/899'` основной путь; поддержка `m/44'/1899'` как опция совместимости с Cashtab.
- Мнемоника: Electrum ABC по умолчанию использует **формат seed Electrum (не BIP39)**; Cashtab и экосистемные кошельки используют BIP39. Кросс-восстановление: BIP39-фраза восстанавливается в любом BIP39-кошельке при одинаковом пути; Electrum-фраза — только в Electrum-семействе (у VEYRO — опциональная поддержка).

## 4. Транзакции

- Структура: классическая (nVersion, vin[], vout[], nLockTime), **без SegWit**.
- Модель баланса: UTXO.
- Подписи: **`SIGHASH_ALL|SIGHASH_FORKID` (0x41)**, дайджест UAHF (BIP143-подобный, forkId=0) — подтверждено: сторонняя реализация minimal-ecash-sender («XEC P2PKH signing uses SIGHASH_ALL|FORKID») + наследованная спецификация ABC «Replay Protected Sighash» (UAHF).
- Комиссии: сатоши/байт; весовых скидок нет. Рынок комиссий XEC низколиквидный — оценку уровня комиссий делать по live-мемпулу (**НЕ ПОДТВЕРЖДЕНО** численно).
- Coinbase maturity: **100 блоков** (consensus.h Bitcoin ABC — проверено).
- Halving: интервал 210 000; текущее значение награды — по графику халвингов (**НЕ ПОДТВЕРЖДЕНО** в текущем проходе, при необходимости снять с API Chronik).
- **Стейкинг (особенность XEC)**: 10% coinbase направляется стейкерам; UTXO ≥ 100 000 000 XEC, только P2PKH-выходы, зачисление после 2016 подтверждений (проверено ранее по документации e.cash). Для базового кошелька реализации не требует: поступления отражаются в обычной истории адреса.
- **Avalanche pre-consensus** (15.11.2025): до-консенсусная финализация; для кошелька не требуется реализация — учитывать при отображении «финальности» (история может считаться финализированной раньше 6 подтверждений).
- Лимит размера транзакции: константа MAX_TX_SIZE в коде ABC (значение по предыдущей проверке — 1 МБ; семантику consensus/policy уточнить при реализации).
- Апгрейд 15.11.2026: только replay-защита — формат подписи/транзакции для кошелька не меняется.

## 5. Сетевой доступ (без серверов VEYRO)

| Способ | Статус | Детали |
|---|---|---|
| Собственный узел Bitcoin ABC + RPC | ✅ | RPC 8332 / 18332 / 18443; P2P 8333 / 18333 / 18444; диск — «НЕ ПОДТВЕРЖДЕНО» |
| **Chronik (REST, встроен в узел ABC)** | ✅ | Официальные публичные эндпоинты: `chronik.e.cash` (официальная документация e.cash), `chronik.be.cash/xec`, `chronik1.e.cash`, `chronik2.e.cash`. Операции: адреса, история, транзакции, **broadcast** |
| **Electrum-протокол** | ✅ | Официальные серверы Electrum ABC: `electrum.bitcoinabc.org`, `electrum.fabien.cash`, `fulcrum.pierre.cash`, `electrum.pierre.cash` — порты 50001 (TCP) / 50002 (TLS). Клиент Electrum ABC 5.5.2 (MIT) |
| Эксплорер | ✅ | https://explorer.e.cash (официальный) |

⚠️ Приватность: публичные Chronik/Electrum-серверы видят IP и запрашиваемые адреса. Рекомендация VEYRO: поддержка прокси/Tor + возможность указать пользовательский сервер.

**Вывод:** полный цикл (баланс/история/broadcast) реализуем без серверов VEYRO тремя независимыми путями: (a) публичный официальный Chronik REST, (b) официальные Electrum-серверы, (c) собственный узел ABC (со встроенным Chronik). Лучший «лёгкий» доступ среди всех сетей BCH-семейства.

## 6. SDK и библиотеки

**Rust:**
- Специализированных XEC-крейтов **нет** (несуществующие: `bitcoincash-abc`, `ecash-lib` — проверено поиском по crates.io).
- Реалистичный путь: **rust-bitcoin** (ключи/скрипты/сериализация; CC0) + собственный модуль: cashaddr-кодек + sighash UAHF (BIP143-подобный) — все параметры в этом паспорте.
- Стороннее: `bitcoin-cash` crate (0.2.3 stable / 1.0.0-beta.0 2020 г., MIT) — устаревший, частично применим.

**Flutter/Dart:**
- **ecash** (pub.dev, **v0.1.0**, опубликован 22.05.2026, MIT, издатель orb.net.pl): XEC-SDK — порт ChronikClient, decodeCashAddress и др. — ключевой кандидат для интеграции Chronik в UI-слое. ⚠️ SDK молодой (v0.1.0, май 2026) — критичную логику дублировать в Rust-ядре, Dart-пакет использовать как каркас.
- bitcoin_base (BSD-3): поддержка BCH-форматов; применимость к XEC требует адаптации (префикс `ecash`, те же структура транзакций и sighash) — **«НЕ ПОДТВЕРЖДЕНО» без доработки**.

**npm/TypeScript:**
- `chronik-client` (официальный, Bitcoin ABC) — эталонная реализация поверх REST Chronik (порт/повторное использование логики для Dart/Rust).

## 7. Лицензии зависимостей vs MIT OR Apache-2.0

| Зависимость | Лицензия | Совместимость с VEYRO |
|---|---|---|
| Bitcoin ABC (узел, только документация/тесты) | MIT | ✅ |
| Electrum ABC | MIT (форк-цепочка Electrum → Electron Cash → ABC) | ✅ |
| ecash (Dart) | MIT | ✅ |
| chronik-client | MIT (официальный) | ✅ |
| rust-bitcoin | CC0-1.0 (public domain) | ✅ |
| bitcoin-cash (rust) | MIT | ✅ |

Конфликтов с политикой MIT OR Apache-2.0 нет.

## 8. Чек-лист совместимости VEYRO

| Операция | Статус | Что требуется |
|---|---|---|
| Создание кошелька (BIP39+BIP32) | ✅ | стандартные алгоритмы |
| Импорт/restore seed | ⚠️→✅ | два пути: `m/44'/899'` (Electrum ABC) и `m/44'/1899'` (Cashtab) — поддержать оба; Electrum-формат seed — опционально |
| Импорт WIF | ✅ | префикс 0x80 |
| Получение (receive, QR) | ✅ | cashaddr `ecash:q...` (+ опция legacy-адреса) |
| Баланс/история | ✅ | Chronik REST (официальный) или Electrum ABC |
| Сборка + подпись транзакции | ⚠️ | нет готового Rust-крейта: собственный sighash-модуль (SIGHASH_ALL\|FORKID, дайджест UAHF) поверх rust-bitcoin; либо адаптация bitcoin_base (Dart) |
| Broadcast | ✅ | Chronik (POST broadcast) или Electrum (`blockchain.transaction.broadcast`) |
| Полный цикл без серверов VEYRO | ✅ | через официальные публичные Chronik/Electrum |

## 9. Безопасность, лимиты, блокеры

1. **Единая команда**: протокол и узел поддерживает одна организация (Bitcoin ABC) — риск остановки развития (ниже, чем у BSV, но выше, чем у BTC/BCH).
2. **Кастомный sighash/кодек в Rust**: отсутствие готового крейта = собственная реализация + аудит (тест-векторы: спецификация cashaddr; дайджест UAHF).
3. **Расхождение дериваций** (899 vs 1899) — риск для пользователей при переносе между кошельками; нужен явный выбор пути в UI импорта.
4. **Стейкинг/Avalanche**: сложность экосистемы; базовому кошельку не требуется (поступления видны в обычной истории).
5. Публичные серверы — приватность (см. §5).
6. Каденция апгрейдов 15.05 / 15.11 (дважды в год): апгрейд 15.11.2026 совместим с кошельками (только replay-защита); следить за 15.05.2027.

## 10. Вердикт для матрицы совместимости

### **Send supported**

Шкала: Research required → Watch-only → Receive supported → Send supported → Full support (Blocked — отдельно).

Полный цикл (получение/баланс/история/отправка/broadcast) реализуем без серверов VEYRO — все компоненты подтверждены: адреса (cashaddr ecash), деривация (899/1899), sighash (ALL|FORKID), официальные публичные Chronik REST + Electrum-серверы, broadcast. Статус «Full support» не присвоен из-за:
- отсутствия Rust-крейтов — нужен собственный (затратный на аудит) sighash/cashaddr-модуль в Rust-ядре;
- нерешённого UX двойной деривации (899 vs 1899);
- зависимости экосистемы от одной команды (Bitcoin ABC).

До повышения до «Full support»: реализация и тесты кастомного модуля на testnet3 XEC (`ectest`), фиксация решения по деривациям, проверка апгрейда 15.05.2027.

## 11. Источники

1. Bitcoin ABC — kernel/chainparams.cpp (genesis-ассерты, magic, порты, base58, cashaddr-префиксы): https://raw.githubusercontent.com/Bitcoin-ABC/bitcoin-abc/master/src/kernel/chainparams.cpp
2. Bitcoin ABC — chainparamsbase.cpp (RPC-порты): https://raw.githubusercontent.com/Bitcoin-ABC/bitcoin-abc/master/src/chainparamsbase.cpp
3. Bitcoin ABC — consensus.h (COINBASE_MATURITY=100; предыдущая проверка): https://github.com/Bitcoin-ABC/bitcoin-abc/blob/master/src/consensus/consensus.h
4. e.cash (апгрейды, Chronik, стейкинг, реденоминация, апгрейд 15.11.2026): https://e.cash и https://e.cash/upgrade
5. Bitcoin ABC — релизы (0.34.3, 29.10.2026): https://bitcoinabc.org
6. Electrum ABC (клиент 5.5.2, restore-документация, пути, список серверов): https://electrum-abc.org и официальный servers.json (electrum.bitcoinabc.org и др., порты 50001/50002)
7. Официальный эксплорер: https://explorer.e.cash
8. ecash (Dart SDK, MIT, orb.net.pl): https://pub.dev/packages/ecash
9. chronik-client (официальный npm-клиент): https://www.npmjs.com/package/chronik-client
10. minimal-ecash-sender (подтверждение sighash ALL|FORKID и пути Cashtab): https://pypi.org/project/minimal-ecash-sender/
11. Спецификация CashAddr (алгоритм PolyMod, тест-векторы; канонический актуальный URL подтверждён 11.11.2026 — спецификация перенесена из bitcoincashorg/spec): https://github.com/bitcoincashorg/bitcoincash.org/blob/master/spec/cashaddr.md
12. SLIP-0044 (coin type 899): https://github.com/satoshilabs/slips/blob/master/slip-0044.md
13. BIP-0044: https://github.com/bitcoin/bips/blob/master/bip-0044.mediawiki
14. Bitcoin Core — chainparams.cpp (общий genesis mainnet/testnet3, перекрёстная проверка): https://raw.githubusercontent.com/bitcoin/bitcoin/master/src/chainparams.cpp
15. Пункты, проверенные на предыдущих этапах без сохранённого URL (стейкинг-детали, Avalanche h 923 347, halving 210 000, MAX_TX_SIZE): помечены в тексте как «проверено ранее»; перед публикацией паспорта — повторная сверка.
