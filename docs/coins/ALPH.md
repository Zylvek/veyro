# Технический паспорт монеты: ALPH

> Заполнять только по официальным источникам. Всё недоказанное помечено
> `НЕ ПОДТВЕРЖДЕНО`. Данные актуальны на 11.11.2026, все критические
> параметры подтверждены минимум двумя независимыми источниками.

- **Тикер(ы):** ALPH (пулы используют «ALPH»; официальные имя/тикер —
  Alephium/ALPH по integration-документации). Альтернативных тикеров нет.
- **Официальное название проекта:** Alephium
- **Официальный сайт:** https://alephium.org
- **Официальный репозиторий:** https://github.com/alephium/alephium
  (Scala-узел, референсная реализация)
- **Официальная документация:** https://docs.alephium.org (Address,
  Integration/Exchange, Full node, Public services, Constants, FAQ)
- **Статус исследования:** завершено (реализация не начата)

## Идентификация сети

- **Mainnet:** шардированный BlockDAG **Blockflow** (sUTXO) с PoW **PoLW**
  (Proof of Less Work; хэш блока = `blake3(blake3(serialize(blockHeader)))`,
  nonce 24 байта, chain index закодирован в хэше блока); 100% комиссий
  сжигается. 4 группы × 4 цепи = **16 цепей** (G→G, от `0→0` до `3→3`);
  network-id `0`.
  - **Genesis:** по одному genesis-блоку на каждую из 16 цепей; полный список
    хэшей — в FAQ docs; genesis цепи `0→0`:
    `9de358fd188ce5c2ec7fef45e00974435da7e22992653a7ee828a441634cb950`.
    Genesis timestamp — символический `1231006505000` (03.01.2009, как у
    Bitcoin); фактический запуск mainnet — 08.11.2021.
  - **Время блока:** **8 сек на цепь** (≈2 блока/сек по сети, 172 800
    блоков/день) с апгрейда **Danube** (mainnet 15.07.2025; до этого 16 с
    с Rhône 12.06.2024 и 64 с на старте). Rhône также добавил gasless-режим
    (user-side) и снизил минимальный депозит контракта с 1 до 0.1 ALPH;
    Danube снял потолок эмиссии (до него hardcap 1 млрд ALPH, из них 140 млн
    в genesis) и ввёл groupless-адреса.
  - **Награда:** `min(time-based, hashrate-based)`, на момент проверки
    ≈0.19 ALPH/блок; coinbase-выходы заблокированы **500 минут** (anti-reorg,
    аналог ~1000 минут у Bitcoin).
  - **Порты mainnet:** REST `12973` (Swagger `127.0.0.1:12973/docs`),
    WebSocket `11973` (`/events`; официально «under active development,
    breaking changes might be expected»), mining API `10973` (бинарный
    TCP: `MessageSize(4 байта) + ProtocolVersion(1) + MessageType(1) +
    payload`; push-модель Jobs с 16 шаблонами; только для пулов), P2P
    `9973`. Devnet: REST `22973`, WS `21973`.
- **Testnet:** network-id `1`; **майнинг permissioned** (блоки создают только
  разрешённые адреса; пулы тестируют на локальном testnet из alephium-stack);
  кран https://faucet.testnet.alephium.org (POST `/send`); explorer
  https://testnet.alephium.org. Devnet: network-id `2`.
- **Проверка идентичности:** ALPH = Alephium (официальные name/ticker в
  integration-доке); coin type `1234` зафиксирован в SDK («we always use
  coinType 1234 no matter the network») и в ответе API узлового кошелька;
  пулы выплачивают на нативные P2PKH-адреса `1…`; сайт, GitHub-организация
  и docs cross-link-ят друг друга. Двусмысленности нет.

## Криптография и ключи

