# Технический паспорт монеты: XMR

- **Тикер(ы):** XMR (пулы/биржи альтернативных обозначений не используют)
- **Официальное название проекта:** Monero
- **Официальный сайт:** https://www.getmonero.org
- **Официальный репозиторий:** https://github.com/monero-project/monero
- **Официальная документация:** https://www.getmonero.org/resources/developer-guides/
  (wallet RPC: https://www.getmonero.org/resources/developer-guides/wallet-rpc/)
- **Статус исследования:** завершено

## Идентификация сети

- **Mainnet:** CryptoNote-сеть Monero. Критические параметры заданы в
  `src/cryptonote_config.h` и проверены по исходникам (2 независимых
  подтверждения: исходники + документация):
  - network byte: 18 — стандартный адрес (Base58, начинается с «4»),
    19 — integrated-адрес (тоже начинается с «4»), 42 — subaddress («8»);
  - порты: P2P 18080, unrestricted RPC 18081, restricted RPC 18089
    (типичный порт публичных узлов);
  - эмиссия: tail emission — фиксированные 0.6 XMR за блок (с 2022).
- **Testnet:** network byte 53 (адреса «9»), integrated 54, subaddress 63
  («B»); порты P2P 28080, RPC 28081.
- **Stagenet:** network byte 24 (адреса «5»), integrated 25, subaddress 36
  («7»); порты P2P 38080, RPC 38081.
- **Генезис-хэш mainnet:** НЕ ПОДТВЕРЖДЕНО в рамках исследования; фиксируется
  по блоку 0 (explorer/локальная нода) при интеграции.
- **Версии ПО:** последний стабильный релиз v0.18.5.3 (октябрь 2026).
  Ветка v0.19 (FCMP++ + Carrot) в разработке: публичный stressnet
  v0.19.0.0-beta.3.0, активация в mainnet не раньше 2027. v0.19 меняет
  модель адресов и восстановления — проектировать ядро кошелька с
  абстракцией форматов заранее.
- **Проверка идентичности:** тикер XMR однозначно закреплён за Monero
  (официальный сайт, репозиторий, майнинг-пулы). Сетей-конфликтантов с
  тикером XMR нет.

## Криптография и ключи

- **Формат адреса:** Base58 (алфавит Bitcoin без 0/O/I/l), 95 символов
  (стандартный и subaddress), 106 — integrated. Содержимое:
  varint(network byte) + public spend key (32 Б) + public view key (32 Б)
  + чексумма (4 Б, keccak). Integrated-адрес дополнительно несёт 8-байтный
  payment ID.
- **Формат публичного ключа:** две точки Ed25519 — public spend key и
  public view key.
- **Формат приватного ключа:** два 32-байтных скаляра (secret spend key,
  secret view key). Watch-only модель: кошелёк из secret view key + адреса
  видит только входящие; исходящие — через импорт подписанных key images
  (`export_key_images`/`import_key_images` из полного кошелька).
- **Схема деривации ключей:** нативная (не BIP32/BIP44): seed → keccak →
  secret spend key → keccak → secret view key. Subaddresses — производные
  secret spend key и индексов (major/minor); accounts/subaddresses —
  уровень кошелька, не протокола.
- **Мнемонический стандарт:** три сосуществующих формата:
  - Legacy 25 слов (Electrum-стиль, словарь 1626 слов, 25-е слово —
    чексумма) — официальный с 2014;
  - Polyseed 16 слов (встроенный birthday для restore height, флаг монеты,
    KDF; поддерживается официальными кошельками с 0.18.4);
  - MyMonero 13 слов (сервисная модель MyMonero; совместимость с
    официальными кошельками НЕ ПОДТВЕРЖДЕНА).
  Polyseed нельзя вывести из 25-словной фразы (необратимый KDF).
- **Алгоритм подписи:** Ed25519; в транзакциях — кольцевые подписи CLSAG
  (с HF v12, 2020), ring size 16 (с HF v15, 2022), range proofs
  Bulletproofs+ (с HF v15), view tags (с HF v15).
- **Совместимость восстановления из фразы:** 25 слов и Polyseed
  восстанавливают полный доступ (spend + view). Восстановление без
  restore height — скан цепи с генезиса (часы); Polyseed ускоряет скан за
  счёт встроенного birthday. Несовместимости: MyMonero 13 ↔ официальные
  кошельки; Polyseed ↔ 25 слов (взаимно не конвертируются).

## Транзакции

- **Структура транзакции:** CryptoNote RingCT: скрытые одноразовые адреса
  (stealth), key images против двойной траты, зашифрованные суммы
  (Pedersen commitments), CLSAG по 16 приманкам, Bulletproofs+.
- **Расчёт комиссии:** нативная модель — от веса транзакции (weight, не
  vByte) с динамическим штрафом за заполнение блока; приоритеты
  (unimportant/normal/elevated/priority) задают множитель; оценка
  комиссии — `get_fee_estimate` демона.
- **Блокировки/имматурность:** обычные транзакции тратятся через 10 блоков;
  coinbase — через 60 блоков.
- **Модель баланса:** UTXO-подобная (одноразовые выходы); на уровне кошелька —
  accounts × subaddresses.
- **Особые поля:** payment ID — только короткий (8 Б) в integrated-адресах;
  длинные 32-байтные устарели и удалены из протокола. URI-схема
  `monero:<адрес>?tx_amount=…&tx_payment_id=…&recipient_name=…&tx_description=…`
  (официальный стандарт для QR/ссылок).

## Доступ к сети

- **Методы RPC:** JSON-RPC 2.0 поверх HTTP.
  - Демон: `get_info`, `get_block_count`, `get_last_block_header`,
    `get_block_header_by_height/hash`, `get_block`, `get_transactions`,
    `get_transaction_pool`, `send_raw_transaction`, `get_fee_estimate`,
    `is_key_image_spent`, `get_outs` (сборка колец).
  - Кошелёк (`monero-wallet-rpc`; `--rpc-bind-port` — обязательный
    аргумент, порта по умолчанию нет — проверено по исходникам):
    `create_wallet`, `generate_from_keys`, `open_wallet`, `get_balance`,
    `get_address`, `create_address`, `get_transfers`,
    `get_transfer_by_txid`, `transfer`, `transfer_split`, `sweep_all`,
    `sweep_single`, `describe_transfer`, `sign_transfer`/`submit_transfer`
    (офлайн-подписание), `sign`/`verify`,
    `export_key_images`/`import_key_images`, `refresh`, `set_daemon`.
- **P2P-протокол:** порт 18080 (TCP), wire-протокол epee/Levin (CryptoNote);
  клиент — `monerod`, bootstrap через seed-ноды. Поддержка Tor описана в
  README (`torsocks`, `--p2p-bind-ip 127.0.0.1`).
- **Лёгкий клиент:** собственного SPV-протокола нет. Три модели:
  (а) remote node — кошелёк сам сканирует цепь через RPC чужого узла;
  (б) monero-lws (light wallet server) — серверный скан по view key:
  требует сервер, для VEYRO не подходит (только сторонние инстансы =
  доверие третьей стороне);
  (в) локальная нода (в т.ч. pruned) — максимум приватности.
- **Узел:** `monerod` (C++), официальные сборки Windows/Linux/ARM.
  Полная цепь — сотни ГБ (точное значение на ноябрь 2026 НЕ ПОДТВЕРЖДЕНО);
  pruned-режим `--prune-blockchain` кратно меньше и достаточен для кошелька.
- **Публичные RPC:** список открытых узлов — https://monero.fail (community).
  Предупреждение о приватности: удалённый узел видит IP, тайминг и
  TXID-запросы кошелька — риск привязки IP ↔ TXID официально
  документирован; публичные узлы открывают `--restricted-rpc`.
- **Explorer:** официального нет; community — xmrchain.net. В эксплорере
  не видны ни балансы, ни адреса, ни суммы (следствие RingCT): история
  кошелька отображается только из wallet-RPC; эксплорер годен для статуса
  TX по хэшу.

## SDK и библиотеки

- **Официальные SDK:** C++-ядро (сам репозиторий, BSD-3-Clause),
  monero-gui (Qt). Официальных JS/Rust SDK нет — есть community.
- **Rust-библиотеки:**
  - monero-rs (`monero`, MIT, активен, v0.22.0): адреса, ключи,
    транзакции, блоки, network types. НЕ реализует подписание/трату —
    signing-логику строить самостоятельно или брать из monero-oxide.
  - monero-oxide (крейты `monero-oxide`, `monero-wallet`; активен с 2024):
    Rust-реализация wallet-функций поверх примитивов; лицензию проверить
    при внедрении (НЕ ПОДТВЕРЖДЕНО в рамках исследования).
  - monero-javascript (community, WASM + RPC).
- **Flutter/Dart-интеграции:** официальной нет. Референсы: Cake Wallet
  (Flutter; GPL-3.0 — код заимствовать нельзя), Feather (C++/Qt).
  Путь VEYRO: Rust-ядро + FFI.
- **Лицензии зависимостей:** monero — BSD-3-Clause (совместимо с
  MIT OR Apache-2.0), monero-rs — MIT (совместимо). Ключевые
  криптокомпоненты (CLSAG, Bulletproofs+, FCMP++) проходят внешние аудиты;
  история аудитов публикуется на официальном сайте.

## Совместимость кошелька

Реализуемость подтверждена на уровне протокола; в VEYRO ничего не
тестировалось, поэтому галочки не проставлены.

- [ ] Создание кошелька — `create_wallet`; форматы seed: 25 слов / Polyseed
- [ ] Импорт кошелька — `generate_from_keys` (ключи), из фразы
- [ ] Восстановление — restore height (или birthday из Polyseed); без него —
      скан с генезиса
- [ ] Получение — стандартный адрес / subaddress / integrated; QR; URI
      `monero:`
- [ ] Баланс — `get_balance` (strict/non-strict; locked/unlocked)
- [ ] История транзакций — `get_transfers`, `get_transfer_by_txid`
- [ ] Отправка — `transfer`/`transfer_split`/`sweep_all`; подпись в
      кошельке, бродкаст через `send_raw_transaction` демона
- [ ] Мониторинг подтверждений — `refresh`, `get_height`,
      `is_key_image_spent`

### Режимы работы без серверов VEYRO (архитектурное требование)

- **Без своего сервера и без полной локальной ноды: ДА.** Полный цикл
  (создание → адрес → баланс → история → отправка → подтверждения) работает
  через remote node из monero.fail — кошелёк сам сканирует цепь. Цена:
  приватность (узел видит IP/запросы) и долгое восстановление без
  restore height.
- **Без своего сервера, с локальной нодой: ДА.** `monerod`, pruned
  допустим; максимальная приватность.
- **Невозможно без сервера/ноды:** ничего — серверных зависимостей у
  функционала кошелька нет; monero-lws-модель исключена (требует сервер).

## Безопасность и ограничения

- **Известные ограничения:** watch-only видит только входящие (исходящие —
  через key images из полного кошелька); восстановление без restore height —
  часы сканирования; multisig — экспериментальная функция (флаг
  `enable-multisig-experimental`); эксплорер не показывает балансы.
- **Риски безопасности:** remote nodes (spy nodes) — привязка IP ↔ TXID
  (официально предупреждённая); тайминг-анализ сети; после активации v0.19
  (FCMP++/Carrot) потребуется обновление форматов адресов/seed — закладывать
  версии заранее.
- **Блокеры:** нет. Remote node покрывает полный цикл; локальная нода —
  опция для максимальной приватности.

## Вывод для матрицы

- **Идентичность:** подтверждена (XMR = Monero).
- **Рекомендуемый статус:** из `Research required` → реализация. Полный цикл
  достижим без серверов VEYRO (remote node / локальная нода). Кандидат №1
  в privacy-группе: самый зрелый wallet-RPC, аудированная криптография,
  есть Rust-примитивы (monero-rs) и Rust wallet-логика (monero-oxide).
  Статус «Full support» — после проверенного полного цикла в тестах.
- **Главный риск:** приватность при использовании публичных remote nodes —
  обязательное предупреждение в UI + рекомендация локальной ноды.

## Источники

1. https://github.com/monero-project/monero — исходники:
   `cryptonote_config.h` (network bytes, порты), `wallet_rpc_server.cpp`
   (проверено: `--rpc-bind-port` обязателен; seed types Legacy/Polyseed;
   watch-only/multisig).
2. https://www.getmonero.org/resources/developer-guides/wallet-rpc/ —
   wallet RPC.
3. https://www.getmonero.org/resources/user-guides/remote-node-gui/ —
   remote nodes и предупреждения о приватности.
4. https://monero.fail/ — список публичных узлов.
5. https://github.com/monero-project/monero/releases — v0.18.5.3, ветка
   v0.19 (stressnet beta).
6. https://github.com/polyseed/polyseed — спецификация Polyseed.
7. https://github.com/monero-rs/monero — Rust-примитивы (MIT).
8. https://github.com/monero-oxide/monero-oxide — Rust wallet-логика.
9. https://xmrchain.net — community explorer.
