# Технический паспорт: Bitcoin (BTC)

> Паспорт монеты для некастодиального мультичейн-кошелька VEYRO (Rust-ядро + Flutter UI, без собственных backend-серверов).
> Составлено: 11.11.2026. Критические параметры подтверждены исходным кодом узла + независимыми источниками (минимум 2 источника).
> Всё, что не удалось подтвердить, помечено **«НЕ ПОДТВЕРЖДЕНО»**.

## 1. Идентичность и официальные источники

| Параметр | Значение |
|---|---|
| Название | Bitcoin |
| Тикер | BTC (иногда XBT в сервисах) |
| Тип сети | L1, Proof-of-Work, SHA-256d (двойной SHA-256) |
| Десятичность | 8 знаков; 1 BTC = 100 000 000 сатоши |
| Первый блок | 03.01.2009 (nTime genesis = 1231006505) |
| Состояние сети | Высота ~975 448 блоков (11.11.2026, по данным мониторинга публичных Electrum-серверов) |

Официальные источники:
- Референсная реализация: **Bitcoin Core 32.1** (27.10.2026) — https://github.com/bitcoin/bitcoin (MIT), сайт https://bitcoincore.org
- Спецификации: BIP — https://github.com/bitcoin/bips
- SLIP-44 (регистр coin types): https://github.com/satoshilabs/slips/blob/master/slip-0044.md
- Официальный список публичных Electrum-серверов: раздел «Electrum Servers» на https://electrum.org → https://1209k.com/bitcoin-eye/ele.php

## 2. Идентификация сети

### Mainnet
| Параметр | Значение | Источник |
|---|---|---|
| Genesis hash | `000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f` | assert в chainparams.cpp Bitcoin Core + blockstream.info (2 источника) |
| Merkle root genesis | `4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b` | там же |
| Параметры genesis | nTime 1231006505, nBits 0x1d00ffff, nNonce 2083236893, награда 50 BTC | там же |
| Network magic | **0xF9BEB4D9** | chainparams.cpp (pchMessageStart) |
| Порт P2P | 8333 | там же |
| Порт RPC | 8332 | chainparamsbase.cpp |
| Base58-префиксы | P2PKH 0x00, P2SH 0x05, WIF 0x80 (128) | chainparams.cpp |
| BIP32-версии | xpub 0x0488B21E / xprv 0x0488ADE4 | там же |
| Bech32 HRP | **`bc`** (bech32 для v0–16, bech32m для P2TR) | chainparams.cpp + BIP173/350 |
| Оценка объёма цепи | ~897 ГБ (константы ASSUMED_* Core; меняются со временем) | исходники Core (предыдущая проверка) |

