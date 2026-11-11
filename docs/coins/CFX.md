# Технический паспорт монеты: CFX

> Паспорт составлен по состоянию на 11 ноября 2026. Ключевой вывод: у
> Conflux два пространства — Core Space (нативное) и eSpace (EVM);
> для VEYRO приоритет — eSpace (полный EVM-цикл). Параметры eSpace проверены
> прямыми RPC на двух зеркалах; Core Space исследован по официальным докам.
> Неподтверждённое помечено `НЕ ПОДТВЕРЖДЕНО`.

- **Тикер(ы):** CFX (Conflux; у пулов синонимов нет)
- **Официальное название проекта:** Conflux Network (пространства: Conflux
  Core Space, Conflux eSpace)
- **Официальный сайт:** https://confluxnetwork.org
- **Официальный репозиторий:** https://github.com/ConfluxChain/conflux-rust
  (узел; GPL-3.0; активен, ~718 звёзд)
- **Официальная документация:** https://doc.confluxnetwork.org (Core Space
  и eSpace)
- **Статус исследования:** завершено (desk research + прямые RPC-проверки
  eSpace, ноябрь 2026; транзакционные тесты не проводились)

## Идентификация сети

- **Mainnet (eSpace — приоритет VEYRO):**
  - Chain ID **1030** (`0x406`) — проверено напрямую RPC `eth_chainId` на
    двух зеркалах официального провайдера Confura
    (`evm.confluxrpc.org`/`evm.confluxrpc.com`); подтверждено chainlist.
  - Genesis-хэш:
    `0xf6cec5af1ee95f56038fc30589bcfeb4b960075c3c76b8a0eaa6d36e8e623b50`
    (получен RPC `eth_getBlockByNumber("0x0")` на обоих зеркалах).
  - Сеть жива: ~16,1 млн блоков (RPC); цена ≈ $0,041, капитализация ≈
    $217 млн (CoinGecko, 2026-11-11).
- **Mainnet (Core Space — для справки):** network ID **1029** (mainnet) /
  **1** (testnet) — по официальным докам; прямой RPC-проверкой в рамках
  исследования НЕ ПРОВЕРЕНО (Core использует namespace `cfx_*`, RPC:
  main.confluxrpc.com / test.confluxrpc.com).
- **Testnet:** eSpace — chain ID **71** (`0x47`) (по докам/chainlist;
  RPC-проверка НЕ ПРОВЕРЕНА); Core testnet — network ID 1. Публичные
  тестовые эндпоинты Confura существуют (testnet.confluxrpc.com и
  зеркала).
- **Проверка идентичности:** тикер CFX однозначен — Conflux. Критический
  нюанс: **два адресных пространства** — CFX существует и на Core Space
  (нативные `cfx:`-адреса), и на eSpace (`0x`-адреса). Это не одинаковые
  адреса: переводы между пространствами идут через кросс-спейс механизмы
  (CIP-645, внутренние контракты), а не напрямую. VEYRO поддерживает eSpace;
  Core Space — опционально (см. «Вывод»).

## Криптография и ключи

- **Формат адреса (eSpace):** `0x`-hex, 20 байт, чексумма EIP-55 (стандарт
  EVM).
- **Формат публичного ключа:** secp256k1.
- **Формат приватного ключа:** 32 байта; hex/keystore Ethereum.
- **Схема деривации ключей (eSpace):** практика — `m/44'/60'/a'/0/i`
  (ETH-путь). Отдельной регистрации eSpace в SLIP-44 нет (запись 503
  относится к Core Space). Подтверждение практики: официальное заявление на
  форуме Conflux — eSpace полностью совместим с Ethereum, для аппаратных
  кошельков используется приложение Ethereum (Ledger) с ETH-путём.
- **Мнемонический стандарт:** BIP39.
- **Алгоритм подписи:** ECDSA secp256k1; защита от повторного
  воспроизведения — EIP-155 (chainId 1030).
- **Core Space (справка):** адреса CIP-37 base32 (`cfx:…`/`cfxtest:…`,
  чексумма BCH-cashaddr); EOA = 4-битный тип адреса + правые 156 бит
  keccak — **деривация адреса отличается от Ethereum**; coin type **503**
  (`m/44'/503'/…`) — официально в доках и SLIP-44.
