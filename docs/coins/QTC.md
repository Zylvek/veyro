# Технический паспорт монеты: QTC

> Составлено 11.11.2026. Только проверенные факты; неподтверждённое помечено
> `НЕ ПОДТВЕРЖДЕНО`. Тикер QTC конфликтный — раздел «Проверка идентичности»
> обязателен к прочтению перед любой интеграцией.

- **Тикер(ы):** **QTC** — используется проектом и Kryptex Pool, CoinGecko (symbol `qtc`), независимым эксплорером qtcscan.com. Альтернативные обозначения: **QUANTUS** (WhatToMine; майнинг-калькулятор Kryptex; пара QUANTUS/USDT на SafeTrade); **QUAN** — символ, зарегистрированный в SLIP-0044 (coin type 189189). NEAR-обёртка: `qtc.omft.near`.
- **Официальное название проекта:** Quantus (Quantus Network) — постквантовая L1
- **Официальный сайт:** https://quantus.com
- **Официальный репозиторий:** https://github.com/Quantus-Network (основной: `chain` — форк polkadot-sdk; майнер: `quantus-miner`; документация: `docs`)
- **Официальная документация:** https://docs.quantus.com
- **Статус исследования:** завершено

## Идентификация сети

- **Mainnet:** PoW-блокчейн на стеке **Substrate/polkadot-sdk** (Rust). Запуск mainnet ~сентябрь–октябрь 2026 (CoinPaprika started 2026-10-22; в репозитории — «mainnet v1.0.1+»). Genesis-хэш и chain ID: **НЕ ПОДТВЕРЖДЕНЫ** (из открытых источников не извлечены).
  - PoW: **QPoW** — Poseidon2 (zk-friendly хэш); аудит Poseidon2/QPoW — Eiger.
  - Параметры: время блока ~14,42 с; награда 0,30 QTC/блок; эмиссия **21 000 000 QTC** (WhatToMine / docs).
  - Порты: RPC **9944** (Substrate HTTP/WS), P2P **30333**, metrics 9615, порт майнера **9833/UDP** (QUIC, ALPN `quantus-miner/2`, auth-token + TLS-pinning).
- **Testnet:** «Planck» — закрытый, работа прекращена (docs.quantus.com). Текущего публичного тестнета нет.
- **Проверка идентичности:** тикер **QTC в майнинговом контексте 2025–2026 = Quantus Network** (постквантовая PoW L1), а НЕ Qubitcoin и НЕ Qitchain. Доказательства: (1) пул Kryptex `pool.kryptex.com/qtc` ведёт на docs.quantus.com; (2) CoinGecko id `quantus` с symbol **qtc**, категории «Layer 1 (L1)», «Proof of Work (PoW)», «Quantum-Resistant», платформа near-protocol `qtc.omft.near`; (3) эксплорер qtcscan.com — «Quantus Explorer: QTC Blocks, Accounts and Network Stats»; (4) explorer.quantus.com (Subsquid) и GitHub-орг Quantus-Network; (5) WhatToMine — страница Quantus (под именем QUANTUS); (6) SLIP-0044: `189189 | QUAN | Quantus Network`.
  - **Коллизия тикера (критично):** параллельно живёт **Qubitcoin (QTC)** — PoW-монета с алгоритмом Qhash, перезапуск ~декабрь 2024: WhatToMine `/coins/450-qtc-qhash` называет её «QTC», на SafeTrade пара **QTC/USDT — это Qubitcoin**, тогда как Quantus там же торгуется как **QUANTUS/USDT** (две разные пары!). Исторически тикер QTC также носила **Qitchain Network** (CoinPaprika `qtc-qitchain-network`, неактивна). ЧтоToMine и калькулятор Kryptex отображают Quantus как QUANTUS, а QTC — как Qubitcoin; при этом пул Kryptex и CoinGecko используют QTC для Quantus. Любой вывод «на биржу по тикеру QTC» требует сверки по адресу/контракту, а не по тикеру.

## Криптография и ключи

