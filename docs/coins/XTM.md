# Технический паспорт монеты: XTM

> Составлено 11.11.2026. Только проверенные факты; неподтверждённое помечено
> `НЕ ПОДТВЕРЖДЕНО`.

- **Тикер(ы):** **XTM** — базовый токен L1 (Minotari). Родственные обозначения: **TARI** — токен L2 «Ootle» (запуск mainnet 11.11.2026; создаётся только сжиганием XTM 1:1); **XTR** — биржевая нотация L2-токена, которую использует XT.com (см. паспорт XTR.md); **WXTM** — wrapped-представление. RFC-сайт так и называет слой: «The Base Layer (XTM)».
- **Официальное название проекта:** Tari (L1 называется Minotari; разработка — Tari Labs / Tari Developer Community)
- **Официальный сайт:** https://tari.com (downloads, tokenomics, lessons)
- **Официальный репозиторий:** https://github.com/tari-project/tari (Rust, BSD-3-Clause); криптобиблиотека: https://github.com/tari-project/tari-crypto
- **Официальная документация:** RFC/TIP-сайт https://rfc.tari.com (ключевые: MT-0155 TariAddress, MT-0150 Wallets, MT-0131 Mining, MT-0132 Merge Mining Monero, MT-0140 Syncing/pruning, MT-0181 Bulletproofs+, MT-0201 TariScript); гайд для бирж: https://tari.com/lessons/09_adding_tari_to_your_exchange; L2: https://ootle.tari.com
- **Статус исследования:** завершено

## Идентификация сети

- **Mainnet:** PoW-блокчейн Minotari (Mimblewimble, Rust). Запуск ~20.05.2025 (CoinPaprika started; листинг XTM/USDT на XT — 12.06.2025). Высота ~385 000 (02.11.2026). Genesis-хэш: **НЕ ПОДТВЕРЖДЁН** (в открытых RFC не публикуется, берётся из конфига ноды).
  - Гибридный PoW (RFC MT-0131, статус Implemented): **4 независимые полосы по 25%** — RxM (merge-mining с Monero, RandomX; pow_algo=0), **SHA3x** (pow_algo=1), RxT (нативный RandomX; pow_algo=2), **Cuckaroo29** (pow_algo=3). Суммарное целевое время блока **120 с** (по 480 с на алгоритм); перретаргет — LWMA, окно 90 блоков на алгоритм.
  - Mining hash: Blake2b с domain-separated хэшированием (домен `com.tari.base_layer.core.blocks`, 13 полей заголовка). SHA3x = тройной Keccak SHA3-256 над `nonce(8B LE) ‖ mining_hash ‖ pow_record(0x01)`; сложность big-endian, block hash тоже big-endian (историческая конвенция «ведущих нулей»).
  - Эмиссия: **21 млрд XTM**, ~30% премайн, экспоненциальное затухание ~27,8 года, хвостовая эмиссия 1% (tari.com/tokenomics). Награда на блок — по emission schedule (функция высоты, RFC-глоссарий).
  - Биржи (тикеры CoinGecko id `minotari`): MEXC, BTSE, SafeTrade (XTM/USDT, XTM/XMR), Biconomy, XT — везде базовый символ **XTM**. Цена ~$0,001 (11.11.2026, волатильно).
- **Testnet:** исторические тестсети Esmeralda («Esme»), Igor; nextnet/stagenet; идентификаторы сети зашиты в TariAddress (см. ниже): Mainnet 00, Stagenet 01, Nextnet 02, Localnet 10, Igor 24 (0x18), Esme 26 (0x1A). Текущий публичный тестнет L1: **НЕ ПОДТВЕРЖДЁН** (L2-тестнет для Ootle — см. tari-ootle).
- **Проверка идентичности:** тикер **XTM = Minotari (Tari L1)**, единственная живая PoW-сеть под этим тикером. Доказательства: пулы Kryptex `xtm-sha3x` / `xtm-rx` / `xtm-c29` (pool.kryptex.com); RFC-сайт «The Base Layer (XTM)»; CoinGecko `minotari` («MinoTari (Tari)»), тикеры XTM/USDT на 4 биржах; XT.com — анонс «Listing of XTM (Tari)». Родственный, но другой актив — токен L2 **TARI** (Ootle, запуск 11.11.2026, создаётся сжиганием XTM 1:1; Turbine Model, RFC O-0320): не путать XTM ↔ TARI ↔ XTR (XT.com обзывает L2 как XTR).

