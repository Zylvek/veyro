# Технический паспорт монеты: ZEPH

- **Тикер(ы):** ZEPH (базовая монета; asset_type в RPC — ZPH). Нативные
  активы сети: ZPH (Zephyr, тикер ZEPH), ZSD (Zephyr Stable Dollar),
  ZRS (Zephyr Reserve Share), ZYS (Zephyr Yield Share). Биржевые обозначения
  производных активов: ZEPHUSD (= ZSD), ZEPHRSV (= ZRS), ZYIELD (= ZYS) —
  из официальной документации.
- **Официальное название проекта:** Zephyr Protocol
- **Официальный сайт:** https://zephyrprotocol.com
- **Официальный репозиторий:** https://github.com/ZephyrProtocol/zephyr
- **Официальная документация:** https://zephyrprotocol.com/documentation
  (Basic guide / Daemon RPC / Wallet RPC / Scanner API)
- **Статус исследования:** завершено

## Идентификация сети

- **Mainnet:** форк Monero (кодовая база поколения v0.18), запуск mainnet —
  29.05.2023. Параметры проверены по исходникам `src/cryptonote_config.h`:
  - COIN = 10^12 (12 знаков);
  - spendable age — 10 блоков;
  - префиксы адресов: «ZEPHYR…» (стандартный, Base58-префикс
    0x6241d18c0), «ZEPHii…» (integrated), «ZEPHs…» (subaddress);
  - порты: P2P 17766, RPC 17767, ZMQ 17768;
  - PoW RandomX, блок 120 с (подтверждено официальной документацией);
  - HF v11 на блоке 536000 (v2.3.0) — «post-audit»: старые
    (неаудированные) asset_type инвалидны, отправка/получение таких
    активов невозможны (официальная документация).
- **Testnet:** публичный (с 08.2023); префикс адресов «ZPHT»; порты P2P
  27766, RPC 27767; фосеты через Discord.
- **Stagenet:** есть; префикс «ZPHS»; порты 37766/37767.
- **NETWORK_ID и генезис-параметры:** определены в исходниках; точные
  значения фиксируются при интеграции.
- **Проверка идентичности:** тикер ZEPH закреплён за Zephyr Protocol
  (zephyrprotocol.com, GitHub ZephyrProtocol). Внимание: до 2023 имя/тикер
  «Zephyr» использовал другой, мёртвый проект (zephyr-protocol/zephyr,
  2018, форк Sumokoin на CryptoNight с «camel»-эмиссией) — это НЕ текущая
  сеть: текущая сеть — Monero-кодовая база 2023 года, RandomX. Для матрицы:
  ZEPH = Zephyr Protocol (2023).

## Криптография и ключи

- **Формат адреса:** как Monero (Base58, network byte из
  `cryptonote_config.h`), префиксы «ZEPHYR»/«ZEPHii»/«ZEPHs»
  (mainnet), «ZPHT» (testnet), «ZPHS» (stagenet).
- **Формат публичного ключа:** две точки Ed25519 (public spend key,
  public view key) — унаследовано от Monero.
- **Формат приватного ключа:** два 32-байтных скаляра; watch-only модель
  как у Monero (view key + адрес; исходящие — через key images). Подтверждено
  существование multisig/view-only/offline-кошельков (zephyr-javascript).
- **Схема деривации ключей:** нативная Monero (seed → spend → view);
  subaddresses/integrated — как у Monero. НЕ BIP32/BIP44.
- **Мнемонический стандарт:** 25 слов (подтверждено официальной
  документацией Zephyr Wallet). Поддержка Polyseed НЕ ПОДТВЕРЖДЕНА —
  проверить при интеграции.
- **Алгоритм подписи:** Ed25519; RingCT с CLSAG и Bulletproofs+
  (унаследовано от Monero v0.18-кодовой базы).
- **Совместимость восстановления из фразы:** 25 слов → полный доступ;
  совместимость фраз с Monero отсутствует (другой network byte/NETWORK_ID).
  Восстановление — скан с restore height (без него — с генезиса).

## Транзакции

