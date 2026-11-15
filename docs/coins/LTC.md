# Технический паспорт: Litecoin (LTC)

> Паспорт монеты для некастодиального мультичейн-кошелька VEYRO (Rust-ядро + Flutter UI, без собственных backend-серверов).
> Составлено: 11.11.2026. Критические параметры подтверждены исходным кодом узла + независимыми источниками (минимум 2 источника).
> Всё, что не удалось подтвердить, помечено **«НЕ ПОДТВЕРЖДЕНО»**.

## 1. Идентичность и официальные источники

| Параметр | Значение |
|---|---|
| Название | Litecoin |
| Тикер | LTC |
| Тип сети | L1, Proof-of-Work, **Scrypt** (memory-hard); время блока ~2,5 мин |
| Десятичность | 8 знаков; 1 LTC = 100 000 000 литоши |
| Первый блок | nTime genesis = 1317972665 (13.10.2011) |
| Референсный узел | **Litecoin Core v0.21.5.8** (12.09.2026) — форк Bitcoin Core (MIT) |
| Особенности | SegWit+CSV активны; **Taproot** развёрнут; **MWEB** (MimbleWimble Extension Blocks) — расширение конфиденциальности |

Официальные источники:
- Сайт: https://litecoin.org
- Код узла: https://github.com/litecoin-project/litecoin (MIT)
- Эксплорер: https://litecoinspace.org (проверен живым 11.11.2026)

## 2. Идентификация сети

### Mainnet
| Параметр | Значение | Источник |
|---|---|---|
| Genesis hash | `12a765e31ffd4059bada1e25190f6e98c99d9714d334efa41a195a7e7e04bfe2` | assert в chainparams.cpp (master **и** v0.21.5.8 — 2 источника) + litecoinspace.org API `/api/block-height/0` (live, вернул этот же хеш) |
| Merkle root genesis | `97ddfbbae6be97fd6cdf3e7ca13232a3afff2353e29badfab7f73011edd4ced9` | там же |
| Параметры genesis | nTime 1317972665, nNonce 2084524493, nBits 0x1e0ffff0, награда 50 LTC | там же |
| Network magic | **0xFBC0B6DB** | chainparams.cpp |
| Порт P2P | 9333 | там же |
| Порт RPC | 9332 | chainparamsbase.cpp |
| Base58-префиксы | P2PKH 48 (L...), P2SH 5 (3...) и P2SH-2 50 (M... — стандартный LTC P2SH), WIF 176 (0xB0) | chainparams.cpp |
| BIP32-версии | стандартные: xpub 0x0488B21E / xprv 0x0488ADE4 | там же |
| Bech32 HRP | **`ltc`**; MWEB HRP **`ltcmweb`** | там же |
| DNS seeds | seed-a.litecoin.loshan.co.uk, dnsseed.thrasher.io и др. | chainparams.cpp |
| Объём цепи | ~40 ГБ (оценка по предыдущим проверкам — «НЕ ПОДТВЕРЖДЕНО повторно») |