- **Формат адреса:** SS58 (Substrate), префикс **189** — адреса начинаются с `qz…`. Для майнинговых выплат проект использует отдельные **wormhole-адреса**: 32-битный preimage/inner hash, отдельный путь деривации, приватность по умолчанию (адрес не связывает выплаты в цепочке).
- **Формат публичного ключа:** постквантовый **ML-DSA-87** (FIPS 204, семейство CRYSTALS-Dilithium); размер публичного ключа ≈ 2,6 КБ, подписи ≈ 4,6 КБ (параметры уровня NIST — стандарт FIPS 204).
- **Формат приватного ключа:** seed из BIP39-мнемоники; хранение — Substrate-совместимое (keystore ноды/кошелька). Watch-only/view-key модели: **НЕ ПОДТВЕРЖДЕНО** (Substrate-стандартных view-ключей нет).
- **Схема деривации ключей:** **m/44'/189189'/account'/0'/0'** — все уровни hardened; coin type **189189**, зарегистрирован в SLIP-0044 (там символ — QUAN).
- **Мнемонический стандарт:** **BIP39, 24 слова** (docs.quantus.com).
- **Алгоритм подписи:** ML-DSA-87 (Dilithium, FIPS 204) — транзакции; P2P-шифрование/инкапсуляция — **ML-KEM-768** (FIPS 203, Kyber): постквантовые форки libp2p (`qp-libp2p-noise`, `qp-libp2p-identity`, `sc-network-pqc`).
- **Совместимость восстановления из фразы:** восстановление из 24 слов по пути m/44'/189189'/…; проверено на кошельках quantus-apps (официальный мобильный бета-кошелёк). Совместимость с третьесторонними Substrate-кошельками (polkadot-js и пр.): **НЕ ПОДТВЕРЖДЕНО** — стандартный polkadot-js не умеет ML-DSA (нужен форк с pluggable signatures).

## Транзакции

- **Структура транзакции:** Substrate-модель (extrinsics, account-based поверх runtime).
- **Расчёт комиссии:** Substrate weight-based fee model; конкретные константы (weightToFee, lengthToFee): **НЕ ПОДТВЕРЖДЕНЫ**.
- **Блокировки/имматурность:** coinbase-период: **НЕ ПОДТВЕРЖДЕНО**.
- **Модель баланса:** account (Substrate system pallet), не UTXO.
- **Особые поля:** wormhole-адрес (inner hash/preimage) в майнинговых выплатах; эмиссия 21M QTC, BR 0,30 QTC, BT ~14,42 с.

## Доступ к сети

- **Методы RPC:** стандартный Substrate RPC (порт 9944, HTTP/WS): chain_getBlockHash, chain_getBlock, state_getBalance, author_submitExtrinsic, state_subscribeRuntimeVersion и т.п. Полный перечень в runtime: через `state_getMetadata` (стандартный подход). Порт майнера: 9833 UDP/QUIC (ALPN `quantus-miner/2`, auth-token, TLS-pinning) — **не** классический stratum.
- **P2P-протокол:** порт 30333, Substrate/libp2p (постквантовый форк шум-протокола — ML-KEM-768).
- **Лёгкий клиент:** официально — мобильный кошелёк (quantus-apps), работающий через ноду/индексер; смарт-контрактного light-client/RPC-light-протокола: **НЕ ПОДТВЕРЖДЕНО**.
- **Узел:** форк polkadot-sdk (`chain`); CLI: `quantus-cli`. Требования к диску/памяти: **НЕ ПОДТВЕРЖДЕНЫ**.
- **Публичные RPC:** **НЕ ПОДТВЕРЖДЕНО** (для интеграции поднимать свою ноду; телеметрия сети — telemetry.quantus.cat).
- **Explorer:** https://explorer.quantus.com (Subsquid-индексер) и независимый https://qtcscan.com — для ссылок из истории транзакций.

## SDK и библиотеки

- **Официальные SDK:**
  - Rust: `quantus-api-client` (Substrate API поверх WS), `quantus-miner` (CLI-майнер), `miner-tauri-gui` (GUI-майнер), `quantus-cli`, `quantus_ur` (UR/QR), `quantus-wasm` (JS/WASM-обёртка примитивов).
  - Dart/Flutter: `quantus-apps` (мобильный кошелёк iOS/Android, бета), форк **polkadart** (`polkadart_1_x` — «pluggable signature scheme»), `resonance-polkadart` — готовый Dart-стек для интеграции.
  - Аппаратные: `ledger-app-rs` (Ledger Nano S+/X/Stax/Flex), форк `keystone3-firmware` — статус: экспериментальные, готовность **НЕ ПОДТВЕРЖДЕНА**.
- **Rust-библиотеки:** `qp-rusty-crystals` (реализация ML-DSA; Apache-2.0; аудит **Neodyme**), `qp-poseidon` (Poseidon2), `qp-zk-circuits` (аудит **Eiger**), `qp-poseidon-constants`, `rust-fn-dsa`/`rusty-falcon` (FN-DSA/Falcon), `qpow-benchmark`, `zk-trie`/`zk-state-machine` (zk-форки Substrate-тр). Ядро сети — форк polkadot-sdk (Rust, активная разработка).
- **Flutter/Dart-интеграции:** официальные — да (см. polkadart-форки и quantus-apps); это ключевой путь интеграции для VEYRO.
- **Лицензии зависимостей:** qp-* — Apache-2.0/BSD-подобные (совместимы с MIT OR Apache-2.0); **polkadot-sdk — GPL-3.0** (форк `chain`): вопросы компиляции/линковки закрытых компонентов требуют юр. проверки; near-mpc/nearcore — Apache-2.0 (мостовая обвязка).

