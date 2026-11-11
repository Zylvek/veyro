# Технический паспорт монеты: ZEC

- **Тикер(ы):** ZEC
- **Официальное название проекта:** Zcash
- **Официальный сайт:** https://z.cash (ECC), https://zfnd.org (Zcash
  Foundation)
- **Официальный репозиторий:** https://github.com/zcash/zcash (zcashd —
  EoL, архивируется), https://github.com/ZcashFoundation/zebra (Zebra)
- **Официальная документация:** https://zcash.github.io (документация
  узлов), https://zips.z.cash (спецификации ZIP)
- **Статус исследования:** завершено

## Идентификация сети

- **Mainnet:** Zcash L1; PoW Equihash (200,9); блок 75 с; cap 21 000 000
  ZEC; халвинги каждые ~4 года (первый — ноябрь 2020). Сеть жива и
  развивается: последняя активация — NU6.3 «Ironwood» на mainnet
  (~28.07.2026, по данным исследования).
- **КРИТИЧНО — zcashd мёртв:** `zcashd` автоматически остановился (halt)
  на блоке 3417100 18.07.2026 (End-of-Life), репозиторий архивируется.
  zcashd НЕ поддерживает NU6.3 и любые последующие активации. Любые
  интеграции/руководства на стеке zcashd непригодны.
- **Testnet:** есть; unified-адреса `utest1…`; P2P-порт Zebra 18233.
- **Проверка идентичности:** тикер ZEC = Zcash (z.cash); сетей-конфликтантов
  нет.

## Криптография и ключи

- **Формат адреса:** Unified Addresses (ZIP-316, bech32m): `u1…` (mainnet) /
  `utest1…` (testnet). Унаследованные форматы: Sapling `zs1…`
  (bech32); transparent `t1…` (Base58, P2PKH) и `t3…` (P2SH), testnet
  `tm…`/`t2…`; Sprout `zc…` (legacy, не использовать).
- **Формат публичного ключа:** transparent — secp256k1 (Bitcoin-модель);
  shielded — ключи кривых Sapling (Jubjub) / Orchard (Pallas).
- **Схема деривации:** shielded — ZIP-32: `m/32'/133'/account'` (из одного
  seed выводятся Sapling- и Orchard-ключи); transparent — BIP44
  `m/44'/133'/0'/…`. Seed современных кошельков — BIP39 (модель Zashi);
  единый стандарт НЕ ПОДТВЕРЖДЁН — сверять при интеграции.
- **Мнемонический стандарт:** BIP39-совместимый seed у современных кошельков
  (Zashi-модель); НЕ ПОДТВЕРЖДЕНО как обязательный стандарт сети.
- **Viewing-модель:** UFVK (unified full viewing key, bech32m `uview1…`)
  — видит входящие и исходящие; watch-only аккаунты через
  `z_importviewingkey` (поддержан в Zallet). Sapling viewing keys — bech32
  (префикс уточнить при интеграции).
- **Алгоритм подписи:** transparent — ECDSA secp256k1; Sapling — Groth16
  (trusted setup, церемония завершена), RedJubjub; Orchard — Halo2 (без
  trusted setup), RedPallas. Shielded-траты — zk-доказательства.
- **Совместимость восстановления из фразы:** seed → ZIP-32 → все аккаунты.
  Восстановление требует полного скана shielded-цепи — лёгкой модели без
  сервера нет.

## Транзакции

- **Структура транзакции:** transparent (Bitcoin-подобная) + shielded-пулы:
  Sapling (spends/outputs) и Orchard (actions); nullifiers против двойной
  траты; зашифрованные memo (до 512 Б).
- **Расчёт комиссии:** shielded — ZIP-317 (conventional fee: формула от
  числа actions); transparent — Bitcoin-модель (vByte).
- **Блокировки/имматурность:** coinbase-зрелость 100 блоков (наследие
  Bitcoin).
- **Модель баланса:** UTXO (transparent) + notes (shielded).
- **Особые поля:** unified receivers (ZIP-316), memo, PCZT — формат
  пошаговой сборки/подписи транзакции (аналог PSBT для shielded).

## Доступ к сети

- **Узел — Zebra** (`zebrad`, Rust, Zcash Foundation; MIT OR Apache-2.0):
  консенсус-нода БЕЗ кошелька; RPC — ограниченный отладочный набор, по
  умолчанию выключен; порты 8233 (mainnet) / 18233 (testnet);
  ориентирован на Linux — Windows официально не тестируется.
- **Кошельковые надстройки:**
  - **Zallet** (репозиторий zcash/zallet): full-node wallet поверх Zebra
    (indexer feature); beta 0.1.0-beta.3 (24.08.2026); лицензия
    Apache-2.0 OR MIT; внутри — zcash_client_sqlite; view-only аккаунты
    через `z_importviewingkey`; PCZT-флоу. КРИТИЧНО (цитата проекта):
    «No chain backend currently runs on macOS or Windows, because the
    zebra backend is Linux-only» — нативного бэкенда на Windows нет.
  - **zecd** (zecd.org): stateless wallet-сервер (bitcoind-стиля RPC)
    поверх локального Zebra; watch-only через UFVK; запускается локально
    пользователем (не требует сервера VEYRO).
- **Light-сервисы:** lightwalletd / Zaino (gRPC-индексеры для мобильных
  клиентов) — требуют собственный сервер поверх полной ноды → для VEYRO
  не подходят; публичные инстансы третьих лиц существуют, но это доверие
  стороннему серверу.