### Тестовые сети — ⚠️ важное уточнение (по коду v0.21.5.8 и master)
| Сеть | Magic | P2P | RPC | Genesis / особенности |
|---|---|---|---|---|
| testnet (единственный) | 0xFDD2C8F1 | 19335 | 19332 | `4966625a4b2851d9fdee139e56211a0d88575f59ed816ff5e6a63deb4e3e29a0` (nTime 1486949366, nNonce 293345, nBits 0x1e0ffff0; assert в master + v0.21.5.8 + GitHub issue litecoin-project/litecoin#368 — 3 источника); HRP `tltc`; MWEB HRP `tmweb`; base58 111/196/58/239 |
| regtest | 0xFABFB5DA | 19444 | 19443 | `530827f38f93b43ed12af0b3ad25a288dc02ed74d6d7857862df51fc56c416f9`; HRP `rltc` |

- В версиях Litecoin Core v0.21.5.x идентификатор сети/datadir тестнета — строка **«testnet4»** (chainparamsbase.cpp), но это **НЕ новый testnet4 с новым genesis** — сеть та же историческая (genesis 4966625a...). Сторонние утверждения о «Litecoin testnet4» вводят в заблуждение.
- Флаг **signet существует, но реального signet нет**: в `CreateChainParams` для SIGNET возвращаются параметры testnet — в коде: `return std::unique_ptr<CChainParams>(new CTestNetParams()); // TODO: Support SigNet` (v0.21.5.8).

## 3. Криптография и ключи

- Кривая: **secp256k1**; подписи ECDSA (+ Schnorr для Taproot). PoW Scrypt не влияет на кошелёчные ключи.
- Форматы адресов (mainnet):
  - P2PKH `L...` (префикс 48) — пример: `LYhttvnKawAv6RcHQ4eBkNtifuiEA99PFe` (live, litecoinspace.org, 11.11.2026)
  - P2SH `M...` (префикс 50; исторический вариант 5 → `3...`) — пример: `MHEhpP2jcSrvZQQbEHHKPw26bCqk5DaYgn` (live)
  - P2WPKH/P2WSH bech32 `ltc1...` (HRP ltc, BIP173-кодирование) — пример: `ltc1qhw6ntumfxtmz7jek9vukdh53gj40u9arcclp85` (live)
  - **MWEB `ltcmweb...`** — конфиденциальные адреса MimbleWimble (вне объёма VEYRO, см. §9)
- Testnet: `m/n...` (111), `Q...` (58), HRP `tltc`.
- WIF: 0xB0 (176) mainnet; 0xEF (239) testnet.
- BIP32: xpub 0x0488B21E / xprv 0x0488ADE4 (mainnet — стандартные); testnet 0x043587CF / 0x04358394.
- SLIP-44: coin type **2**.
- Деривация:
  - BIP44+SLIP-44: **`m/44'/2'/0'/0/0`** (канонический путь по построению стандартов).
  - Для bech32 LTC **отдельного BIP нет**: кошельки применяют BIP84-аналогию `m/84'/2'/0'/0/0` — **НЕ СТАНДАРТИЗИРОВАНО**; при импорте сторонних seed — предлагать выбор пути.
- Мнемоника: **BIP39** — фактический стандарт; Electrum-LTC (заброшенный клиент) использовал формат seed Electrum. Кросс-восстановление BIP39+пути — как у BTC.

## 4. Транзакции

- Структура: как Bitcoin (nVersion, vin, vout, nLockTime, witness для SegWit). UTXO-модель.
- Активации (по коду узла): SegWit+CSV — высота 1 201 536; BIP16 — 218 579; **Taproot** — bit 2, nStartHeight 2 161 152; **MWEB** — bit 4, nStartHeight 2 217 600; mweb_pegout_feature_activation_height 3 154 440; mweb_extradata_feature_activation_height 3 172 640; механизм «замороженных» MWEB-выходов в коде.
- Sighash: семантика Bitcoin Core (форк): SIGHASH_ALL/NONE/SINGLE/ANYONECANPAY; BIP143-дайджест для SegWit-входов.
- Комиссии: **сат/vB**, весовая модель BIP141.
- Лимиты блока (consensus.h LTC): MAX_BLOCK_SERIALIZED_SIZE 4 000 000 (без MWEB; с MWEB — + mw::MAX_BLOCK_BYTES), MAX_BLOCK_WEIGHT 4 000 000, MAX_BLOCK_SIGOPS_COST 80 000.
- Coinbase maturity: **100 блоков** (consensus.h Litecoin — проверено 11.11.2026).
- Halving: интервал **840 000** блоков; текущая эпоха — 12.5 LTC (после 2-го халвинга 08.2023 — по графику); следующий ~08.2027 (блок 2 520 000).
- MWEB-транзакции: отдельный формат (hogwat/педерсен-коммитменты), в прозрачной цепи видны только peg-in/peg-out — VEYRO не поддерживает (см. §9).

## 5. Сетевой доступ (без серверов VEYRO)

| Способ | Статус | Детали |
|---|---|---|
| Собственный узел Litecoin Core + RPC | ✅ | RPC 9332 / 19332 / 19443; P2P 9333 / 19335 / 19444; диск ~40 ГБ (оценка) |
| **Electrum-протокол** | ✅ | Публичные серверы LTC живы: протокол 1.4; порты 50002 (ssl)/50001 (tcp). ⚠️ Официальный клиент **Electrum-LTC заброшен** (4.2.2.1 от 05.06.2022; сайт предупреждает «no longer maintained… STRONGLY DISCOURAGED»; альтернативный форк — ltc-electrum.github.io). **Live-верификация VEYRO 15.11.2026** (наш rustls-клиент): рабочие — `electrum-ltc.petrkr.net:60002` (Fulcrum 2.1.1), `litecoin.stackwallet.com:20063` (Fulcrum 2.1.4), `electrum.petrkr.net:60002`; отвечают по SslStream, но не прошли через webpki — `electrum.ltc.xurious.com:50002`, `backup.electrum-ltc.org:50002` (сертификаты), `ltc.rentonisk.com`/`electrum-ltc.bysh.me` рвут свежие коннекты/сертификат old-версии. Список держится в `SERVERS_MAINNET` (chains/src/litecoin.rs) — порядок кандидатов по живости |
| Эксплорер/API | ✅ | litecoinspace.org (живой 11.11.2026 — block-height API и данные блока). ⚠️ Приватность |

⚠️ Приватность публичных серверов: IP + адреса видны провайдеру. Решение: Tor + пользовательский сервер (Fulcrum/ElectrumX поверх узла).

**Вывод:** полный цикл без серверов VEYRO — **да**: живые публичные Electrum-серверы LTC, собственный узел, либо собственный Electrum-сервер. Нюанс: клиентская экосистема Electrum-LTC деградирует, но серверы и протокол работают.

## 6. SDK и библиотеки

**Rust:**
- **litecoin** (rust) — 0.32.8-rc.1 (18.05.2026), лицензия **CC0-1.0**, ~683 загрузки/90 дней; **нет стабильного релиза** (только rc); заявлена поддержка MWEB. Молодой крейт — использовать с осторожностью.
- **rust-bitcoin** (0.32.102, CC0-1.0, активен) + параметры Litecoin (base58-префиксы, HRP) — рабочий путь; sighash/структуры идентичны Bitcoin.
- **electrum-client 0.25.2** (MIT, активен) — Electrum-протокол.

**Flutter/Dart:**
- **bitcoin_base 7.3.0** (16.07.2026, BSD-3-Clause) — поддержка LTC: P2PK/P2PKH/P2SH/P2WPKH/P2WSH + интеграция Electrum API.
- MWEB в Dart-библиотеках — «НЕ ПОДТВЕРЖДЕНО» (не поддерживается, не требуется).

## 7. Лицензии зависимостей vs MIT OR Apache-2.0

| Зависимость | Лицензия | Совместимость с VEYRO |
|---|---|---|
| litecoin (rust) | CC0-1.0 | ✅ |
| rust-bitcoin, secp256k1, bip39 | CC0-1.0 | ✅ |
| electrum-client | MIT | ✅ |
| bitcoin_base (Dart) | BSD-3-Clause | ✅ (атрибуция) |
| Litecoin Core (узел, только для справки/тестов) | MIT | ✅ |

Конфликтов нет.

## 8. Чек-лист совместимости VEYRO

| Операция | Статус | Что требуется |
|---|---|---|
| Создание кошелька (BIP39+BIP32) | ✅ | стандартные алгоритмы |
| Импорт/restore seed | ⚠️→✅ | путь m/44'/2' (BIP44); для bech32-кошельков — предложить m/84'/2' (нестандартизирован); выбор пути в UI |
| Импорт WIF | ✅ | префикс 0xB0 |
| Получение (receive, QR) | ✅ | L.../M.../ltc1... (дефолт — P2WPKH ltc1) |
| Баланс/история | ✅ | Electrum-протокол (rust electrum-client) / свой узел |
| Сборка + подпись | ✅ | rust-bitcoin с параметрами LTC; bitcoin_base (Dart) |
| Broadcast | ✅ | Electrum broadcast / sendrawtransaction |
| Полный цикл без серверов VEYRO | ✅ | живые публичные Electrum-серверы LTC |
| MWEB (получение/отправка в ltcmweb) | ❌ | **не поддерживается** — только transparent-часть (документированное ограничение) |

## 9. Безопасность, лимиты, блокеры

1. **MWEB-слепота**: переводы в MWEB невидимы в прозрачной истории; если пользователь получит средства на ltcmweb-адрес сторонним кошельком, VEYRO их не отобразит. Обязательное предупреждение в UI; VEYRO не генерирует MWEB-адреса.
2. **Клиент Electrum-LTC заброшен** — серверы живы, но экосистема хрупкая; VEYRO использует rust electrum-client (собственная реализация протокола).
3. Молодой крейт litecoin-rs (нет стабильной версии) — предпочтительно rust-bitcoin + параметры LTC.
4. Нестандартизированные bech32-пути (m/84'/2') — риск при импорте сторонних seed.
5. Приватность публичных серверов (см. §5).
6. Блокеров для transparent-цикла нет.

## 10. Вердикт для матрицы совместимости

### **Full support** (только transparent-часть, без MWEB)

Шкала: Research required → Watch-only → Receive supported → Send supported → Full support (Blocked — отдельно).

Все компоненты подтверждены: форматы адресов (L/M/ltc1 с живыми примерами), деривация m/44'/2' (+ выбор для segwit), sighash стандартные (форк Bitcoin Core), maturity 100, лимиты по коду, живые публичные Electrum-серверы LTC, активные библиотеки Rust/Dart с поддержкой LTC. Полный цикл не требует серверов VEYRO. Ограничение — MWEB не поддерживается (фиксируется в матрице и в UI-предупреждениях).

## 11. Источники

1. Litecoin — chainparams.cpp (master и v0.21.5.8 — magic, порты, префиксы, HRPs, MWEB-параметры, genesis-ассерты): https://raw.githubusercontent.com/litecoin-project/litecoin/master/src/chainparams.cpp
2. Litecoin — chainparamsbase.cpp (RPC-порты; строка «testnet4» как идентификатор тестнета): https://raw.githubusercontent.com/litecoin-project/litecoin/v0.21.5.8/src/chainparamsbase.cpp
3. Litecoin — consensus.h (COINBASE_MATURITY=100, лимиты блока): https://raw.githubusercontent.com/litecoin-project/litecoin/master/src/consensus/consensus.h
4. Litecoin — CreateChainParams (signet → CTestNetParams, TODO): https://raw.githubusercontent.com/litecoin-project/litecoin/v0.21.5.8/src/chainparams.cpp (строки ~451–458)
5. litecoinspace.org API (live 11.11.2026): https://litecoinspace.org/api/block-height/0 (genesis) и /api/blocks (живые адреса блока)
6. Публичный servers.json Electrum-LTC (7 серверов, порты 50001/50002, proto 1.4.2) — проверен ранее в исследовании; клиент Electrum-LTC: https://electrum-ltc.org (предупреждение о заброшенности); альтернативный форк: https://ltc-electrum.github.io
7. SLIP-0044 (coin type 2): https://github.com/satoshilabs/slips/blob/master/slip-0044.md
8. BIP-0044, BIP-0173: https://github.com/bitcoin/bips
9. crates.io API (litecoin, electrum-client, bitcoin): https://crates.io/api/v1/crates/litecoin и др.
10. pub.dev: bitcoin_base — https://pub.dev/packages/bitcoin_base
11. GitHub issue litecoin-project/litecoin#368 (третий источник тестнет-genesis) — проверено ранее в исследовании.