- **Формат адреса:** Base58; `address = байт типа || контент-байты`; формат
  **одинаков во всех сетях** (mainnet/testnet/devnet — префикса сети нет).
  6 типов адресов:
  - `0x00` **P2PKH** — хэш публичного ключа (blake2b, 32 байта — поэтому
    адреса длиннее биткоиновских; декодированный адрес обычно 33 байта,
    жёсткого максимума длины нет); в mainnet начинается с `1` (пример:
    `1DrDyTr9RpRsQnDnXo2YRiPzPW4ooHX5LLoqXrqfMrpQH`);
  - `0x01` **P2MPKH** — m-of-n multisig (хэши ключей + порог); с `2`;
  - `0x02` **P2SH** — хэш скрипта;
  - `0x03` **P2C** — контракт (группа контракта закодирована в контенте
    адреса);
  - `0x04` **P2PK groupless** — «безгрупповой» (апгрейд Danube): контент =
    `тип ключа || pubkey || 4-байтовая djb2-чексумма || группа`; помимо
    secp256k1 поддерживает типы ключей `0x01` secp256r1, `0x02` Ed25519,
    `0x03` WebAuthn (PassKey);
  - `0x05` **P2HMPK** — groupless multisig: контент =
    `blake2b(0x05 || pubkeys || порог) || djb2-чексумма || группа`.
  Группа адреса детерминированно вычисляется из самого адреса.
  Санити-регулярка из docs: `^[1-9A-HJ-NP-Za-km-z]+(?:\:[0-9])?$`.
  Groupless-адрес на уровне приложения показывает суммарный баланс
  сгруппированных адресов и сам выбирает underlying-адрес для перевода.
- **Формат публичного ключа:** secp256k1, сжатый (33 байта; пример:
  `0381818e63bd9e35a5489b52a430accefc608fd60aa2c7c0d1b393b5239aedf6b0`).
  Кривая та же, что у Bitcoin; хэширование blake2b (не sha256/ripemd160).
- **Формат приватного ключа:** BIP32; узловой кошелёк хранит секрет
  зашифрованным; в модели VEYRO ключи локальные, узел — только данные
  и бродкаст.
- **Схема деривации ключей:** BIP32/BIP44, coin type `1234`; стандартный
  адрес — `m/44'/1234'/0'/0/0` (путь возвращается API узлового кошелька);
  уровень `account'` занят типом ключа: `0` default/secp256k1, `1`
  bip340-schnorr, `2` gl-secp256k1, `3` gl-secp256r1, `4` gl-ed25519, `5`
  gl-webauthn. Адреса разных групп получаются перебором индексов
  (`deriveHDWalletPrivateKeyForGroup` в SDK) — фиксированный index не
  гарантирует нужную группу.
- **Мнемонический стандарт:** BIP39, по умолчанию **24 слова** (256 бит
  энтропии; 12 слов — опция SDK); поддерживается опциональный
  BIP39-passphrase.
- **Алгоритм подписи:** стандартный P2PKH-анлок — **ECDSA над secp256k1**:
  компактная подпись `r‖s` (64 байта) с **low-S нормализацией**; подпись
  вычисляется по `txId`. Подтверждено независимо: `utils.ts` официального
  SDK (`normalizeS()`, отказ при high-S) и эндпоинт узла
  `POST /utils/verify-signature` («Verify the SecP256K1 signature»).
  **Schnorr BIP-340** — опционально: AssetScript `Schnorr(publicKey)` с
  `verifyBIP340Schnorr!` (введён апгрейдом Leman 03.2023; сценарии типа
  Nostr) и отдельный keyType в SDK. Подпись сообщений — с префиксом
  `Alephium signed message: `.
- **Совместимость восстановления из фразы:** BIP39 (24 слова) + путь
  `m/44'/1234'/0'/0/0` даёт одни и те же адреса в официальных кошельках и
  узле (тест-вектор exchange-дока: опубликованная 24-словная фраза → адрес
  `1DrDy…MrpQH`, pubkey `0381818e…`, group 0). Аудиты крипто-стека —
  НЕ ПОДТВЕРЖДЕНО.

## Транзакции

- **Структура транзакции:** sUTXO: inputs (outpoint + unlock-скрипт +
  подписи) и outputs (attoAlphAmount, address, tokens, lockTime,
  message-байты). Единица: 1 ALPH = 10^18 **attoALPH** (precision 1e-18).
  Поток: `POST /transactions/build` (fromPublicKey, destinations) →
  подписание офлайн (ECDSA по txId) → `POST /transactions/submit`;
  статус: `GET /transactions/status?txId` (Confirmed, blockHash,
  chainConfirmations, fromGroupConfirmations, toGroupConfirmations).