## Криптография и ключи

- **Формат адреса:** **TariAddress** (RFC MT-0155, статус Implemented): `[network u8][features u8][view key 32B][spend key 32B][payment_id ≤256B опц.][DammSum-чексумма 8 бит (k=8, m=32)]`. Кодировки: bytes / hex / **base58** / **emoji** (256-символьный emoji-алфавит). Base58-адрес начинается с символа сети, затем символ фич: Mainnet → `1`; фичи: one-sided only `01`→'2', interactive only `02`→'3', both `03`→'4', one-sided+payment_id `05`→'6', interactive+payment_id `06`→'7', all `07`→'8'. Сокращённая форма (без отдельного view key): `[network][features][spend key][checksum]`.
  - Идентификаторы сети (u8 / base58): Mainnet 00/'1' (🐢), Stagenet 01/'2', Nextnet 02/'3', Localnet 10/'H', Igor 24/'d', Esme 26/'f'.
- **Формат публичного ключа:** Ristretto255 (tari-crypto; семейство curve25519-dalek). Ключевые пары кошелька: **spend key** (траты), **view key** (просмотр), script keypair (TariScript), sender offset keypair.
- **Формат приватного ключа:** master seed (24 слова, см. ниже) → детерминированная деривация (KeyManager); экспорт для read-only: `export-view-key-and-spend-key` выдаёт hex view key + spend key.
- **Схема деривации ключей:** нативная — детерминированная деривация от мастер-ключа через KeyManager (крейты `tari_transaction_key_manager`/legacy_key_manager; ветвь/индекс). **BIP44-пути не используются**, SLIP-0044-регистрация отсутствует (проверено 11.11.2026).
- **Мнемонический стандарт:** **24 слова из предопределённого списка** (гайд для бирж: «seed phrase is a 24-word phrase generated from a pre-defined list of words»). Это схема **cipher seed** (LibWallet 0.13.0, обновление от 04.11.2021), а **не стандартный BIP39** — сторонние BIP39-кошельки фразу не примут.
- **Алгоритм подписи:** Schnorr на Ristretto255; диапазонные доказательства — **Bulletproofs+** (MT-0181); commitment-подписи (MT-0182); TariScript (MT-0201) — неполный по Тьюрингу стек-скрипт; stealth-адреса (MT-0203) для one-sided платежей (DH-общий секрет между view key получателя и sender offset public key).
- **Совместимость восстановления из фразы:** восстановление из 24 слов поддерживается официально (консольный кошелёк, Tari Universe, Ledger). Известная UX-проблема: при вводе слов по одному (перевод строки) импорт ломается (universe issue #3128) — учитывать в UI.

## Транзакции

- **Структура транзакции:** Mimblewimble: Pedersen-коммитменты `C = vH + kG` (значения скрыты), inputs/outputs + kernels (excess-подпись; kernels не прунятся никогда). Cut-through **запрещён** (RFC-0201) в отличие от классического MW.
- **Расчёт комиссии:** по «граммам»: вес транзакции/блока измеряется в **grams**, комиссия = fee_per_gram × вес (глоссарий RFC: Transaction Weight; кошелёк оценивает fee по размеру, загруженности сети и приоритету — MT-0150).
- **Блокировки/имматурность:** coinbase maturity: **НЕ ПОДТВЕРЖДЕНО**; существуют time-locked UTXO (в get-balance отдельная строка «Time locked») и pending incoming/outgoing балансы.
- **Модель баланса:** UTXO (Mimblewimble), с состояниями Spent/Unspent/Unconfirmed.
- **Особые поля:** **payment_id** — до 256 байт, шифруется on-chain на UTXO; встроен в TariAddress; стандарт для биржевых депозитов (референс депозита). Coinbase extra — произвольные 64 байта в coinbase-UTXO. Единицы: 1 XTM = 10⁶ µT (microMinotari); в CLI суммы без суффикса — в µT, с суффиксом `T` — в XTM.
- **Интерактивные и односторонние транзакции:** interactive (классический MW-обмен) — только для p2p; **one-sided (неинтерактивные)** — для депозитов на биржи/пулы. Валидация типа адреса: 2-й байт адреса = `01` hex → interactive; такие адреса для депозитов **отклонять**.

## Доступ к сети

- **Методы RPC:** gRPC (protobuf): нода — порт **18142**, кошелёк — порт **18143** (default `/ip4/127.0.0.1/tcp/18143`, поддерживается grpc_authentication login/password и TLS). Описание API: `applications/minotari_app_grpc/proto/wallet.proto` (GetCompletedTransactions — стрим для мониторинга депозитов, GetBalance и др.). Консольный кошелёк: команды `get-balance`, `send-minotari <amount> <dest>`, `export-view-key-and-spend-key`, `whoami`, sync и т.д.
- **P2P-протокол:** порт **18141** (multiaddr; поддержка **Tor/onion3** встроена; публичным серверам требуется Tor-клиент или публичный IP). Wire-протокол собственный (Tari Comms, RFC MT-0170…0174).
- **Лёгкий клиент:** отдельного SPV-протокола нет; для бирж/сервисов рекомендуется своя нода (или публичная с открытым gRPC) + read-only кошелёк по view key.
- **Узел:** `minotari_node` (Rust; режимы Archive/Pruned — MT-0140; pruned-horizon настраивается). Бинарники: minotari_node, minotari_console_wallet, minotari_miner, minotari_merge_mining_proxy, randomx-benchmark. Требования к диску/памяти: **НЕ ПОДТВЕРЖДЕНЫ** (зависят от pruning horizon).
- **Публичные RPC:** публичные ноды возможны (гайд для бирж допускает public node с gRPC); официальный список публичных шлюзов: **НЕ ПОДТВЕРЖДЕНО**. Предупреждение о приватности: подключение к чужой ноде раскрывает ей ваши транзакции/запросы.
- **Explorer:** https://explore.tari.com (L1); L2 — https://ootle.tari.com. Для истории транзакций годятся прямые ссылки на explore.tari.com.

## SDK и библиотеки

- **Официальные SDK:**
  - Rust: `minotari_wallet` (base_layer/wallet), `minotari_wallet_ffi` (FFI для мобильных), `minotari_wallet_grpc_client`, `tari_crypto` (Ristretto255, Bulletproofs+; BSD-3-Clause, ~23★, активен: коммиты 10.2026), `tari_transaction_key_manager`, Ledger-интеграция `minotari_ledger_wallet`.
  - Мобильные приложения: `wallet-android` (Kotlin), `wallet-ios` (Swift) — в сторах публикуются как **Tari Universe Wallet** (XTM).
  - Десктоп: **Tari Universe** (`tari-universe` TypeScript + `universe` Rust/Tauri) — официальный майнер+кошелёк.
  - JS: `wallet-grpc-client` (Node.js).
  - MCP: `minotari_mcp_wallet` — кошелёк-клиент для Model Context Protocol (агентские интеграции).
- **Rust-библиотеки:** весь L1-стек — Rust/BSD-3-Clause; независимых аудитов: **НЕ ПОДТВЕРЖДЕНО**.
- **Flutter/Dart-интеграции:** официальной Dart-библиотеки нет; путь интеграции VEYRO — gRPC (proto-файлы в репо, любой язык) или Rust FFI.
- **Лицензии зависимостей:** BSD-3-Clause (tari, tari-crypto, RFC-доки) — совместимо с MIT OR Apache-2.0.

### Майнинг-инфраструктура

- Пулы Kryptex: `xtm-sha3x.kryptex.network:7039` (SHA3x), `xtm-rx.kryptex.network:7038` (RandomX/RxT), Cuckaroo29 — порт 7040 (страница xtm-c29); min payout 200 XTM (≈$0,22). Merge-mining с Monero через пулы XMR (например, supportxmr) по RFC MT-0132; официальный прокси `clythor` (репозиторий tari-project: «Mining Tari and Monero with RandomX»). ASIC: **Goldshell XT BOX / XT Card** (SHA3X). Официальный клиент-майнер: Tari Universe (CPU/GPU, встроенный кошелёк).

## Совместимость кошелька

- [x] Создание кошелька — minotari_console_wallet / Tari Universe / FFI
- [x] Импорт кошелька — 24 слова, Ledger (hardware wallet)
- [x] Восстановление — из seed words (скан цепи derived-ключами, MT-0150); из view key — read-only
- [x] Получение (адрес/QR/URI) — one-sided адреса (base58/emoji) + payment_id; deep links (MT-0154); QR
- [x] Баланс — get-balance (available / time locked / pending incoming / pending outgoing)
- [x] История транзакций — GetCompletedTransactions (gRPC-стрим)
- [x] Отправка (построение, подпись, бродкаст) — send-minotari / wallet gRPC
- [x] Мониторинг подтверждений — gRPC ноды/кошелька

Обязательно при интеграции: принимать только one-sided адреса (2-й байт ≠ `01` hex) и маршрутизировать учёт депозитов через payment_id.

## Безопасность и ограничения

- **Известные ограничения:** Mimblewimble — балансы/адреса не видны в эксплорере; интерактивные адреса непригодны для депозитов (обязательная валидация 2-го байта); 4 PoW-полосы — поддержка майнинга требует всех четырёх конфигураций; блоки ~2 мин → ждать подтверждений дольше, чем в QTC-подобных сетях; seed-фраза несовместима с BIP39.
- **Риски безопасности:** **двухтокеновая модель** — с 11.11.2026 существует L2-токен TARI (сжигание XTM 1:1, Turbine Model); сторонние ресурсы называют L2 то TARI, то XTR (XT.com) — высокий риск путаницы у пользователей; UX-баги импорта seed (universe #3128); публичные RPC раскрывают транзакции провайдеру.
- **Блокеры:** нет. Все кошелёчные операции покрываются gRPC/FFI; в репозитории есть proto-описания и эталонный гайд для бирж.

## Вывод для матрицы поддержки

Актив идентифицирован уверенно: **XTM = Minotari (Tari L1)**, гибридный PoW (4 алгоритма), Mimblewimble/Ristretto255, зрелая документация (RFC Implemented) и официальный гайд интеграции для бирж. Предлагаемый статус матрицы: **«Готов к интеграции»** — полный кошелёк реализуем поверх gRPC (нода 18142 / кошелёк 18143) с read-only мониторингом по view key; требования: one-sided-адреса + payment_id, поддержка 24-словной seed-фразы (не BIP39), учёт XTM↔TARI↔XTR в UI. Главный риск: двухтокеновая модель после запуска Ootle (11.11.2026) и разнобой тикеров L2 (TARI/XTR) — путаница при указании актива пользователями.

## Источники

1. https://rfc.tari.com/RFC-0155_TariAddress.html — спецификация TariAddress (DammSum, фичи, сети, emoji)
2. https://rfc.tari.com/RFC-0150_Wallets.html — кошелёк: seed, деривация, восстановление, read-only
3. https://rfc.tari.com/RFC-0131_Mining.html — гибридный PoW: 4 алгоритма, LWMA, mining hash, SHA3x
4. https://rfc.tari.com/RFC-0132_Merge_Mining_Monero.html — merge-mining Monero
5. https://rfc.tari.com/RFC-0140_Syncing_and_seeding.html — архивный/пруненый режимы ноды
6. https://rfc.tari.com/Glossary.html — вес в граммах, emission schedule, kernels
7. https://tari.com/lessons/09_adding_tari_to_your_exchange — официальный гайд интеграции (gRPC 18142/18143, payment_id, валидация адресов, send-minotari, µT)
8. https://tari.com/tokenomics — эмиссия 21 млрд, премайн, затухание
9. https://github.com/tari-project/tari — монорепозиторий (LICENSE BSD-3, Cargo.toml: minotari_wallet, wallet_ffi, ledger_wallet, mcp_wallet)
10. https://github.com/tari-project/tari-crypto — криптобиблиотека (Ristretto255, domain-separated hashing)
11. https://github.com/tari-project/tari-ootle и https://rfc.tari.com/RFC-0320_TurbineModel.html — L2 Ootle, токен TARI, сжигание XTM 1:1
12. https://pool.kryptex.com/xtm-sha3x (и /xtm-rx, /xtm-c29) — пулы Kryptex, порты 7039/7038/7040
13. https://www.coingecko.com/en/coins/minotari — тикеры XTM/USDT (MEXC, BTSE, SafeTrade, Biconomy)
14. https://xtsupport.zendesk.com/hc/en-us/articles/46646509443353 — XT: листинг XTM (Tari), старт торгов 12.06.2025
15. https://explore.tari.com — эксплорер L1
16. https://tari.com/updates/2021-11-04-update-62.html — cipher seed scheme (мнемоника LibWallet 0.13.0)