## Совместимость кошелька

- [x] Создание кошелька — quantus-apps / Substrate-keystore
- [x] Импорт кошелька — BIP39 (24 слова), SS58-адреса
- [x] Восстановление — по пути m/44'/189189'/account'/0'/0'
- [x] Получение (адрес/QR/URI) — `qz…` (SS58, префикс 189); для майнинговых выплат — wormhole-адреса; `quantus_ur` (UR/QR)
- [x] Баланс — Substrate RPC (state_*)
- [x] История транзакций — explorer.quantus.com / qtcscan.com / RPC
- [x] Отправка (построение, подпись, бродкаст) — author_submitExtrinsic (подпись ML-DSA-87; для Dart — форк polkadart с pluggable signatures)
- [x] Мониторинг подтверждений — Substrate-подписки (chain_subscribeNewHeads и т.п.)

Ограничение: стандартный polkadot-js/polkadart ML-DSA не поддерживает — обязателен форк (у проекта уже есть).

## Безопасность и ограничения

- **Известные ограничения:** очень молодая сеть (mainnet ~окт 2026); закрытый тестнет Planck (нет публичной площадки для испытаний); майнинг не через stratum, а через собственный QUIC-протокол (порт 9833, auth-token+TLS-pin) — сторонние пул/майнер-обвязки несовместимы; огромные подписи (≈4,6 КБ) и ключи (≈2,6 КБ) → тяжёлые транзакции и большой state; wormhole-адреса — нестандартная модель выплат.
- **Риски безопасности:** коллизия тикера QTC (Qubitcoin жив и торгуется на SafeTrade как QTC/USDT; Qitchain — исторический) — риск ошибочных депозитов/выводов по тикеру; NEAR-обёртка `qtc.omft.near` (CoinGecko показывает Quantus как NEAR-токен при живой L1-цепи — это мост через NEAR chain abstraction/near-mpc, не ошибка, но запутывает); GPL-3.0 в polkadot-sdk — лицензионный вопрос для производных клиентов.
- **Блокеры:** нет критических; для VEYRO — обязательное использование PQ-библиотек проекта (qp-rusty-crystals / polkadart-форк), стандартные Substrate-стеки несовместимы по подписям.

## Вывод для матрицы поддержки

Актив идентифицирован уверенно: **QTC (в контексте пулов Kryptex) = Quantus Network**, постквантовая PoW L1 (Poseidon2/QPoW, ML-DSA-87/ML-KEM-768, SS58-189). Предлагаемый статус матрицы: **«Технически реализуемо»** через официальный Dart-стек (polkadart-форк) или Substrate RPC; перед включением обязательны: (1) сверка коллизии QTC↔Qubitcoin во всех UI-надписях и предупреждение пользователям, (2) подтверждение публичных RPC или развёртывание своей ноды, (3) поддержка wormhole-адресов для пуловых выплат. Главный риск: коллизия тикера QTC с активным Qubitcoin (на SafeTrade и WhatToMine QTC — это другая монета).

## Источники

1. https://quantus.com — официальный сайт
2. https://docs.quantus.com — документация (адреса, деривация, мнемоника, порты, майнер QUIC)
3. https://github.com/Quantus-Network — организация (chain, quantus-miner, quantus-apps, qp-*, polkadart-форки, ledger-app-rs, slips, improvement-proposals)
4. https://github.com/satoshilabs/slips/blob/master/slip-0044.md — `189189 | QUAN | Quantus Network`
5. https://www.coingecko.com/en/coins/quantus — symbol qtc, L1/PoW/Quantum-Resistant, платформа qtc.omft.near
6. https://qtcscan.com — независимый эксплорер «Quantus Explorer: QTC»
7. https://explorer.quantus.com — официальный эксплорер (Subsquid)
8. https://pool.kryptex.com/qtc — пул Kryptex (QTC = Quantus)
9. https://whattomine.com — QUANTUS (Quantus) и /coins/450-qtc-qhash (Qubitcoin) — доказательство коллизии
10. https://safe.trade — пары QUANTUS/USDT (Quantus) и QTC/USDT (Qubitcoin)
11. https://telemetry.quantus.cat — телеметрия сети
12. https://github.com/Quantus-Network/near-mpc — NEAR-мост (chain abstraction)
