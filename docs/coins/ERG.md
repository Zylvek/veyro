# Технический паспорт монеты: ERG

> Заполнять только по официальным источникам. Всё недоказанное помечено
> `НЕ ПОДТВЕРЖДЕНО`. Данные актуальны на 11.11.2026, критические параметры
> подтверждены минимум двумя независимыми источниками.

- **Тикер(ы):** ERG (пулы используют «ERG»). Альтернативных тикеров нет.
- **Официальное название проекта:** Ergo
- **Официальный сайт:** https://ergoplatform.org
- **Официальный репозиторий:** узел — https://github.com/ergoplatform/ergo
  (Scala, референс-клиент); криптобиблиотека —
  https://github.com/ergoplatform/sigma-rust (`ergo-lib`, Rust)
- **Официальная документация:** https://docs.ergoplatform.com
- **Статус исследования:** завершено (реализация не начата)

## Идентификация сети

- **Mainnet:** eUTXO-блокчейн, PoW **Autolykos2**, блоки ~120 сек (≈720
  блоков/день); все 97 739 924 ERG созданы в genesis-блоке и выпускаются по
  фиксированному графику (текущий базовый reward — 3 ERG/блок с ~03.04.2026
  по официальному графику: 21→18→15→12→9→6→3; дополнительно майнеры получают
  комиссии и storage rent).
  - **genesisId:** `b0244dfc267baca974a4caee06120321562784303a8a688976ae56170e4d175b`
    — задан в `src/main/resources/mainnet.conf` («Other genesis blocks will be
    considered invalid»); подтверждён независимо API explorer: первый блок
    сети (height 1, parentId `000…000`, timestamp `1561978977137` =
    2019-07-01) имеет именно этот ID.
  - magic bytes P2P: `[1, 0, 2, 4]`; addressPrefix `0`; protocolVersion `4`
    (эра интерпретатора 6.0; узлы голосуют за soft-fork 6.0 — «120 = 1» в
    mainnet.conf); initialDifficultyHex `011765000000`; genesis state digest
    `a5df145d41ab15a01e0cd3ffbab046f0d029e5412293072ad0f5827428589b9302`;
    checkpoint: height `1231454`, blockId `ca5aa96a2d560f49cd5652eae4b9e16bbf410ee32365313dc16544ee5fda1e6d`.
  - Порты mainnet: REST API `9053` (чувствительные вызовы защищаются
    `apiKeyHash`), P2P `9030`; seed-пиры перечислены в mainnet.conf
    (в т.ч. `213.239.193.208:9030`).
- **Testnet:** публичный тестнет существует: addressPrefix `16` (0x10),
  magicBytes `[2, 2, 2, 2]`, REST `9052`, P2P `9020`, интервал блоков 2 мин,
  genesis state digest `cb63aa99a3060f341781d8662b58bf18b9ad258db4fe88d09f8f71cb668cad4502`
  (`src/test/resources/application.conf` / testnet-конфиг узла). Explorer:
  https://testnet.ergoplatform.com. Публичный кран для testnet-ERG —
  НЕ ПОДТВЕРЖДЕНО (токены добываются/выдаются сообществом).
- **Проверка идентичности:** ERG = Ergo, coin type SLIP-44 `429` (EIP-0003);
  пулы выплачивают на P2PK-адреса Ergo (начинаются с `9`); genesisId выше
  жёстко привязывает узел к правильной цепочке. Двусмысленности нет.

## Криптография и ключи

- **Формат адреса:** Base58 (не Bech32). Байт-префикс = тип сети
  (`0x00` mainnet / `0x10` testnet) + тип адреса:
  - `0x01` **P2PK** — контент: сжатый публичный ключ; **в mainnet всегда
    начинается с `9`** (пример:
    `9fRAWhdxEsTcdb8PhGNrZfwqa65zfkuYHAMmkQLcic1gdLSV5vA`); в testnet — с `3`;
  - `0x02` **P2SH** — контент: первые 192 бита blake2b256 хэша сериализованного
    скрипта; начинается с `8`;
  - `0x03` **P2S** — контент: сериализованный скрипт (сюда идут майнерские
    награды); может начинаться с любого символа Base58.
  Чексумма = первые 4 байта `blake2b256(prefix || content)`;
  адрес = `prefix || content || checksum`.
- **Формат публичного ключа:** secp256k1, сжатый (33 байта).
- **Формат приватного ключа:** BIP32-расширенный; узел хранит секрет
  зашифрованным (`ergo.wallet.secretStorage.secretDir`) и старается вычищать
  ключ из памяти; для VEYRO ключи локальные (sigma-rust), узел используется
  только для данных и бродкаста.