- **Совместимость восстановления из фразы:** eSpace — идентична Ethereum
  (путь 60'); адреса совпадают с ETH-кошельками той же фразы. UI обязан явно
  идентифицировать сеть и пространство.

## Транзакции

- **Структура (eSpace):** стандартные EVM-транзакции: legacy (EIP-155)
  изначально; EIP-2930/EIP-1559 — после Conflux v2.4.0; EIP-7702 — после
  v3.0.0 (по докам); EIP-4844 — нет (по докам).
- **Расчёт комиссии:** фактически фиксированный газ — `eth_gasPrice` =
  `eth_feeHistory.baseFeePerGas` = `0x4a817c800` = **20 gwei** (проверено
  RPC на обоих зеркалах, baseFee постоянен по блокам, gasUsedRatio = 0);
  рекомендация — gasPrice = 20 gwei (и legacy, и 1559-структуры валидны).
- **Блокировки/имматурность:** аккаунтная модель; coinbase-имматурности для
  получателей нет.
- **Модель баланса:** account/nonce.
- **Особые поля:** нет. Кросс-спейс переводы (Core ↔ eSpace) — отдельные
  контрактные операции (CIP-645), в начальный охват не входят.

## Доступ к сети

- **Методы RPC (eSpace):** стандартный EVM-набор (см. паспорт ETC); проверены
  напрямую 2026-11-11: eth_chainId, eth_getBlockByNumber (генезис/высота),
  eth_feeHistory, eth_gasPrice. Ограничения Confura (по докам): free-тариф —
  50 вызовов/с, 100 000 вызовов/день; `eth_getLogs` — окно ≤ 10 000 блоков;
  расширенный метод `eth_scanLogs` для больших диапазонов.
- **P2P-протокол:** собственный протокол Conflux (tree-graph); кошельком не
  используется.
- **Лёгкий клиент:** нет (для eSpace — доступ через RPC).
- **Узел:** conflux-rust (GPL-3.0, активен; MSRV 1.94) — обслуживает оба
  пространства.
- **Публичные RPC (eSpace):** `https://evm.confluxrpc.org` /
  `https://evm.confluxrpc.com` (провайдер Confura; оба живы, проверены) +
  wss-аналоги (НЕ ПРОВЕРЕНЫ). Это зеркала одного провайдера — единственная
  публичная инфраструктура; допускать пользовательские эндпоинты. Core:
  `https://main.confluxrpc.com` (`cfx_*`).
- **Explorer:** https://evm.confluxscan.org (eSpace mainnet; живость
  web-интерфейса НЕ ПРОВЕРЯЛАСЬ), testnet — testnet.confluxscan.org/espace;
  Core — https://confluxscan.org.
- **Кошельки экосистемы:** Fluent (официальный), MetaMask (eSpace по
  стандартным EVM-механизмам).

## SDK и библиотеки

- **Официальные SDK:** для eSpace не требуются — стандартный EVM-стек. Для
  Core Space — `js-conflux-sdk` (npm 2.7.0; лицензия **LGPL-3.0** по данным
  npm registry) — в начальный охват не входит.
- **Rust-библиотеки:** eSpace — `alloy`/`ethers-rs`, `k256` (MIT OR
  Apache-2.0). Официального Rust-SDK Conflux НЕ ПРОВЕРЕНО (go-conflux-sdk
  существует для Go).
- **Flutter/Dart-интеграции:** те же, что для ETC (см. паспорт ETC).
- **Лицензии зависимостей:** узел conflux-rust — GPL-3.0 (в кошелёк не
  включается); js-conflux-sdk — LGPL-3.0 (при использовании — только как
  динамическая/изолированная зависимость, в начальный охват не входит);
  EVM-стек — MIT OR Apache-2.0. Совместимо с ядром VEYRO (eSpace).

## Совместимость кошелька

Отметка = реализуемо существующими средствами (фактический статус — только
после тестов):

