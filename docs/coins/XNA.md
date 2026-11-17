# Технический паспорт монеты: XNA

> Паспорт составлен по состоянию на ноябрь 2026. Критические параметры — из
> официальных исходников NeuraiProject/Neurai и официального сайта neurai.org
> (страницы specs/wallets/libs). Неподтверждённое помечено `НЕ ПОДТВЕРЖДЕНО`.

- **Тикер(ы):** XNA (Neurai; у пулов встречается только XNA)
- **Официальное название проекта:** Neurai
- **Официальный сайт:** https://neurai.org (specs, wallets, libraries,
  webwallet.neurai.org)
- **Официальный репозиторий:** https://github.com/NeuraiProject/Neurai
  (MIT, основной); зеркало/под-тима: https://github.com/NeuraiTeam/Neurai
  (MIT, создан 06.04.2026)
- **Официальная документация:** neurai.org/specs, neurai.org/neurai-software/libs
  (версии пакетов на сентябрь 2026), `README.md` репозитория (сетевые
  параметры), npm-документация @neuraiproject/*
- **Статус исследования:** завершено (desk research, ноябрь 2026; сетевые тесты
  не проводились)

## Идентификация сети

- **Mainnet:**
  - Genesis-хэш (X16R-генезис):
    `00000044d33c0c0ba019be5c0249730424a69cb4c222153322f68c6104484806`,
    merkle root
    `4b28bf93d960cd83d1889757381d5a587208464e9075bdc0739151fbe15f5951`,
    время генезиса 1681720840 (**17.04.2023**, официальная дата запуска
    2023-04-17 08:40 UTC).
  - Magic bytes: `0x4e455552` (ASCII «NEUR»)
  - Порты: P2P `19000`, RPC `19001` (подтверждено дважды: исходники chainparams
    и neurai.org/specs)
  - Блок: **60 секунд**; PoW **KAWPOW** (активирован с генезиса; X16R-генезис,
    KAWPOW с блока 1).
  - Награда: 50,000 XNA старт; **micro-halving каждые 14,400 блоков (~10 дней,
  -5%)**; макс. эмиссия 21,000,000,000 XNA (21 млрд); 8 MB начальный размер
    блока.
  - Asset-слой (как у RVN): активирован с высоты 10; повышенные burn-ставки
    (issue — 1,000 XNA).
- **Testnet:** magic «RUEN» `0x5255454e`, P2P `19100`, RPC `19101`
  (datadir `testnet`).
- **Regtest:** P2P `19200`, RPC `19201`.
- **Проверка идентичности:** тикер однозначен. Neurai — форк Ravencoin
  (запуск 17.04.2023, KAWPOW, asset-слой, DePIN-мессенджинг). Официальный сайт
  neurai.org закрепляет тикер XNA; пулы (например, Kryptex) выплачивают
  майнинг на адреса, начинающиеся с `N`. SLIP-44 coin type 1900 зарегистрирован
  именно для Neurai. Двусмысленности нет.

## Криптография и ключи

- **Формат адреса:** base58 + новые bech32m-типы (см. ниже):
  - Legacy P2PKH: префиксный байт `53` → адреса `N...`
  - Legacy P2SH: префикс `117` (адреса `h...`-типа) — точный вид сверить при
    реализации
  - **Новые форматы 2026** (neurai.org/specs): bech32m HRP `nq`
    (strict ECDSA v3), `pq` (strict PQ v2, подписи ML-DSA-44), `nc`
    (generic AuthScript v1), `nzk` (private receiving). Для майнинговых выплат
    используются legacy-адреса `N...`.
- **Формат публичного ключа:** SEC1 secp256k1 (классическое семейство);
  пост-квантовое семейство — ML-DSA-44 (дilithium) со своим формата ключей.
- **Формат приватного ключа:** WIF, префикс `0x80` (как BTC; подтверждено
  neurai.org/specs); xprv/xpub стандартные Bitcoin (`0x0488ADE4`/
  `0x0488B21E`); PQ-расширенные ключи: `xpqp`/`tpqp` (в neurai-key с 4.0).
- **Схема деривации ключей (КРИТИЧНО — двойной стандарт):**
  - **Coin type 0** (легаси, унаследован от узла RVN-типа): путь
    `m/44'/0'/0'/0` — кошелёк узла (Neurai-QT/Core), **биржи, ранние кошельки,
    Electrum-Neurai и Web Wallet (Rebel Wallet)**.
  - **Coin type 1900** (SLIP-44, регистрация Neurai): путь `m/44'/1900'/0'/0` —
    аппаратные кошельки (OneKey), мобильные Neurai Wallet, Neurai Sign;
    recommended для новых кошельков (npm-пакет: `xna-legacy` = 1900,
    `xna-old-legacy` = 0, «not recommended for new wallets»).
  - Strict ECDSA: `m/84'/1900'/0'/c/i`; PQ: `m_pq/100'/1900'/0'/0'` (все уровни
    hardened).
  - **Официальное предупреждение (neurai.org/wallets):** кошельки coin type 0 и
    coin type 1900 выводят **разные адреса из одной фразы**; восстановление
    возможно только в кошельке того же семейства.
- **Мнемонический стандарт:** BIP39 (12/18/24 слова, опциональная passphrase).
- **Алгоритм подписи:** ECDSA secp256k1 (legacy); Schnorr-подобные/новые схемы —
  для strict-типов; **ML-DSA-44** для пост-квантовых адресов (вне scope
  майнинговых выплат).
- **Совместимость восстановления из фразы:** ВАЖНО — при восстановлении
  сканировать **обе** деривации (`m/44'/0'` и `m/44'/1900'`), иначе средства на
  «чужом» семействе путей не будут найдены. Это официальная позиция проекта.

## Транзакции

- **Структура транзакции:** Bitcoin/RVN-подобная UTXO + asset-расширения
  (маркеры NIP-040 `rvn`/`xna` в neurai-create-transaction), PSBT поддерживается
  (neurai-sign-esp32: полный PSBT-флоу).
- **Расчёт комиссии:** sat/vByte (weight-модель Bitcoin).
- **Блокировки/имматурность:** coinbase maturity — 100 блоков, унаследовано от
  Ravencoin; `НЕ ПОДТВЕРЖДЕНО` прямым чтением consensus.h Neurai — сверить при
  реализации.
- **Модель баланса:** UTXO (XNA + UTXO-активы).
- **Особые поля:** asset-операции (issue/reissue/transfer/transferwithmessage),
  DePIN-сообщения (depinsubmitmsg) — вне начального scope VEYRO; для майнинговых
  выплат достаточно plain-переводов XNA.

## Доступ к сети

- **Методы RPC:** стандартный набор Bitcoin Core + asset-методы; порт `19001`.
  Публичные RPC-прокси проекта: `main.neurai.org`, `rpc-testnet.neurai.org`
  (WebSocket/HTTP-бэкенд wallet-services; Web Wallet подписывает локально,
  транзакции отправляет через RPC-прокси — модель, аналогичная допустимой для
  VEYRO).
- **P2P-протокол:** порт `19000`, wire-протокол Bitcoin-совместимый
  (magic «NEUR»), KAWPOW-заголовки.
- **Лёгкий клиент:** есть:
  - **electrum-neurai** (Python, Electrum-клиент с поддержкой активов;
    сервер — **electrumx-neurai**); официальные страницы libs.
  - Blockbook-форк (trezor/blockbook) — бэкенд балансов/адресов
    (NeuraiProject/blockbook).
  - wallet-services (Node.js, WebSocket) — синхронизация мобильных/лёгких
    кошельков, push-уведомления, ZMQ-подписка на узел.
- **Узел:** Neurai Core (репозиторий NeuraiProject/Neurai, MIT; актуальная
  линия v1.0.6+ с KAWPOW-фиксом). Диск: полная цепь — десятки ГБ
  (`НЕ ПОДТВЕРЖДЕНО` точно).
- **Публичные RPC:** да — официальные RPC-прокси проекта (`main.neurai.org`,
  `rpc-testnet.neurai.org`) + возможность пользовательского узла. Приватность:
  публичный прокси видит транзакции клиента (но не ключи); рекомендовать
  пользовательский узел/ElectrumX-neurai.
- **Explorer:** форк Blockbook в организации проекта предполагает собственный
  explorer; канонический публичный URL `НЕ ПОДТВЕРЖДЁН` — зафиксировать при
  интеграции.

**P2P-проба заголовков (17.11.2026, живой скан сидов):** DoH-резолв 3 сидов
(`dns.neurai.org`, `seed1/seed2.neurai.org`) → 2-3 IP; узлы `/Neurai:1.0.6/`
(protocol 70028, `nStartHeight` 1 871 752) **молча игнорируют getheaders**
(нет ответа в 20/60 с и на нулевой локатор) и на повторные подключения
отказывают/refused; `getaddr` не отдают ни один. Живого P2P-источника
заголовков через community-сиды нет — нужен узел вне IBD (свой Neurai Core)
или другой транспорт. Статус матрицы честно не менялся.

## SDK и библиотеки

- **Официальные SDK** (страница libs, версии на сентябрь 2026):
  - npm `@neuraiproject/neurai-key` 4.0.0 — адреса/BIP32/BIP44, legacy и PQ;
    сети `xna`, `xna-test`, `xna-legacy` (1900), `xna-old-legacy` (0), `xna-pq`
  - npm `@neuraiproject/neurai-create-transaction` 0.8.0 — построение
    unsigned-транзакций (XNA, активы, NIP-040)
  - npm `@neuraiproject/neurai-jswallet` 0.15.2 — некастодиальный
    кошельковый композит (keys, address scanning, UTXO, signing); бандлы
    CJS/ESM/browser/IIFE
  - `neurai-message`, `neurai-assets` 1.6.0, `neurai-history-list`,
    `neurai-sign-esp32` 0.6.0 (PSBT через ESP32)
  - electrum-neurai (Python) + electrumx-neurai (сервер)
- **Rust-библиотеки:** зрелого кошелькового крейта нет. Рекомендуемый путь:
  `rust-bitcoin` (MIT OR Apache-2.0) + кастомные параметры (base58 53/117,
  WIF 0x80) + KAWPOW-валидация при необходимости
  (`hasherkawpow-sys` 0.1.0, MIT, июль 2026 — только PoW-хэш; параметр
  «512 DAG-item parents» KAWPOW RVN/XNA учитывать при валидации заголовков).
- **Flutter/Dart-интеграции:** готового пакета не найдено; путь — FFI к
  Rust-ядру VEYRO (структуры совместимы с RVN; переиспользовать модуль RVN с
  другими chainparams).
- **Лицензии зависимостей:** Neurai Core — MIT; npm-пакеты проекта — открытые
  (MIT-семейство; сверить при подключении); rust-bitcoin — MIT OR Apache-2.0.
  Совместимо с ядром VEYRO.

## Совместимость кошелька

Отметка = реализуемо существующими средствами (фактический статус — только
после тестов):

- [x] Создание кошелька — BIP39; **обязательный выбор coin type** (для новых
  кошельков — 1900, с поддержкой чтения обеих)
- [x] Импорт кошелька — WIF, xprv, фраза
- [x] Восстановление — **сканирование обеих дериваций** `m/44'/0'` и
  `m/44'/1900'` (официальное требование совместимости)
- [x] Получение — legacy-адреса `N...` (майнинговые выплаты пулов идут на них)
- [x] Баланс — UTXO через RPC/ElectrumX-neurai
- [x] История транзакций — scripthash-history (Electrum) / Blockbook / RPC
- [x] Отправка — построение/подпись rust-bitcoin, бродкаст через RPC-прокси
  или пользовательский узел
- [x] Мониторинг подтверждений — subscribe headers/scripthash
- [ ] Пост-квантовые (`pq1...`) и strict ECDSA (`nq1...`) адреса — вне
  начального scope (реализуемо позже через neurai-key как референс)

## Безопасность и ограничения

- **Зеркальный KAWPOW-инцидент августа 2026:** Neurai (как KAWPOW-форк RVN)
  активировала фикс header-height KAWPOW на высоте **1,739,500 (~16.08.2026)**
  — зеркалирует RVN-эксплойт от 07.08.2026. Все узлы/бэкенды должны работать на
  версии с этим фиксом (v1.0.6+); SPV-валидацию заголовков строить с учётом
  чекпоинта фиксации.
- **Двойная деривация** (0 и 1900) — главный операционный риск: неверно
  выбранный путь при восстановлении = «пустой» кошелёк; обязательное
  сканирование обоих + явный выбор coin type при создании.
- **Малый возраст проекта** (2023) и меньшая зрелость инфраструктуры
  относительно RVN: electrumx-neurai — community-масштаб.
- **Приватность:** официальные RPC-прокси видят транзакции (не ключи);
  рекомендовать пользовательские узлы.
- **Блокеры:** нет. Полный цикл (майнинговые выплаты legacy-XNA) реализуем без
  серверов VEYRO.

## Вывод для матрицы

- **Идентичность:** подтверждена (официальный сайт/репозиторий, SLIP-44 1900,
  genesis/magic из исходников; форк RVN).
- **Реализуемость:** полная для plain XNA — инфраструктура есть
  (ElectrumX-neurai, RPC-прокси, Blockbook, JS-SDK как референс).
- **Главный риск:** двойной стандарт деривации coin type 0/1900 — требует
  сканирования обоих путей и аккуратного UX; плюс пост-эксплойт KAWPOW-фикс
  (высота 1,739,500) как обязательное условие бэкендов.
- **Предлагаемый статус:** `Research required` → после тестового цикла кандидат
  на `Full support` (переиспользование RVN-модуля с другими chainparams +
  двойная деривация). До тестов статус не менять.

## Источники

1. https://github.com/NeuraiProject/Neurai — официальный репозиторий (MIT):
   `src/chainparams.cpp` (genesis, magic «NEUR», порты 19000/19001, base58
   53/117, WIF 0x80), README (награда 50,000 XNA, micro-halving 10 дней/5%,
   supply 21B, запуск 2023-04-17)
2. https://neurai.org/specs — официальные спецификации: деривации
   (`m/44'/0'` узел/легаси, `m/44'/1900'` SLIP-44/OneKey, `m/84'/1900'`,
   PQ `m_pq/100'/1900'`), порты 19000/19001/19100/19101/19200/19201, base58/
   bech32m-префиксы, WIF 0x80
3. https://neurai.org/wallets — таблица кошельков с coin types (QT — 0,
   Electrum — 0, Neurai Wallet — 1900, Neurai Sign — 1900, Web Wallet — 0,
   OneKey — 1900) и официальное предупреждение о несовместимости дериваций
4. https://neurai.org/neurai-software/libs — официальный список библиотек
   (neurai-key 4.0.0, neurai-create-transaction 0.8.0, neurai-jswallet 0.15.2,
   electrum-neurai + electrumx-neurai, wallet-services, публичные RPC
   main.neurai.org / rpc-testnet.neurai.org)
5. https://github.com/NeuraiProject/neurai-jswallet и
   https://github.com/NeuraiProject/neurai-sign-esp32 — реализация сетей
   `xna-legacy` (1900) и `xna-old-legacy` (0), PSBT-флоу
6. https://pool.kryptex.com/articles/neurai-wallet-en — майнинговый пул
   Kryptex: выплаты XNA, официальный web-кошелёк Rebel Wallet
   (webwallet.neurai.org) — подтверждение майнингового контекста
7. https://github.com/NeuraiTeam/Neurai — зеркало/под-тима проекта (MIT, апрель
   2026), KAWPOW + asset layer + DePIN
8. https://github.com/satoshilabs/slips/blob/master/slip-0044.md — SLIP-44:
   coin type 1900 (Neurai)
9. https://docs.rs/hasherkawpow-sys — Rust-биндинги KAWPOW (MIT, июль 2026)