- **Схема деривации ключей:** BIP32/BIP44, coin type `429` (EIP-0003):
  `m/44'/429'/account'/chain/index`; стандартный приёмный —
  `m/44'/429'/0'/0/0`, change — `m/44'/429'/0'/1/0`.
- **Мнемонический стандарт:** BIP39; допустимы 12/15/18/21/24 слова
  (128–256 бит энтропии; параметр узла `seedStrengthBits`); де-факто стандарт
  кошельков Ergo — **15 слов** (использовался Yoroi; узел по умолчанию
  генерирует 160-битную мнемонику); языки: english, chinese_simplified/
  traditional, french, italian, japanese, korean, spanish. Поддерживается
  опциональный BIP39-passphrase (`mnemonicPass` в API узла).
- **Алгоритм подписи:** траты — **Sigma-протоколы** (неинтерактивные
  доказательства поверх secp256k1; стандартный P2PK — `proveDlog`,
  фактически подпись Шнорра с Fiat–Shamir от blake2b256-хэша транзакции).
  Аудитов sigma-rust сторонними фирмами — НЕ ПОДТВЕРЖДЕНО.
- **Совместимость восстановления из фразы:** BIP39 + путь `m/44'/429'`
  восстанавливает адреса во всех актуальных кошельках (Nautilus, Satergo,
  Terminus, узел). Известные несовместимости: (1) **bug деривации BIP32 в
  части кошельков, созданных до 18.10.2022** (официальный чекер satergo.com);
  (2) Yoroi прекратил поддержку ERG (август 2025) — восстановление 15-словной
  фразой через Nautilus и др.; (3) узел использует «secret root key» для
  change-адресов — при глубокой деривации адресов нужно выводить дополнительные
  индексы вручную.

## Транзакции

- **Структура транзакции:** eUTXO-«боксы»: транзакция = inputs (boxId +
  proof) + dataInputs + outputs (боксы: value, ergoTree, tokens, регистры
  R0–R9, creationHeight). Единица: 1 ERG = 10^9 **nanoERG**.
- **Расчёт комиссии:** комиссия — **явный выходной бокс** на пропозицию
  майнера; минимальная комиссия мемпула `minimalFeeAmount` = 1 000 000
  nanoERG (**0.001 ERG**); дефолт кошелька `defaultTransactionFee` =
  1 000 000 nanoERG; максимальная стоимость транзакции `maxTransactionCost`
  = 4 900 000. Минимальная стоимость бокса ≈ 360 nanoERG за байт ergoTree.
- **Блокировки/имматурность:** награда за блок приходит в P2S-бокс
  («this is where mining rewards go» — docs). Immaturity coinbase —
  **НЕ ПОДТВЕРЖДЕНО** (предположительно 720 блоков, требуется второй
  источник). Для приёма выплат пула некритично: пулы платят обычными
  транзакциями из зрелых боксов.
- **Storage rent:** бокс, не тронутый ~4 года, может быть собран любым
  (комиссия ≈ 0.13 ERG за 4-летний период); на mainnet `rejectStorageRentTxs
  = true` — rent-транзакции не релеятся, майнеры собирают rent в шаблонах
  блоков. **Важно для майнинг-кошелька:** долгое накопление мелких выплат
  без движения средств делает боксы потенциально collectible.
- **Модель баланса:** eUTXO (боксы), баланс = сумма несspent-боксов по адресам
  (+ unconfirmed из мемпула).
- **Особые поля:** payment ID / memo в базовом протоколе нет; данные
  помещаются в регистры/токены; URI-схема для платежей — НЕ ПОДТВЕРЖДЕНО
  (QR с адресом подтверждён).

## Доступ к сети

- **Методы RPC:** REST API узла (mainnet 9053 / testnet 9052), OpenAPI/Swagger.
  Кошелько-критичный набор:
  - создание/восстановление узлового кошелька: `POST /wallet/init`,
    `POST /wallet/restore`, `POST /wallet/unlock`, `GET /wallet/status`,
    `GET /wallet/deriveNextKey` (в модели VEYRO — только если пользователь
    сам поднимает узел-кошелёк; подпись по умолчанию локальная через
    sigma-rust);
  - сеть/данные: `GET /info`, `GET /blockchain/box/byId/{id}`,
    `GET /blockchain/box/byAddress/{address}`,
    `GET /blockchain/box/byAddress/{address}/unspent`,
    `GET /blockchain/transaction/byId/{txId}`,
    `GET /blockchain/block/header/byId/{id}`, `GET /network/peers`,
    mempool-эндпоинты;
  - отправка: `POST /transactions/send` (бродкаст), `POST /transactions/sign`
    (HSM-style подпись узлом).
  Для адресной истории/box-tracking на собственном узле нужен
  **extraIndex** (индексация боксов по адресу/высоте/txId — конфиг узла).