- **Структура транзакции:** CryptoNote RingCT (CLSAG, Bulletproofs+,
  key images) — как Monero, с расширением на нативные активы: каждая
  транзакция работает с конкретным asset_type.
- **Четыре нативных актива:** ZPH, ZSD, ZRS, ZYS (asset_type — обязательный
  параметр RPC). После аудита (HF v11) неаудированные asset_type
  непригодны.
- **Протокольные операции:** mint/redeem (mint_stable, mint_reserve,
  redeem_stable, redeem_reserve), transfer/stable_transfer/reserve_transfer
  (CLI); экономика — минимальная Djed-модель с reserve ratio: жёстко
  зашитые правила коллатерализации автоматически останавливают mint/redeem
  при выходе за диапазон.
- **Расчёт комиссии:** модель Monero (per-kB weight, динамическая,
  приоритеты). Точные константы — из исходников при интеграции.
- **Блокировки/имматурность:** spendable age 10 блоков (проверено по
  конфигу); coinbase — 60 блоков (унаследовано от Monero).
- **Модель баланса:** UTXO-подобная, с балансами на каждый актив
  (`get_balance` по asset_type или по всем).
- **Особые поля:** asset_type в каждом RPC-методе;
  source_asset/destination_asset в transfer (конвертации);
  payment ID/integrated — как у Monero.

## Доступ к сети

- **Методы RPC:** JSON-RPC 2.0, совместим с Monero-стеком.
  - Демон `zephyrd` (порт 17767): `get_block_count`,
    `get_last_block_header`, `get_transactions`, `send_raw_transaction`
    и др. (Monero-совместимые).
  - Кошелёк `zephyr-wallet-rpc` (`--rpc-bind-port` — обязательный
    аргумент; в официальной документации используется 17777):
    `create_wallet`, `get_balance` (asset_type или все),
    `get_transfers`, `get_transfer_by_txid`, `transfer`
    (source_asset/destination_asset), `sweep_all` и др.
  - «Scanner API» заявлен в навигации официальной документации —
    назначение/требования НЕ ИССЛЕДОВАНЫ (проверить: может быть серверным
    сервисом).
- **P2P-протокол:** порт 17766, epee/Levin (CryptoNote), клиент `zephyrd`.
- **Лёгкий клиент:** собственного light-протокола нет; модель remote node
  (кошелёк сканирует цепь через RPC узла). Совместимость с monero-lws
  НЕ ПОДТВЕРЖДЕНА.
- **Узел:** `zephyrd`; официальные требования: 4 ядра CPU, 4 ГБ RAM,
  60 ГБ SSD (+~10 ГБ/год), 10 Мбит/с, ~50 ГБ трафика в месяц. Поддержка
  pruning (`--prune-blockchain`), Tor через torsocks (README),
  `--restricted-rpc` для публичных узлов — унаследовано от Monero.
- **Публичные RPC:** remote nodes существуют (GUI умеет подключаться к
  удалённому узлу); централизованный список публичных mainnet-узлов
  НЕ ПОДТВЕРЖДЁН. Предупреждение о приватности — как для Monero.
- **Оракулы:** oracle.zephyrprotocol.com — централизованные серверы
  pricing records (цены для mint/redeem). Консенсус-критичны только
  данные, попадающие в блоки; для базовых переводов подключение к оракулам
  кошельку не требуется.
- **Explorer:** https://explorer.zephyrprotocol.com — ограничения
  приватности как у XMR (балансы/адреса/суммы не видны).

## SDK и библиотеки

- **Официальные SDK:** zephyr-javascript (адаптация monero-javascript:
  WASM-кошельки в браузере/Node, RPC-клиенты, multisig/view-only/offline).
- **Rust-библиотеки:** отдельного Rust SDK для ZEPH нет. Вариант:
  monero-rs с заменой network byte/NETWORK_ID — потребует модификаций,
  НЕ ПРОВЕРЕНО. Реальный стек — wallet-RPC `zephyr-wallet-rpc` или
  WASM из zephyr-javascript.
- **Flutter/Dart-интеграции:** официальной нет; референс — Zephyr GUI
  (форк monero-gui, C++/Qt).