- [x] Создание кошелька — BIP39/BIP32 (путь 60' по практике eSpace)
- [x] Импорт кошелька — фраза / приватный ключ / keystore
- [x] Восстановление — `m/44'/60'` (совместимо с MetaMask/Ledger-ETH-app)
- [x] Получение — `0x` EIP-55; URI `ethereum:0x…@1030`
- [x] Баланс — `eth_getBalance`
- [x] История транзакций — `eth_getLogs` окнами ≤ 10 000 блоков и/или
  `eth_scanLogs` (лимиты эксплорер-API НЕ ПРОВЕРЕНЫ)
- [x] Отправка — legacy (gasPrice = 20 gwei) или EIP-1559, подпись ECDSA
  EIP-155 (chainId 1030), `eth_sendRawTransaction`
- [x] Мониторинг подтверждений — `eth_getTransactionReceipt` + поллинг
- [ ] Core Space (`cfx:`-адреса, `cfx_*` RPC, деривация CIP-37, coin 503) —
  вне начального охвата; отдельная большая работа

## Безопасность и ограничения

- **Два пространства — главный UX-риск:** CFX на Core Space и на eSpace —
  разные адресные модели; пользователь может отправить средства не туда,
  перепутав пространство. UI обязан маркировать «eSpace» явно и валидировать
  адреса (`0x` = eSpace; `cfx:` = Core — не принимать в eSpace-переводы).
- **Лимиты Confura** (50 вызовов/с, 100 000/день на free-тарифе): для
  некастодиального кошелька без собственных серверов при активном опросе
  лимит достижим — реализовать адаптивный поллинг, кэш, пользовательские
  эндпоинты.
- **Единственный публичный провайдер RPC** (Confura, зеркала) — точка
  приватности и отказа.
- **Блокеры:** нет для eSpace; Core Space — отложено (не блокер, а отдельный
  объём работ).

## Вывод для матрицы

- **Идентичность:** подтверждена (eSpace: chainId 1030 — RPC на двух
  зеркалах + chainlist; генезис — RPC; Core: по докам). Тикер однозначен;
  обязательная маркировка пространства.
- **Реализуемость:** полная через eSpace — стандартный EVM-цикл, почти
  нулевые доработки; фиксированный газ 20 gwei упрощает оценку комиссий.
- **Главный риск:** путаница Core/eSpace у пользователей и лимиты публичного
  RPC-провайдера.
- **Предлагаемый статус:** `Research required` → eSpace после тестового
  цикла кандидат на `Full support`; Core Space — вне охвата (не
  поддерживается в MVP). До тестов статус не менять.

## Источники

1. Прямые RPC-проверки 2026-11-11: `https://evm.confluxrpc.org`,
   `https://evm.confluxrpc.com` — eth_chainId (0x406),
   eth_getBlockByNumber (генезис 0xf6cec5af…, высота ~16,1 млн),
   eth_feeHistory/eth_gasPrice (0x4a817c800 = 20 gwei, baseFee постоянен)
2. https://doc.confluxnetwork.org — официальная документация Core Space и
   eSpace: network ID 1029, CIP-37 (base32 `cfx:`), coin type 503, версии
   хардфорков (EIP-2930/1559 после v2.4.0, EIP-7702 после v3.0.0),
   лимиты Confura (50 вызовов/с, 100k/день, getLogs ≤ 10 000, eth_scanLogs),
   CIP-645 (кросс-спейс)
3. https://chainlist.org/chain/1030 — chain ID 1030 eSpace (и 71 testnet)
4. https://github.com/ConfluxChain/conflux-rust — официальный узел (GPL-3.0,
   активен)
5. https://forum.conflux.fun/t/about-ledger-conflux-app-core-space/21188 —
   официальное разъяснение: eSpace полностью совместим с Ethereum, работа
   через приложение Ledger Ethereum (ETH-путь) — подтверждение практики
   деривации eSpace
6. https://github.com/Conflux-Chain/app-conflux — Ledger-приложение Core
   Space (сравнение пространств)
7. https://www.npmjs.com/package/js-conflux-sdk — SDK Core Space (v2.7.0,
   лицензия LGPL-3.0 по данным npm registry)
8. https://github.com/satoshilabs/slips/blob/master/slip-0044.md — SLIP-44:
   coin type 503 (CFX/Core Space); отдельной записи eSpace нет
9. https://evm.confluxscan.org — эксплорер eSpace
10. https://www.coingecko.com/en/coins/conflux-token — цена ≈ $0,041,
    капитализация ≈ $217 млн (2026-11-11)