- **P2P-протокол:** scorex P2P, порт `9030` (mainnet) / `9020` (testnet);
  magicBytes см. выше; для кошелька не используется.
- **Лёгкий клиент:** полноценного SPV нет. Есть: (1) bootstrap узла по
  NiPoPoW (`nipopowBootstrap`) и по снапшоту UTXO-множества
  (`utxoBootstrap`) — ускорение синхронизации собственного узла; (2)
  исследования «asymmetric stateless clients» — для кошелька неприменимо.
  Итог: кошелёк = локальная подпись (sigma-rust) + REST узла или explorer-API.
- **Узел:** ergo 6.0.x (протокол 4; актуальная линейка 6.0.8), Scala/JVM;
  JDK ≥ 9, ориентир ~4–6 ГБ RAM, ~100 ГБ диск (+накладные extraIndex);
  genesis-bootstrap или UTXO-snapshot; seed-пиры в mainnet.conf.
- **Публичные RPC:** публичных официальных узлов нет; комьюнити-узел
  `213.239.193.208:9053` (seed-пир; REST без гарантий) использовался
  сторонними приложениями. Публичные explorer-API:
  https://api.ergoplatform.com (REST v1, rate-limited). **Приватность:**
  публичные узлы/explorers видят адреса; для production — собственный узел
  с extraIndex (и при необходимости собственный explorer-backend).
- **Explorer:** https://explorer.ergoplatform.com (mainnet),
  https://testnet.ergoplatform.com (testnet), ergexplorer.com,
  sigmaspace.io (GraphQL) — для ссылок из истории транзакций.

## SDK и библиотеки

- **Официальные SDK:** **sigma-rust / ergo-lib** (Rust, CC0-1.0) — активен:
  последний опубликованный тег ergo-lib v0.28.0, v0.29.0 подготовлен (на
  сентябрь 2026 не опубликован), коммиты продолжаются (ноябрь 2026).
  Привязки: WASM/JS/TS (`ergo-lib-wasm`), Python, JVM/JNI (Android),
  iOS/Swift. JVM-стек: Ergo Appkit (Scala/Java).
- **Rust-библиотеки:** ergo-lib — эталонная (её используют официальные
  кошельки), идеально подходит для Rust-ядра VEYRO; звёздность/активность
  высокие (организация ergoplatform); лицензия CC0-1.0 (public domain
  equivalent); аудиты — НЕ ПОДТВЕРЖДЕНО.
- **Flutter/Dart-интеграции:** официального Dart SDK нет; рекомендация —
  FFI на ergo-lib (тот же Rust-контракт, что у официальных мобильных
  привязок) + REST для сетевого слоя.
- **Лицензии зависимостей (совместимость с MIT OR Apache-2.0):** узел
  ergo — **CC0-1.0**; sigma-rust — **CC0-1.0**. CC0 лишён обязательств
  attribution/copyleft → **совместимо** с политикой VEYRO. Зависимости
  sigma-rust (bip32, secp256k1-обёртки, blake2) — типовые MIT/Apache-2.0.

## Совместимость кошелька

Реализуемость полного цикла **без серверов VEYRO** (пометки — технический
маршрут; ничего не считается поддержанным до тестов):

- [ ] Создание кошелька — локально: BIP39 + ergo-lib (Rust-FFI)
- [ ] Импорт кошелька — BIP39-фраза / расширенный ключ, локально
- [ ] Восстановление — `m/44'/429'/0'/0/0` через ergo-lib; учёт легаси-bug
      деривации до 18.10.2022 (информировать пользователя)
- [ ] Получение (адрес/QR/URI) — Base58 P2PK `9…` + QR; URI — НЕ ПОДТВЕРЖДЕНО
- [ ] Баланс — сумма unspent-боксов: `GET /blockchain/box/byAddress/…/unspent`
      на своём узле (extraIndex) или explorer-API
- [ ] История транзакций — box-tracking на своём indexed-узле; explorer-API
      (api.ergoplatform.com) как внешний fallback
- [ ] Отправка — построение tx в ergo-lib (fee-бокс 0.001 ERG), локальная
      подпись Sigma-proof, `POST /transactions/send` на узел