- **Rust SDK:** librustzcash (крейты zcash_primitives, zcash_proofs,
  zcash_client_backend, zcash_client_sqlite, orchard, sapling-crypto,
  zip32, zcash_address; MIT OR Apache-2.0) — основа для собственного
  Rust-ядра VEYRO.
- **Публичные RPC:** модели «remote node» (как у XMR) нет: shielded-скан
  требует либо полной цепи (Zebra), либо lightwalletd-сервера.
- **Explorer:** официального нет; community-эксплореры (shielded-данные в
  них не видны).

## SDK и библиотеки

- **Официальные SDK:** librustzcash (Rust, MIT OR Apache-2.0) — примитивы,
  proofs, client backend, SQLite-кошелёк. Компоненты экосистемы: Zebra
  (MIT OR Apache-2.0), Zallet (Apache-2.0 OR MIT), Zashi (референсный
  мобильный кошелёк).
- **Rust-библиотеки:** librustzcash — первоклассный активный стек
  (используется Zashi/Zallet); состояние production-готовности для
  полного цикла — через zcash_client_sqlite.
- **Flutter/Dart-интеграции:** официальной нет; путь VEYRO — Rust-ядро на
  librustzcash + FFI.
- **Лицензии зависимостей:** MIT OR Apache-2.0 по всему стеку
  (librustzcash, Zebra, Zallet) — полностью совместимо с требованиями
  VEYRO.

## Совместимость кошелька

Условная реализуемость: только при наличии локальной ноды (Zebra) и
кошелькового стека (Zallet/zecd/свой librustzcash). В VEYRO ничего не
тестировалось.

- [ ] Создание кошелька — zcash_client_sqlite / Zallet (локальный Zebra)
- [ ] Импорт кошелька — seed (ZIP-32) / UFVK (watch-only)
- [ ] Восстановление — полный скан shielded-цепи с локальной нодой
- [ ] Получение — unified-адрес `u1…`; QR/URI (`zcash:` — схема ZIP,
      номер сверить)
- [ ] Баланс — через wallet-стек (Zallet/zecd/zcash_client_sqlite)
- [ ] История транзакций — через wallet-стек
- [ ] Отправка — Zallet (PCZT) / собственный стек librustzcash
- [ ] Мониторинг подтверждений — через wallet-стек

### Режимы работы без серверов VEYRO (архитектурное требование)

- **Без своего сервера и без полной локальной ноды: НЕТ.** Полноценного
  режима нет: shielded-скан требует полной цепи либо lightwalletd-сервера
  (чужой сервер = доверие третьей стороне; не рекомендуется по умолчанию).
  Теоретически возможна изолированная поддержка только transparent-пула
  (t1…) по Bitcoin-модели — противоречит смыслу актива, не рекомендуется.
- **Без своего сервера, с локальной нодой: ДА (условно).** Zebra +
  Zallet/zecd/свой librustzcash-стек. Ограничение: Zebra
  Linux-ориентирован, Zallet-бэкенд — Linux-only; на Windows — только
  WSL/Docker, нативной поддержки нет.
- **Вывод:** самая дорогая интеграция в privacy-группе; без собственного
  Rust-стека на librustzcash не обойтись.

## Безопасность и ограничения

- **Известные ограничения:** zcashd мёртв (halt 18.07.2026) — подавляющее
  большинство старых руководств/библиотек устарели; Zallet — beta; PCZT —
  молодой флоу; Zebra на Windows не тестируется.
- **Риски безопасности:** активная фаза миграции экосистемы (NU6.3);
  Groth16/Sapling — исторический trusted setup (церемония завершена;
  Orchard его не требует).
- **Блокеры:** нативная Windows-реализация — Zebra/Zallet на Windows не
  работают (Linux-only backend); обходные пути WSL/Docker — не «нативно».

## Вывод для матрицы

- **Идентичность:** подтверждена (ZEC = Zcash).
- **Рекомендуемый статус:** **Blocked** для нативной Windows-реализации;
  условная реализация возможна на Linux (или через WSL/Docker на
  Windows) по пути librustzcash + Zebra (+ Zallet/zecd после стабилизации
  из beta). Не включать в первый релиз; вернуться после стабилизации
  Zallet/PCZT.
- **Главный риск:** отсутствие кошелькового бэкенда на Windows (Linux-only)
  и beta-статус всех свежих инструментов поверх мёртвого zcashd.

## Источники

1. https://z.cash/ — Zcash; активация NU6.3 «Ironwood».
2. https://github.com/zcash/zcash — уведомление об EoL zcashd (halt на
   блоке 3417100, 18.07.2026).
3. https://github.com/ZcashFoundation/zebra — Zebra (MIT OR Apache-2.0;
   RPC выключен по умолчанию; Linux-ориентированность).
4. https://github.com/zcash/zallet — Zallet beta (цитата о Linux-only
   backend; z_importviewingkey; PCZT).
5. https://zips.z.cash/ — ZIP-32 (деривация m/32'/133'), ZIP-316
   (UA/UFVK), ZIP-317 (комиссии).
6. https://github.com/zcash/librustzcash — Rust-SDK (MIT OR Apache-2.0).
7. https://zecd.org — zecd (stateless wallet-сервер поверх Zebra,
   watch-only через UFVK).
8. https://github.com/zcash/lightwalletd — lightwalletd (серверная
   light-модель, требует свою ноду).