- **Лицензии зависимостей:** zephyr — BSD-3-Clause (наследие Monero,
  совместимо с MIT OR Apache-2.0); zephyr-javascript — MIT (наследие
  monero-javascript).

## Совместимость кошелька

Реализуемость подтверждена на уровне протокола; в VEYRO ничего не
тестировалось.

- [ ] Создание кошелька — `create_wallet`; seed 25 слов
- [ ] Импорт кошелька — из фразы/ключей (Monero-совместимые RPC)
- [ ] Восстановление — restore height; без него — скан с генезиса
- [ ] Получение — адреса «ZEPHYR…»; QR/URI (Monero-подобная схема —
      сверить префикс URI при интеграции)
- [ ] Баланс — `get_balance` по каждому asset_type (ZPH/ZSD/ZRS/ZYS)
- [ ] История транзакций — `get_transfers`, `get_transfer_by_txid`
      (asset_type обязателен)
- [ ] Отправка — `transfer` (+ source_asset/destination_asset для
      конвертаций), mint/redeem
- [ ] Мониторинг подтверждений — refresh + spendable age 10 блоков

### Режимы работы без серверов VEYRO (архитектурное требование)

- **Без своего сервера и без полной локальной ноды: ДА.** Remote node:
  полный цикл функций, кошелёк сам сканирует цепь; риски приватности как
  у XMR.
- **Без своего сервера, с локальной нодой: ДА.** `zephyrd` (4 CPU / 4 ГБ /
  60 ГБ), pruning поддержан.
- **Невозможно без сервера/ноды:** ничего — серверных зависимостей нет;
  оракулы нужны только протоколу mint/redeem (данные приходят из блоков).

## Безопасность и ограничения

- **Известные ограничения:** asset_type в каждом вызове — интеграционная
  работа поверх XMR-стека; coinbase 60 блоков; аудиторская история —
  аудит 2024 (v2.1.1) и хардфорк v11, инвалидировавший старые asset_type.
- **Риски безопасности:** централизованные оракулы (pricing-инфраструктура)
  — зависимость протокольной экономики; хешрейт/капитализация сети
  значительно ниже Monero; риски remote node (spy nodes) как у XMR.
- **Блокеры:** нет структурных блокеров; стек переиспользуется с XMR
  (~80–90% инженерной работы общее).

## Вывод для матрицы

- **Идентичность:** подтверждена (ZEPH = Zephyr Protocol 2023, не путать с
  мёртвым «Zephyr» 2018).
- **Рекомендуемый статус:** из `Research required` → реализация. Полный
  цикл без серверов VEYRO (remote node / локальная нода), Monero-совместимый
  wallet-RPC. Реализовывать после/вместе с XMR с переиспользованием стека.
  «Full support» — после проверенного полного цикла в тестах (включая все
  4 актива).
- **Главный риск:** зависимость протокольной экономики от централизованных
  оракулов и меньшая устойчивость сети (хешрейт); для функции кошелька
  (переводы) риск ограничен.

## Источники

1. https://zephyrprotocol.com/documentation — Basic guide (4 актива,
   asset_type, ZPH/ZSD/ZRS/ZYS, биржевые тикеры, wallet-rpc с
   `--rpc-bind-port 17777`, post-audit HF v11).
2. https://zephyrprotocol.com/documentation/wallet-rpc — wallet RPC
   (get_transfer_by_txid, get_balance, transfer).
3. https://github.com/ZephyrProtocol/zephyr — исходники
   (`cryptonote_config.h`: префиксы, порты, COIN, spendable age),
   README (pruning, Tor, restricted-rpc).
4. https://github.com/ZephyrProtocol/zephyr-javascript — официальный JS
   SDK (multisig/view-only/offline).
5. https://zephyrwallet.io/documentation — требования к ноде, 25-словная
   мнемоника.
6. https://medium.com/@zephyrcurrencyprotocol/zephyr-protocol-public-testnet-now-live-f0b721536dab —
   публичный тестнет (08.2023), remote node модель GUI.
7. https://explorer.zephyrprotocol.com — explorer.