- [ ] Мониторинг подтверждений — высота включения + confirmations из API
      узла/explorer; при ~2 мин/блоке порог 10–12 подтверждений

## Безопасность и ограничения

- **Известные ограничения:** история по адресам требует indexed-узла
  (extraIndex) либо внешнего explorer-API; публичных официальных RPC нет;
  узел тяжеловат (JVM, ~100 ГБ).
- **Риски безопасности:** (1) **storage rent** — накопленные выплаты, не
  тронутые ~4 года, могут быть собраны третьими лицами (в UX майнинг-кошелька
  предусмотреть консолидацию/предупреждение); (2) расхождение
  реализаций sigma-rust ↔ Scala-узел на edge-кейсах (сериализация, token
  burning checks) — использовать только актуальный ergo-lib и тестировать на
  testnet; (3) зависимость от внешних explorer-API при отказе от своего узла
  (приватность + доступность); (4) лёгкая DoS-поверхность REST без apiKey
  (всегда включать `apiKeyHash` на своём узле).
- **Блокеры:** **нет**. Полный цикл реализуем на клиенте (ergo-lib) + узел
  пользователя (или комьюнити-узел/explorer-API на старте).

## Вывод и предлагаемый статус в матрице

- **Идентичность:** подтверждена (ERG = Ergo, coin type 429, genesisId
  зафиксирован в mainnet.conf и подтверждён explorer-API).
- **Полный цикл без серверов VEYRO:** да — локальная подпись sigma-rust +
  собственный узел с extraIndex (комьюнити-узел/explorer-API только как
  временный fallback).
- **Наибольший риск:** доступ к адресной истории без собственного
  indexed-узла (публичной официальной инфраструктуры нет) + паритет
  sigma-rust/Scala-узел.
- **Предлагаемый статус:** до тестов — Research required; после полного
  тестового цикла — кандидат на **Full support**. Промежуточно: Receive
  supported → Send supported. Rust-ядро VEYRO может опираться напрямую на
  ergo-lib (CC0) — лучший интеграционный профиль из трёх исследованных.
- Для майнинг-выплат: пулы (PPLNS/PPS, min payout 1 ERG) платят обычными
  транзакциями на P2PK `9…`; учёт storage rent для «спящих» балансов.

## Источники

1. https://github.com/ergoplatform/ergo/blob/master/src/main/resources/mainnet.conf — genesisId `b0244dfc…d175b`, protocolVersion 4, magicBytes [1,0,2,4], порты 9030/9053, minimalFee/maxTransactionCost/rejectStorageRentTxs, seed-пиры
2. https://api.ergoplatform.com/api/v1/blocks/b0244dfc267baca974a4caee06120321562784303a8a688976ae56170e4d175b — первый блок (height 1, parentId 000…000, timestamp 1561978977137) — второе независимое подтверждение genesisId
3. https://docs.ergoplatform.com/dev/wallet/address/address_types — типы адресов 0x01/0x02/0x03, префиксы 9/8/P2S, чексумма blake2b256, примеры mainnet/testnet
4. https://docs.ergoplatform.com/node/wallet-setup и https://ergoplatform.org/en/blog/2019_06_04_wallet-documentation — BIP39/BIP32, длины 12–24 слова, seedStrengthBits, /wallet/init, /wallet/restore, mnemonicPass
5. https://docs.ergoplatform.com/tutorials/access-issues — bug деривации BIP32 до 18.10.2022, checker satergo.com
6. https://github.com/ergoplatform/ergo — README (CC0-1.0, bootstrap UTXO-snapshot/NiPoPoW, требования, предупреждения безопасности), лицензия репозитория
7. https://github.com/ergoplatform/sigma-rust — ergo-lib (CC0-1.0), теги v0.28.0/v0.29.0, активность
8. https://ergoplatform.org/en/blog/Ergo-Block-Reward-Drops-to-9-ERG — график эмиссии (9 ERG 04.10.2025 → 6 ERG 03.01.2026 → 3 ERG 03.04.2026), интервал 120 сек
9. https://explorer.ergoplatform.com, https://testnet.ergoplatform.com, https://ergexplorer.com, sigmaspace.io — explorers; параметры testnet — testnet-конфиг узла (prefix 16, magicBytes [2,2,2,2], порты 9020/9052)
10. https://help.yoroi-wallet.com/en/article/how-to-access-my-ergo-wallet-15qpo6p — sunset ERG в Yoroi, 15-словное восстановление через Nautilus