- **Расчёт комиссии:** модель **газа**: мин. газ **20 000**, мин. gas price
  **1e-7 ALPH** (1e11 atto), мин. комиссия **0.002 ALPH**, макс. газ
  **5 000 000** на tx (10 000 000 на блок, ≤500 tx/блок). Формула
  simple-transfer: `2000×inputs + 4500×outputs + 1000 + 2060 (p2pk
  unlock)`, gas = max(20 000, расчёт).
- **Dust/резервирование:** каждый выход/UTXO ≥ **0.001 ALPH**; не более
  **1 токена** на asset-UTXO (токен-выходы — отдельные UTXO со своим
  dust); контрактный UTXO ≥ **0.1 ALPH**.
- **Правило шардинга:** все входы tx — из одной группы, все адресаты — из
  одной (перевод между группами допустим в одной tx: fromGroup→toGroup);
  groupless-адреса снимают это ограничение на уровне приложения.
- **Mempool/UTXO-гигиена:** неподтверждённая tx удаляется из мемпула через
  **2 часа** (`alephium.mempool.unconfirmed-tx-expiry-duration`); из-за
  лимита inputs на tx кошельки майнинг-выплат обязаны **консолидировать**
  мелкие UTXO — эндпоинт `POST /transactions/sweep-address/build`
  (узел ≥ 2.3.0), в узловом кошельке `sweep-active-address` /
  `sweep-all-addresses`.
- **Блокировки/имматурность:** coinbase-выходы (награда за блок и
  uncle-награды: ≤2 ghost-uncles на блок, референс в диапазоне высот
  [h+1, h+7]) заблокированы **500 минут**. Выплаты пула приходят обычными
  транзакциями из зрелых UTXO пула — на получателя блокировка
  не действует.
- **Модель баланса:** UTXO (sUTXO), шардированная по группам;
  «подтверждения» считаются по цепи (chainConfirmations и групповые
  варианты из `/transactions/status`). Reorg-модель: защита
  Ravencoin-style при реоргах > 100 блоков, максимум реорга 200 блоков;
  рекомендация docs — ждать ~110 подтверждений (биржи по FAQ — 30–110).
- **Особые поля:** memo/payment ID — **нет** (integration-док: «No»);
  у выходов есть опциональный lockTime; URI-схема платежей (`alephium:`) —
  НЕ ПОДТВЕРЖДЕНО.

## Доступ к сети

- **Методы RPC:** REST API узла (mainnet/testnet `12973`, devnet `22973`;
  Swagger `/docs`, OpenAPI-файл в репозитории). Кошельковый набор:
  `GET /infos`, `GET /addresses/{address}/balance`,
  `GET /addresses/{address}/utxos`, `POST /transactions/build`,
  `POST /transactions/submit`, `GET /transactions/status`,
  `GET /transactions/details/{txId}`, mempool-эндпоинты, `/blockflow/*`
  (blocks, chain-info, hashes). Узловой кошелёк (опция для пользователя,
  поднявшего свой узел): `POST /wallets` (создание, возвращает 24-словную
  мнемонику), `PUT /wallets` (восстановление),
  `POST /wallets/{name}/unlock`, `GET /wallets/{name}/addresses`,
  `POST /wallets/{name}/sign`, transfer/sweep-эндпоинты. В модели VEYRO
  подпись локальная; узловые wallet-эндпоинты не используются.
- **WebSocket:** порт `11973`, путь `/events` (метод `block_notify` —
  стрим блоков целиком; предупреждение docs: «under active development,
  breaking changes might be expected»). Для мониторинга надёжнее
  REST-поллинг.
- **P2P-протокол:** порт `9973`; для кошелька не используется (поверхность
  узлов и пулов).
- **Лёгкий клиент:** SPV-клиента нет; «лёгкий» режим = локальная подпись +
  REST к узлу (публичному или своему).