### Тестовые сети
| Сеть | Magic | P2P | RPC | Genesis / особенности |
|---|---|---|---|---|
| testnet3 | 0x0B110907 | 18333 | 18332 | `000000000933ea01ad0ee984209779baaec3ced90fa3f408719526f8d77f4943` (nTime 1296688602, nNonce 414098458; assert код + blockstream.info testnet API); HRP `tb`; base58 111/196/239; ~245 ГБ (assumed) |
| testnet4 | 0x1C163F28 | 48333 | 48332 | `00000000da84f2bafbbc53dee25a72ae507ff4914b867c565be350b0da8bf043`, merkle `7aa0a7ae1e223414cb807e40cd57e667b718e42aaf9306db9102fe28912b7b4e` (nTime 1598918400, nNonce 52613770, nBits 0x1e0377ae; assert в коде + mempool.space/blockstream ранее); ~31 ГБ |
| signet | 0x0A03CF40 | 38333 | 38332 | `00000008819873e925422c1ff0f99f7cc9bbb232af63a077a480a3633bee1ef6`; challenge = скрипт 2-of-2 multisig (`512103ad…452ae`); magic выведен из SIGNET_DEFAULT_CHALLENGE (SHA256d с CompactSize-префиксом) и подтверждён 3 независимыми источниками (Bitcoin Wiki, docs.rs rust-bitcoin, PR bitcoin/bitcoin #35610) |
| regtest | 0xFABFB5DA | 18444 | 18443 | `0f9188f13cb7b2c71f2a335e3a4fc328bf5beb436012afca590b1a11466e2206` (nTime 1296688602, nNonce 2, nBits 0x207fffff) |

## 3. Криптография и ключи

- Кривая: **secp256k1**. Подписи: **ECDSA** (для P2PKH/P2SH/P2WPKH/P2WSH) и **Schnorr (BIP340)** для key-path P2TR.
- Публичный ключ: сжатый (33 байта) — стандарт индустрии.
- Форматы адресов (mainnet, все подтверждены live или вектором BIP):
  - P2PKH `1...` (префикс 0x00) — примеры: `1CK6KHY6MHgYvmRQ4PAafKYDrg1ejbH1cE` (live, mempool.space, 11.11.2026); genesis-адрес `1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa` (live: 67 486 транзакций, не потрачен)
  - P2SH `3...` (префикс 0x05) — пример: `324H9uyTV9bPgAVgmdJNxPKKKZmowk5CYq` (live, mempool.space)
  - P2WPKH (bech32, BIP173) — примеры: `bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4w` (тест-вектор BIP173), `bc1qe2rccsashpwyhmss3tk4kj0agce2ejywfe9e2f` (live, mempool.space)
  - P2WSH (bech32, BIP173) — пример: `bc1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qccfmv3` (тест-вектор BIP173)
  - P2TR (bech32m, BIP350/341) — пример: `bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr` (тест-вектор BIP86)
- WIF: префикс 0x80 (mainnet; сжатые ключи → K/L...), 0xEF (testnet).
- BIP32: xpub 0x0488B21E / xprv 0x0488ADE4 (mainnet); 0x043587CF / 0x04358394 (testnet).
- **Деривация (SLIP-44 coin type 0):**
  - BIP44 (legacy P2PKH): `m/44'/0'/0'/0/0`
  - BIP49 (P2SH-P2WPKH): `m/49'/0'/0'/0/0`
  - BIP84 (native SegWit P2WPKH): `m/84'/0'/0'/0/0` — подтверждено текстом BIP84 («Account 0, first receiving address = m/84'/0'/0'/0/0»)
  - BIP86 (Taproot P2TR): `m/86'/0'/0'/0/0` — тест-вектор BIP86
- Мнемоника: **BIP39** — фактический межкошелёчный стандарт. Кросс-восстановление: BIP39-фраза + путь BIP44/49/84/86 восстанавливается в большинстве кошельков (Ledger, Trezor, Trust, BlueWallet и т.д.); ⚠️ Electrum использует собственный формат seed (не BIP39) — восстановление Electrum-фраз в VEYRO — опциональная функция (детали формата в этом проходе не проверялись — «НЕ ПОДТВЕРЖДЕНО»).

## 4. Транзакции

- Структура: nVersion, vin[] (prevout, scriptSig, nSequence), vout[] (value, scriptPubKey), nLockTime; witness-структуры для SegWit (BIP141); Taproot (BIP341/342).
- Модель баланса: **UTXO**.
- Комиссии: **сат/vB**. Весовая модель (BIP141, подтверждено текстом): «Transaction weight = Base transaction size * 3 + Total transaction size», «Virtual transaction size = Transaction weight / 4 (rounded up)», лимит веса блока 4 000 000. Свидетель-данные дисконтируются 1:4.
- Sighash: SIGHASH_ALL/NONE/SINGLE (+ANYONECANPAY) + BIP143-дайджест для SegWit; Taproot — BIP341-дайджест (SIGHASH_DEFAULT без флага для key path).
- RBF: opt-in через nSequence (BIP125) — рекомендовано для UX отзыва/замены транзакций; CPFP — стандартная практика мемпула.
- Coinbase maturity: **100 блоков** (consensus.h Bitcoin Core — проверено).
- Halving: интервал 210 000; текущая награда **3.125 BTC** (4-я эпоха с 04.2024, блок 840 000); следующий ~2028 (блок 1 050 000).
- Dust limit: 546 сат (policy узлов; не consensus — «policy, общеизвестная практика Core»).
- Спец-поля: nSequence (BIP68 относительные блокировки), nLockTime; OP_RETURN для данных.

## 5. Сетевой доступ (без серверов VEYRO)

| Способ | Статус | Детали |
|---|---|---|
| Собственный узел Bitcoin Core + RPC | ✅ | JSON-RPC (`bitcoin-cli`), порты 8332 / 18332 / 48332 / 38332 / 18443; P2P 8333 / 18333 / 48333 / 38333 / 18444; диск ~897 ГБ (assumed) |
| **Electrum-протокол (лёгкий путь)** | ✅ | Живые публичные серверы (11.11.2026, мониторинг 1209k.com/bitcoin-eye/ele.php — официальная ссылка electrum.org): `electrum.qtornado.com:50002` (ssl, Fulcrum 2.1.4), `vps.hsmiths.com:50002` (ssl, Fulcrum 2.1.4), `blockitall.us:50001/50002`, `zutaten.mooo.com:50001/50002`, `zztop.twilightparadox.com:50001/50002`, `fulcrum.bullbitcoin.com:50002` (ElectrumX 1.16.0 / Fulcrum 2.1.4, протокол 1.4, синхронизированы до высоты 975 448). Клиенты: Electrum 4.8.4 (MIT); **rust electrum-client 0.25.2** |
| Публичные эксплореры/API | ✅ (оговорки) | mempool.space, blockstream.info (Esplora API) — проверены живыми запросами адресов. ⚠️ Приватность: провайдер связывает IP с адресами |
| Собственный Electrum-сервер | ✅ (для приватности) | electrs / ElectrumX / Fulcrum поверх узла пользователя |

⚠️ Приватность публичных серверов: они видят IP и все запрашиваемые адреса/скрипты. Для VEYRO:Tor-поддержка + возможность указать пользовательский Electrum-сервер.

**Вывод:** полный цикл (баланс/история/отправка/broadcast) реализуем **без серверов VEYRO** тремя путями: (a) публичные Electrum-серверы (избыточная инфраструктура), (b) собственный Core-узел (+RPC), (c) собственный Electrum-сервер поверх узла пользователя.

## 6. SDK и библиотеки

**Официальные:** Bitcoin Core (узел + `bitcoin-cli`); libsecp256k1 (github.com/bitcoin-core/secp256k1 — эталонная C-библиотека подписи secp256k1). Кошелькового «официального SDK» нет — экосистема библиотек открыта.

**Rust (все проверены через crates.io API 11.11.2026):**
| Крейт | Версия | Обновление | Загрузки/90 дней | Лицензия |
|---|---|---|---|---|
| bitcoin (rust-bitcoin) | 0.32.102 stable / 0.33.0-beta | 22.07.2026 | ~5 560 000 | CC0-1.0 |
| secp256k1 (rust-secp256k1) | 0.33.1 | 29.08.2026 | ~26 270 000 | CC0-1.0 |
| miniscript | 13.2.0 | 27.10.2026 | ~767 000 | CC0-1.0 |
| bip39 | 3.0.0 | 17.09.2026 | ~4 890 000 | CC0-1.0 |
| bdk-wallet | 3.2.0 | 20.09.2026 | ~340 000 | MIT OR Apache-2.0 |
| electrum-client | 0.25.2 | 22.10.2026 | ~507 000 | MIT |

Все ключевые крейты активны (обновления 2026 г.), формальные аудиты — «НЕ ПОДТВЕРЖДЕНО» в этом проходе (использовать с собственным тест-покрытием).

**Flutter/Dart:**
- **bitcoin_base 7.3.0** (16.07.2026, BSD-3-Clause) — поддержка BTC: P2PK/P2PKH/P2SH/P2WPKH/P2WSH/**P2TR** + интеграция Electrum API.
- bitcoindart 2.2.1 (23.12.2020) — устаревший, не использовать.

## 7. Лицензии зависимостей vs MIT OR Apache-2.0

| Зависимость | Лицензия | Совместимость с VEYRO |
|---|---|---|
| rust-bitcoin, rust-secp256k1, miniscript, bip39 | **CC0-1.0** (public domain dedication) | ✅ — свободнее MIT; атрибуция не требуется |
| bdk-wallet | MIT OR Apache-2.0 | ✅ |
| electrum-client | MIT | ✅ |
| bitcoin_base (Dart) | BSD-3-Clause | ✅ (требуется атрибуция копирайта) |
| Bitcoin Core (узел) | MIT | ✅ |

Конфликтов нет. Для проприетарного продукта VEYRO допустимы все перечисленные.

## 8. Чек-лист совместимости VEYRO

| Операция | Статус | Что требуется |
|---|---|---|
| Создание кошелька (BIP39+BIP32) | ✅ | bip39 + secp256k1 (Rust); bitcoin_base (Dart) |
| Импорт/restore seed | ✅ | BIP39 + стандартные пути m/44'/49'/84'/86'; выбор типа адреса в UI |
| Импорт WIF | ✅ | префикс 0x80 |
| Получение (receive, QR) | ✅ | рекомендованный дефолт: bech32 P2WPKH (bc1q...) |
| Баланс | ✅ | Electrum (scripthash subscribe) / свой узел |
| История | ✅ | Electrum blockchain.scripthash.get_history |
| Сборка + подпись | ✅ | rust-bitcoin/bdk локально (никакие ключи не покидают устройство) |
| Broadcast | ✅ | Electrum broadcast / sendrawtransaction / API эксплорера |
| Полный цикл без серверов VEYRO | ✅ | избыточная публичная инфраструктура + опция своего сервера |

## 9. Безопасность, лимиты, блокеры

1. **Приватность публичных Electrum-серверов** — главный компромисс; решение: Tor + опция пользовательского сервера.
2. Fee/UTXO-менеджмент: оценка sat/vB, RBF, CPFP — обязательные UX-функции.
3. Сложность форматов: 4 поколения адресов (P2PKH/P2SH/SegWit/Taproot) — импорт должен корректно определять тип по префиксу пути.
4. BIP39-passphrase (25-е слово): поддержка и UX-предупреждения (потеря = потеря средств).
5. Полная нода — ~900 ГБ диск: для пользователей с собственным узлом — предупреждать; лёгкий путь Electrum не требует диска.
6. Блокеров нет.

## 10. Вердикт для матрицы совместимости

### **Full support**

Шкала: Research required → Watch-only → Receive supported → Send supported → Full support (Blocked — отдельно).

Все компоненты подтверждены: форматы адресов (5 типов, все с примерами/векторами), деривации BIP44/49/84/86, sighash (стандартные + BIP143/341), maturity 100, полный лёгкий доступ через избыточную публичную Electrum-инфраструктуру (живые серверы подтверждены), активные Rust- и Dart-библиотеки (все зависимости пермиссивные). Полный цикл не требует серверов VEYRO.

## 11. Источники

1. Bitcoin Core — chainparams.cpp (magic, порты, префиксы, genesis-ассерты): https://raw.githubusercontent.com/bitcoin/bitcoin/master/src/chainparams.cpp
2. Bitcoin Core — chainparamsbase.cpp (RPC-порты): https://raw.githubusercontent.com/bitcoin/bitcoin/master/src/chainparamsbase.cpp
3. Bitcoin Core — consensus.h (COINBASE_MATURITY=100): https://github.com/bitcoin/bitcoin/blob/master/src/consensus/consensus.h
4. Bitcoin Core — src/kernel/signet.h (SIGNET_DEFAULT_CHALLENGE): https://raw.githubusercontent.com/bitcoin/bitcoin/master/src/kernel/signet.h
5. BIP-0044, BIP-0049, BIP-0084, BIP-0086 (деривации): https://github.com/bitcoin/bips (bip-0044/0084/0086 mediawiki проверены 11.11.2026)
6. BIP-0141 (весовая модель, цитаты), BIP-0143, BIP-0173, BIP-0350: https://github.com/bitcoin/bips
7. SLIP-0044 (coin type 0): https://github.com/satoshilabs/slips/blob/master/slip-0044.md
8. Electrum — официальный список серверов (ссылка с electrum.org, раздел «Electrum Servers»): https://1209k.com/bitcoin-eye/ele.php (живые данные 11.11.2026)
9. mempool.space (live-адреса 11.11.2026): https://mempool.space ; blockstream.info API: https://blockstream.info/api
10. crates.io API (версии/лиценции/загрузки): https://crates.io/api/v1/crates/{bitcoin,secp256k1,miniscript,bip39,bdk-wallet,electrum-client}
11. pub.dev: bitcoin_base — https://pub.dev/packages/bitcoin_base (7.3.0, 16.07.2026); bitcoindart — https://pub.dev/packages/bitcoindart (2.2.1, 2020)
12. bitcoincore.org (релиз Bitcoin Core 32.1, 27.10.2026)
13. Signet magic (0x0a03cf40): вывод из SIGNET_DEFAULT_CHALLENGE + Bitcoin Wiki + docs.rs rust-bitcoin + PR bitcoin/bitcoin #35610 (проверено ранее).