- **Узел:** Scala/JVM, Java **11 или 17**; актуальная ветка **v4.x**
  (требование Danube); дистрибутив — jar из GitHub Releases или Docker
  (alephium-stack). БД mainnet ~**95 ГБ** (pruned ~**25 ГБ**); полная
  синхронизация до ~20 часов; снапшоты — https://archives.alephium.org.
  На mainnet узел работает с одним брокером (`broker-num = 1`). Для
  публичного узла включать `alephium.api.api-key` (32+ символа).
- **Публичные RPC:** официальные (все rate-limited — кэшировать и
  ретраить): `https://node.mainnet.alephium.org` и
  `https://node.testnet.alephium.org` (node v4.X),
  `https://backend.mainnet.alephium.org` и
  `https://backend.testnet.alephium.org` (explorer-backend v3.X).
  Комьюнити: AlphScan `node.mainnet.alphscan.io` /
  `backend.mainnet.alphscan.io` (load balancers с failover); Flux.
  **Приватность:** публичные API видят адреса пользователя; для
  production — свой узел и свой explorer-backend.
- **Explorer:** https://explorer.alephium.org (mainnet),
  https://testnet.alephium.org (testnet). **История по адресу узлом не
  даётся** — два официальных пути: (1) свой **explorer-backend** (Java 11/17
  + PostgreSQL + полный узел; порт `9090`, Swagger `/docs`; обслуживает
  официальный explorer и официальные кошельки; эндпоинты
  `/addresses/{address}/transactions`, `/transactions/{hash}` и др.),
  (2) собственная БД, пополняемая при депозитах. Снапшот БД
  explorer-backend — тоже на archives.alephium.org.

## SDK и библиотеки

- **Официальные SDK:**
  - **TypeScript (монорепозиторий alephium-web3, лицензия LGPL-3.0):**
    `@alephium/web3` (NodeProvider/ExplorerProvider, сгенерированные типы
    API узла и explorer-backend, адресные утилиты, TransactionBuilder),
    `@alephium/web3-wallet` (HD-кошелёк, PrivateKeyWallet, деривация),
    `@alephium/cli`, `@alephium/web3-test`, `@alephium/web3-react`,
    `@alephium/get-extension-wallet`, `@alephium/walletconnect`;
    депозит-хелперы `getALPHDepositInfo` / `getDepositInfo` /
    `getSenderAddress`. Для Danube требуется ветка 2.x (1.x на поддержке).
  - **Go:** github.com/alephium/go-sdk (генерированные клиенты API узла).
- **Rust-библиотеки:** официального общего Rust SDK **нет**.
  `ledger-alephium` — Rust, LGPL-3.0 (код апплета Ledger, не библиотека для
  кошельков). Крейт `alephium-web3` на crates.io (v2.0.7, публикатор —
  стороннее лицо, ~десятки загрузок, лицензия **GPL-3.0-or-later`) —
  **не пригоден** ни по лицензии, ни по зрелости. Итог: собственная
  реализация в Rust-ядре VEYRO — BIP39/BIP32, secp256k1-ECDSA (low-S),
  blake2b, кодирование адресов, сериализация tx по openapi-спецификации.
  Аудиты — НЕ ПОДТВЕРЖДЕНО.
- **Flutter/Dart-интеграции:** официального Dart SDK нет; маршрут VEYRO —
  криптопримитивы в Rust-ядре (FFI) + тонкий REST-клиент на Dart.
- **Лицензии зависимостей (совместимость с MIT OR Apache-2.0):** узел
  alephium — **LGPL-3.0** (файл LICENSE), explorer-backend — **LGPL-3.0**,
  TS SDK — **LGPL-3.0** (заголовки исходников), ledger-alephium —
  **LGPL-3.0**; официальные кошельки (монорепозиторий alephium-frontend) —
  GPL-семейство (точная лицензия — НЕ ПОДТВЕРЖДЕНО, проверить при
  интеграции). **Вывод:** ни один компонент нельзя встраивать/вендорить в
  ядро VEYRO; допустимо только **запускать** узел и explorer-backend как
  отдельные сервисы и интегрироваться по REST, реализуя клиента самим.

## Совместимость кошелька

Реализуемость полного цикла **без серверов VEYRO** (пометки — технический
маршрут; ничего не считается поддержанным до тестов):

- [ ] Создание кошелька — локально: BIP39 (24 слова) + собственная
      BIP32-деривация в Rust-ядре
- [ ] Импорт кошелька — BIP39-фраза (+passphrase) / BIP32-ключ, локально
- [ ] Восстановление — `m/44'/1234'/0'/0/0` (keyType 0) в Rust-ядре;
      группа адреса вычисляется локально
- [ ] Получение (адрес/QR/URI) — Base58 P2PKH `1…` + QR; URI —
      НЕ ПОДТВЕРЖДЕНО; groupless-адреса — отдельное решение после MVP
- [ ] Баланс — `GET /addresses/{address}/balance` + `/utxos` (официальный
      публичный узел на старте; свой узел для production)
- [ ] История транзакций — explorer-backend API (официальный публичный на
      старте; свой backend для приватности) либо своя БД депозитов
- [ ] Отправка — `POST /transactions/build` → локальная подпись ECDSA
      (txId, low-S) → `POST /transactions/submit`; комиссия ≥ 0.002 ALPH
- [ ] Мониторинг подтверждений — `GET /transactions/status`
      (chain/fromGroup/toGroup confirmations); при 8 с/блок цикл быстрый;
      для крупных сумм — ~110 подтверждений; WS `/events` — опционально
      (нестабилен)

## Безопасность и ограничения

- **Известные ограничения:** адресная история недоступна через узел — нужен
  explorer-backend (свой или официальный rate-limited) или локальный индекс;
  официального Rust SDK нет (экосистема LGPL/GPL); WS-стриминг в активной
  разработке; публичные API с rate limits.
- **Риски безопасности:** (1) собственная реализация подписи/сериализации
  (ECDSA low-S, blake2b, группы адресов) — паритет с Scala-узлом нужно
  доказать тестами на devnet/testnet; (2) фрагментация UTXO при частых
  мелких выплатах пула — лимит inputs на tx, обязательная консолидация
  (sweep) в UX и её комиссионная стоимость; (3) групповая модель — при
  отправке из разных групп нужны цепочки транзакций (или groupless-адреса,
  что усложняет валидацию и индексацию); (4) mempool expiry 2 ч —
  неподтверждённые tx выпадают, нужен реброадкаст; (5) зависимость от
  официальных публичных сервисов при отказе от своей инфраструктуры
  (приватность + rate limits); (6) Danube-эра — поддержка новых типов
  адресов в валидации (groupless, regex).
- **Блокеры:** жёстких **нет**. Полный цикл реализуем без серверов VEYRO
  (локальная подпись + REST); но интеграционная стоимость — наивысшая из
  трёх исследованных активов: официальный стек TS-only и LGPL, всё
  критичное пишем сами на Rust и проверяем против узла.

## Вывод и предлагаемый статус в матрице

- **Идентичность:** подтверждена (ALPH = Alephium; coin type 1234;
  16 genesis-хэшей опубликованы в FAQ docs; genesis цепи `0→0` =
  `9de358fd…4cb950`).
- **Полный цикл без серверов VEYRO:** да — локальная подпись ECDSA +
  официальные публичные node/explorer-backend API с первого дня; для
  приватности и надёжности — собственный узел + собственный
  explorer-backend (Java + PostgreSQL).
- **Наибольший риск:** отсутствие официального Rust SDK и LGPL-3.0 во всей
  экосистеме → собственная REST-интеграция и реализация ECDSA/blake2b/
  сериализации; корректность доказывается только тестами против узла.
- **Предлагаемый статус:** до тестов — Research required; после полного
  тестового цикла (`docs/COIN_COMPATIBILITY.md`) — **условный** кандидат
  на Full support (инженерный профиль затрат выше, чем у KAS/ERG).
  Промежуточно: Watch-only → Receive supported → Send supported.
- Для майнинг-выплат: пулы платят обычными транзакциями на единый
  payout-адрес P2PKH `1…`; 500-минутная блокировка coinbase — на стороне
  пула, получателя не касается; главный операционный вопрос — консолидация
  мелких UTXO (dust 0.001 ALPH) и групповая адресация.

## Источники

1. https://docs.alephium.org/dapps/concepts/address — 6 типов адресов (0x00–0x05), Base58, `type || content`, djb2-чексумма, типы ключей P2PK (secp256k1/secp256r1/Ed25519/WebAuthn), groupless-модель, одинаковость формата сетей
2. https://docs.alephium.org/frequently-asked-questions — Genesis Blocks (16 хэшей; `0→0` = 9de358fd…), genesis timestamp 03.01.2009 / запуск 08.11.2021, secp256k1 + blake2b (32-байтный хэш), блок 8 с, lock 500 минут, Rhône (gasless, депозит 1→0.1 ALPH)
3. https://docs.alephium.org/integration/exchange — тест-кошелёк (24 слова → адрес `1DrDy…`, pubkey `0381818e…`, group 0, path `m/44'/1234'/0'/0/0`), build/sign/submit, `/transactions/status`, sweep-address, формула газа, правила шардинга, UTXO-менеджмент
4. https://docs.alephium.org/integration/integration-more — БД 95 ГБ / pruned 25 ГБ, mempool 2 ч, dust 0.001 ALPH, precision 1e-18, memo «No», история через explorer-backend или свою БД, Ravencoin-style защита при реоргах >100, ~110 подтверждений, адрес ~33 байта
5. https://docs.alephium.org/integration/danube-upgrade — Danube mainnet 15.07.2025, блок 16→8 с, узел 4.x, TS SDK 2.x, новые типы адресов, regex
6. https://docs.alephium.org/dapps/constants — газ (min 20 000 / price 1e-7 ALPH / fee 0.002 ALPH / max 5 000 000), dust, контрактный депозит 0.1 ALPH, ≤500 tx/блок
7. https://docs.alephium.org/infrastructure/public-services — официальные node/backend API (v4.X / v3.X), rate limits, алиасы (explorer.alephium.org, testnet.alephium.org), faucet, AlphScan, Flux
8. https://docs.alephium.org/infrastructure/explorer-backend — Java 11/17 + PostgreSQL + полный узел, порт 9090, снапшоты archives.alephium.org
9. https://docs.alephium.org/full-node/getting-started и https://docs.alephium.org/full-node/config — Java 11/17, Docker, network-id 0/1/2, testnet permissioned, Swagger `127.0.0.1:12973/docs`, api.api-key (32+), P2P 9973
10. https://docs.alephium.org/integration/mining — mining API `localhost:10973`, бинарный формат сообщений, `blake3(blake3(…))`, nonce 24 байта, ghost-uncles, sweep-эндпоинты узлового кошелька
11. https://docs.alephium.org/sdk/block — WebSocket `/events` (`block_notify`; пример devnet `ws://127.0.0.1:21973/events`; mainnet по умолчанию 11973), предупреждение о нестабильности
12. https://docs.alephium.org/dapps/concepts/programming-model — AssetScript `Schnorr(publicKey)`, `verifyBIP340Schnorr!`
13. https://alephium.org/news/post/the-leman-network-upgrade-is-live-f52c89b7dd6a — Schnorr-поддержка (Leman, 03.2023); https://alephium.org/news/post/alephium-block-rewards-72d9fb9fde33 — награды, lock 500 минут, PoLW
14. https://github.com/alephium/alephium — LICENSE (LGPL-3.0), openapi.json, исходники (ALPH.scala, BlockHeader.scala)
15. https://github.com/alephium/alephium-web3 — hd-wallet.ts (coinType 1234, keyType-пути), utils.ts (ECDSA, `normalizeS`), LGPL-заголовки файлов
16. https://github.com/alephium/explorer-backend и https://github.com/alephium/ledger-alephium — LICENSE (LGPL-3.0)
17. https://crates.io/crates/alephium-web3 — сторонний крейт v2.0.7, GPL-3.0-or-later, публикатор не Alephium
18. https://explorer.alephium.org, https://testnet.alephium.org — explorers; https://node.mainnet.alephium.org/docs — Swagger публичного узла
