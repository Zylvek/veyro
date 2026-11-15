//! Словарь интерфейса VEYRO (решение владельца: «в настройках добавь
//! поддержку других языков»). Русский — база; English переводит
//! основную оболочку (Обзор, настройки, каталог); редкие глубокие
//! экраны и честные статусы сетей добираются по ходу обновлений.
//! Использование: t('total_balance').

import 'package:flutter/foundation.dart';

import 'package:veyro/util/display_prefs.dart';

/// Событие смены языка: `t()` — просто функции от строки, экраны сами
/// перевод не перечитывают; MaterialApp.builder перестраивает весь
/// навигатор на это событие — язык применяется мгновенно на всех
/// экранах (решение владельца: «язык должен меняться везде»).
final ValueNotifier<int> languageRevision = ValueNotifier<int>(0);

/// Вызвать после DisplayPrefs.setLanguage (настройки «Общие»).
void bumpLanguageRevision() => languageRevision.value++;

const Map<String, Map<String, String>> _strings = {
// Обзор.
  'total_balance': {'ru': 'Общий баланс', 'en': 'Total balance'},
  'synced_funds': {
    'ru': 'Есть синхронизированные средства',
    'en': 'Synced funds available',
  },
  'all_assets': {'ru': 'Все монеты', 'en': 'All assets'},
  'recent_transactions': {
    'ru': 'Последние транзакции',
    'en': 'Recent activity',
  },
  'no_transactions': {
    'ru': 'Транзакций пока нет — всё чисто.',
    'en': 'No transactions yet — all clear.',
  },
  'core_unavailable': {'ru': 'Ядро недоступно', 'en': 'Core unavailable'},
  'check_install': {
    'ru': 'Проверьте установку и повторите.',
    'en': 'Check the installation and retry.',
  },
  'retry': {'ru': 'Повторить', 'en': 'Retry'},
  'show_amounts': {'ru': 'Показать суммы', 'en': 'Show amounts'},
  'hide_amounts': {'ru': 'Скрыть суммы', 'en': 'Hide amounts'},
  'db_unavailable': {'ru': 'БД настроек недоступна', 'en': 'Settings DB unavailable'},
  'period_1d': {'ru': '1Д', 'en': '1D'},
  'period_1w': {'ru': '1Н', 'en': '1W'},
  'period_1m': {'ru': '1М', 'en': '1M'},
  'period_1y': {'ru': '1Г', 'en': '1Y'},
  // Настройки.
  'settings_general': {'ru': 'Общие', 'en': 'General'},
  'display_currency': {'ru': 'Валюта отображения:', 'en': 'Display currency:'},
  'language_label': {'ru': 'Язык:', 'en': 'Language:'},
  'db_note': {
    'ru': 'БД настроек недоступна: изменения действуют только текущую сессию',
    'en': 'Settings database unavailable: changes apply to this session only',
  },
  'settings_security': {'ru': 'Безопасность', 'en': 'Security'},
  'settings_notifications': {'ru': 'Уведомления', 'en': 'Notifications'},
  'settings_references': {'ru': 'Разделы', 'en': 'Sections'},
  'settings_wallets': {'ru': 'Кошельки', 'en': 'Wallets'},
  // Каталог.
  'assets_title': {'ru': 'Активы', 'en': 'Assets'},
  'search_hint': {
    'ru': 'Поиск: тикер, имя или сеть',
    'en': 'Search: ticker, name or network',
  },
  'nothing_found': {'ru': 'Ничего не найдено', 'en': 'Nothing found'},
  // Настройки — продолжение.
  'settings_title': {'ru': 'Настройки', 'en': 'Settings'},
  'chart_coin_label': {'ru': 'График:', 'en': 'Chart:'},
  // Кошельки.
  'wallets_create': {'ru': 'Создать', 'en': 'Create'},
  'wallets_import': {'ru': 'Импорт', 'en': 'Import'},
  'wallets_registry_error': {
    'ru': 'Реестр не прочитан: {error}',
    'en': 'Registry could not be read: {error}',
  },
  'wallets_empty': {
    'ru': 'Кошельков нет. Первый появится после создания или '
        'восстановления фразы.',
    'en': 'No wallets yet. The first one appears after creating a wallet '
        'or restoring a phrase.',
  },
  'wallet_created': {
    'ru': 'vault · создан {date}',
    'en': 'vault · created {date}',
  },
  'wallet_id': {'ru': 'ID: {id}', 'en': 'ID: {id}'},
  'seed_reveal_tooltip': {
    'ru': 'Показать seed-фразу',
    'en': 'Show seed phrase',
  },
  'delete_wallet_tooltip': {'ru': 'Удалить кошелёк', 'en': 'Delete wallet'},
  'delete_wallet_title': {
    'ru': 'Удалить кошелёк «{name}»?',
    'en': 'Delete wallet "{name}"?',
  },
  'delete_wallet_body': {
    'ru': 'Хранилище ключей этого кошелька (vault-файл) будет удалено с '
        'диска навсегда. Без резервной копии восстановить доступ к '
        'средствам будет невозможно.',
    'en': 'This wallet\'s key storage (vault file) will be removed from '
        'the disk for good. Without a backup, access to the funds '
        'cannot be restored.',
  },
  'cancel': {'ru': 'Отмена', 'en': 'Cancel'},
  'delete_forever': {'ru': 'Удалить навсегда', 'en': 'Delete forever'},
  'wallet_deleted': {
    'ru': 'Кошелёк «{name}» удалён.',
    'en': 'Wallet "{name}" deleted.',
  },
  'reveal_title': {
    'ru': 'Показать seed-фразу «{name}»',
    'en': 'Show the seed phrase of "{name}"',
  },
  // Безопасность.
  'session_state_error': {
    'ru': 'Состояние сессии не прочитано: {error}',
    'en': 'Session state could not be read: {error}',
  },
  'session_keys_active': {
    'ru': 'Ключи сессии в памяти ядра ({network})',
    'en': 'Session keys are in the core memory ({network})',
  },
  'btc_locked_chip': {
    'ru': 'BTC заблокирован: ключи сессии не загружены',
    'en': 'BTC is locked: session keys are not loaded',
  },
  'lock_btc_btn': {'ru': 'Заблокировать BTC', 'en': 'Lock BTC'},
  'locking_now': {'ru': 'Блокировка…', 'en': 'Locking…'},
  'manual_lock_note': {
    'ru': 'Ручная блокировка выгружает ключи сессии из памяти ядра: '
        'повторная разблокировка требует пароля кошелька.',
    'en': 'Manual lock unloads the session keys from the core memory: '
        'unlocking again requires the wallet password.',
  },
  'idle_lock_label': {
    'ru': 'Авто-блокировка по бездействию',
    'en': 'Auto-lock on idle',
  },
  'idle_lock_note': {
    'ru': 'не реализовано в ядре (нет таймера бездействия) — '
        'переключатель не добавляется',
    'en': 'not implemented in the core (no idle timer) — no toggle is added',
  },
  'biometry_label': {'ru': 'Биометрия', 'en': 'Biometrics'},
  'biometry_note': {
    'ru': 'не реализовано в этой сборке (планируется в Android-группе)',
    'en': 'not implemented in this build (planned for the Android group)',
  },
  'password_change_label': {'ru': 'Смена пароля', 'en': 'Password change'},
  'password_change_note': {
    'ru': 'API смены пароля в ядре отсутствует; честный путь — экспорт '
        'и импорт с новым паролем',
    'en': 'there is no password-change API in the core; the honest path '
        'is export and import with a new password',
  },
  'secrets_label': {'ru': 'Хранение секретов', 'en': 'Secret storage'},
  'secrets_note': {
    'ru': 'seed и ключи — только в зашифрованном vault ядра; показ фразы '
        'требует пароля',
    'en': 'seed and keys live only in the encrypted core vault; revealing '
        'the phrase requires the password',
  },
  // Уведомления.
  'notifications_note': {
    'ru': 'Уведомления не реализованы в этой сборке — переключателей '
        'и имитации здесь нет. Если функция появится, допустимые '
        'события (по спецификации): подтверждение входящей '
        'транзакции, сбои и восстановление сетевого подключения, '
        'завершение синхронизации, статус бэкапа. Маркетинг и '
        'реклама исключены безусловно.',
    'en': 'Notifications are not implemented in this build — there are no '
        'toggles or imitation here. If the feature lands, the allowed '
        'events (per the spec) are: incoming-transaction confirmation, '
        'network failure and recovery, sync completion, backup status. '
        'Marketing and ads are excluded unconditionally.',
  },
  // Разделы.
  'backups_btn': {'ru': 'Бэкап и восстановление', 'en': 'Backup and restore'},
  'about_btn': {'ru': 'О VEYRO', 'en': 'About VEYRO'},
  // BTC-центр.
  'btc_connecting': {'ru': 'Подключение…', 'en': 'Connecting…'},
  'unlocking_now': {'ru': 'Разблокировка…', 'en': 'Unlocking…'},
  'btc_syncing_addresses': {
    'ru': 'Синхронизация адресов…',
    'en': 'Syncing addresses…',
  },
  'btc_syncing_addresses_long': {
    'ru': 'Синхронизация адресов… (gap-limit 20, это может занять до минуты)',
    'en': 'Syncing addresses… (gap limit 20, this may take up to a minute)',
  },
  'btc_unlock_title': {
    'ru': 'Разблокировать BTC — «{name}»',
    'en': 'Unlock BTC — "{name}"',
  },
  'password_mismatch_hint': {
    'ru': 'Похоже, это пароль другого кошелька. Пароль — от '
        '«{name}»; при забытых паролях паре кошельков переключите '
        'кошелёк на Обзоре.',
    'en': 'This looks like another wallet\'s password. The password '
        'belongs to "{name}"; if the two wallets have different '
        'passwords, switch wallets on the dashboard.',
  },
  'connect_btn': {'ru': 'Подключиться', 'en': 'Connect'},
  'error_title': {'ru': 'Ошибка', 'en': 'Error'},
  'session_not_open': {'ru': 'Сессия не открыта', 'en': 'Session is not open'},
  'session_desc': {
    'ru': 'Подключение к Electrum-серверу выбранной сети.',
    'en': 'Connecting to the Electrum server of the selected network.',
  },
  'wallet_label': {'ru': 'Кошелёк: «{name}»', 'en': 'Wallet: "{name}"'},
  'unlock_btc_btn': {'ru': 'Разблокировать BTC', 'en': 'Unlock BTC'},
  'connection_section': {'ru': 'Подключение', 'en': 'Connection'},
  'network_label': {'ru': 'Сеть', 'en': 'Network'},
  'server_label': {'ru': 'Сервер', 'en': 'Server'},
  'xpub_note': {'ru': 'xpub (только публичный): ', 'en': 'xpub (public only): '},
  'lock_btn': {'ru': 'Заблокировать', 'en': 'Lock'},
  'balance_section': {'ru': 'Баланс', 'en': 'Balance'},
  'not_synced_note': {
    'ru': 'Ещё не синхронизировано. Синхронизация опрашивает сервер по всем '
        'адресам аккаунта (gap-limit 20).',
    'en': 'Not synced yet. Syncing polls the server across all the account '
        'addresses (gap limit 20).',
  },
  'sats': {'ru': 'сат', 'en': 'sat'},
  'mempool_row': {'ru': 'В мемпуле: {value}', 'en': 'In mempool: {value}'},
  'utxo_available': {'ru': 'UTXO доступно', 'en': 'UTXOs available'},
  'chain_height': {'ru': 'Высота чейна', 'en': 'Chain height'},
  'addresses_with_history': {
    'ru': 'Адресов с историей',
    'en': 'Addresses with history',
  },
  'sync_btn': {'ru': 'Синхронизировать', 'en': 'Sync'},
  'refresh_btn': {'ru': 'Обновить', 'en': 'Refresh'},
  'get_btn': {'ru': 'Получить', 'en': 'Receive'},
  'send_btn': {'ru': 'Отправить', 'en': 'Send'},
  'history_btn': {'ru': 'История', 'en': 'History'},
  // Получение.
  'receive_title': {'ru': 'Получение BTC', 'en': 'Receive BTC'},
  'receive_card_with_network': {
    'ru': 'Адрес получения ({network})',
    'en': 'Receiving address ({network})',
  },
  'receive_card_no_network': {
    'ru': 'Адрес получения (сеть не определена)',
    'en': 'Receiving address (network unknown)',
  },
  'address_label': {'ru': 'Адрес', 'en': 'Address'},
  'copy_address_btn': {'ru': 'Копировать адрес', 'en': 'Copy address'},
  'share_btn': {'ru': 'Поделиться', 'en': 'Share'},
  'share_note': {
    'ru': 'Системный Share появится в Android-группе: '
        'канал шерингa в этой сборке не подключён.',
    'en': 'The system Share lands with the Android group: the sharing '
        'channel is not wired in this build.',
  },
  'core_no_address': {
    'ru': 'Ядро не вернуло адрес: {error}{extra}',
    'en': 'The core returned no address: {error}{extra}',
  },
  'also_extra': {'ru': '\n(также: {error})', 'en': '\n(also: {error})'},
  'address_unavailable': {'ru': 'Адрес недоступен.', 'en': 'Address is unavailable.'},
  'copied_snackbar': {'ru': '{label} скопировано', 'en': '{label} copied'},
  // Общие компоненты.
  'copy_tooltip': {'ru': 'Копировать', 'en': 'Copy'},
  'dismiss_snackbar': {'ru': 'Скрыть', 'en': 'Dismiss'},
  'password_prompt': {'ru': 'Пароль', 'en': 'Password'},
  'password_hint': {'ru': 'Пароль кошелька', 'en': 'Wallet password'},
  'continue_default': {'ru': 'Продолжить', 'en': 'Continue'},
  'mnemonic_dialog_title': {'ru': 'Seed-фраза', 'en': 'Seed phrase'},
  'close_btn': {'ru': 'Закрыть', 'en': 'Close'},
  // Обзор — остатки.
  'favorites_card': {'ru': 'Избранные активы', 'en': 'Favorite assets'},
  'mempool_suffix': {'ru': '(мемпул)', 'en': '(mempool)'},
  'tx_internal_short': {'ru': 'Внутри кошелька', 'en': 'Internal'},
  'full_history': {'ru': 'Полная история', 'en': 'Full history'},
  // Детали транзакции.
  'tx_details_title': {'ru': 'Детали транзакции', 'en': 'Transaction details'},
  'direction_row': {'ru': 'Направление: {dir}', 'en': 'Direction: {dir}'},
  'tx_card': {'ru': 'Транзакция', 'en': 'Transaction'},
  'block_height_row': {'ru': 'Высота блока', 'en': 'Block height'},
  'in_mempool_short': {'ru': '— (в мемпуле)', 'en': '— (in mempool)'},
  'fee_row_label': {'ru': 'Комиссия', 'en': 'Fee'},
  'status_card': {'ru': 'Статус (запрос в ядро)', 'en': 'Status (core query)'},
  'status_read_error': {
    'ru': 'Статус не прочитан: {error}',
    'en': 'Status could not be read: {error}',
  },
  'retry_query_btn': {'ru': 'Повторить запрос', 'en': 'Retry query'},
  'status_confirmed': {'ru': 'Подтверждено сетью', 'en': 'Confirmed by network'},
  'status_mempool': {
    'ru': 'В мемпуле — не подтверждено',
    'en': 'In mempool — not confirmed',
  },
  'status_not_found': {'ru': 'Не найдено на сервере', 'en': 'Not found on the server'},
  'confirmations_row': {'ru': 'Подтверждения', 'en': 'Confirmations'},
  'server_height_row': {'ru': 'Высота (сервер)', 'en': 'Height (server)'},
  'network_explorer_card': {'ru': 'Сеть и explorer', 'en': 'Network and explorer'},
  'network_unknown': {'ru': '— (сеть не определена)', 'en': '— (network unknown)'},
  'explorer_note': {
    'ru': 'Explorer для этой сети не настроен ({name} '
        'поддерживает сети mainnet/testnet3/testnet4).',
    'en': 'No explorer is configured for this network ({name} '
        'supports mainnet/testnet3/testnet4).',
  },
  'summary_incoming': {
    'ru': 'Сумма получена на адреса кошелька: {value} сат.',
    'en': 'The amount was received at the wallet addresses: {value} sat.',
  },
  'summary_outgoing': {
    'ru': 'Чистый уход с кошелька (с учётом возврата сдачи): {value} сат.',
    'en': 'Net outflow from the wallet (change returned): {value} sat.',
  },
  'summary_internal': {
    'ru': 'Перевод между своими адресами: чистая сумма по кошельку равна нулю.',
    'en': 'Transfer between own addresses: the net wallet sum is zero.',
  },
  'summary_unknown': {
    'ru': 'Направление «{dir}» отдало ядро — суммы проверьте в explorer по TXID.',
    'en': 'The core reported direction "{dir}" — check the amounts in an '
        'explorer by TXID.',
  },
  // Детали монеты.
  'identification_card': {'ru': 'Идентификация', 'en': 'Identification'},
  'ticker_label': {'ru': 'Тикер', 'en': 'Ticker'},
  'name_label': {'ru': 'Имя', 'en': 'Name'},
  'implemented_in_core': {'ru': 'Реализован в ядре', 'en': 'Implemented in the core'},
  'yes': {'ru': 'да', 'en': 'yes'},
  'no': {'ru': 'нет', 'en': 'no'},
  'research_state_card': {
    'ru': 'Состояние исследования',
    'en': 'Research status',
  },
  'management_card': {
    'ru': 'Управление — реальный поток',
    'en': 'Management — the real flow',
  },
  'account_row': {'ru': 'Аккаунт', 'en': 'Account'},
  'funds_not_synced': {
    'ru': 'Средства ещё не синхронизированы',
    'en': 'Funds are not synced yet',
  },
  'session_closed_note': {
    'ru': 'Сессия закрыта: разблокировка происходит в центре управления '
        'по паролю кошелька (реальная, не имитация).',
    'en': 'Session is closed: unlocking happens in the control center '
        'with the wallet password (real, not imitated).',
  },
  'sync_note': {
    'ru': 'Баланс и транзакции появляются после явной синхронизации в центре '
        'управления (btcSync — сетевая операция, из экрана деталей '
        'не запускается). Receive/Send поверх реальных FFI-вызовов.',
    'en': 'Balances and transactions appear after an explicit sync in the '
        'control center (btcSync is a network operation; it is not started '
        'from the details screen). Receive/Send run over real FFI calls.',
  },
  'wallets_read_error': {
    'ru': 'Не удалось прочитать кошельки: {error}',
    'en': 'Wallets could not be read: {error}',
  },
  'no_wallets_btc': {
    'ru': 'Кошельков нет — создайте или импортируйте кошелёк, затем '
        'вернитесь к BTC.',
    'en': 'No wallets — create or import a wallet, then come back to BTC.',
  },
  'btc_wallet_field': {'ru': 'Кошелёк для BTC', 'en': 'Wallet for BTC'},
  'open_btc_center': {
    'ru': 'Открыть центр управления BTC',
    'en': 'Open the BTC control center',
  },
  'unlock_manage_btc': {
    'ru': 'Разблокировать и управлять BTC',
    'en': 'Unlock and manage BTC',
  },
  // LTC-центр (receive-only milestone: приём/баланс/история; отправка
  // LTC — отдельный этап).
  'unlock_ltc_btn': {
    'ru': 'Разблокировать LTC',
    'en': 'Unlock LTC',
  },
  'ltc_unlock_title': {
    'ru': 'Разблокировать LTC — «{name}»',
    'en': 'Unlock LTC — "{name}"',
  },
  'ltc_wallet_field': {'ru': 'Кошелёк для LTC', 'en': 'Wallet for LTC'},
  'open_ltc_center': {
    'ru': 'Открыть центр управления LTC',
    'en': 'Open the LTC control center',
  },
  'unlock_manage_ltc': {
    'ru': 'Разблокировать и управлять LTC',
    'en': 'Unlock and manage LTC',
  },
  'ltc_mweb_warning': {
    'ru': 'Лайткоин имеет расширение конфиденциальности MWEB: переводы '
        'в MWEB-адреса не видны этому кошельку. Баланс и история '
        'отражают только прозрачные (обычные) транзакции ltc1….',
    'en': 'Litecoin has the MWEB privacy extension: transfers to MWEB '
        'addresses are invisible to this wallet. Balance and history '
        'cover transparent (regular) ltc1… transactions only.',
  },
  'ltc_server_autopick_note': {
    'ru': 'Сервер Electrum-LTC подбирается автоматически из живых '
        'публичных (проверка genesis обязателен).',
    'en': 'The Electrum-LTC server is picked automatically from live '
        'public ones (the genesis check is mandatory).',
  },
  'ltc_unit': {'ru': 'лит.', 'en': 'lits'},
  'fav_remove_tooltip': {'ru': 'Убрать из избранного', 'en': 'Remove from favorites'},
  'fav_add_tooltip': {'ru': 'В избранное', 'en': 'Add to favorites'},
  // Кошельковый экран (портфель-карточка).
  'state_unavailable': {'ru': 'Состояние недоступно', 'en': 'State unavailable'},
  'open_btc_btn': {'ru': 'Открыть BTC', 'en': 'Open BTC'},
  'secrets_ui_note': {
    'ru': 'Секреты живут только внутри Rust-ядра: интерфейс ни разу не '
        'получает seed — лишь адреса и балансы.',
    'en': 'Secrets live only inside the Rust core: the UI never receives '
        'the seed — only addresses and balances.',
  },
  'session_open_synced': {
    'ru': 'Сессия открыта, синхронизирована',
    'en': 'Session open and synced',
  },
  'session_open_needs_sync': {
    'ru': 'Сессия открыта — нужна синхронизация',
    'en': 'Session open — sync needed',
  },
  'connect_tap_note': {
    'ru': 'Нажмите, чтобы подключиться к Electrum-серверу и синхронизировать '
        'баланс. Сеть и сервер настраиваются на экране BTC.',
    'en': 'Tap to connect to the Electrum server and sync the balance. '
        'Network and server are configured on the BTC screen.',
  },
  // Создание кошелька.
  'create_title': {'ru': 'Создание кошелька', 'en': 'Create a wallet'},
  'wallet_created_snack': {
    'ru': 'Кошелёк «{name}» создан',
    'en': 'Wallet "{name}" created',
  },
  'abort_title': {'ru': 'Прервать создание?', 'en': 'Abort creating?'},
  'abort_body': {
    'ru': 'Кошелёк ещё не прошёл проверку фразы. Отмена удалит его '
        'насовсем — вместе с записанной фразой. Если фраза уже переписана '
        'на бумагу и кошелёк нужен — пройдите проверку до конца.',
    'en': 'The wallet has not passed the phrase check yet. Cancelling '
        'deletes it for good — together with the recorded phrase. If the '
        'phrase is already written down and the wallet is needed — finish '
        'the check first.',
  },
  'delete_and_exit': {'ru': 'Удалить и выйти', 'en': 'Delete and exit'},
  'back_btn': {'ru': 'Назад', 'en': 'Back'},
  'step_next': {'ru': 'Далее', 'en': 'Next'},
  'step_create': {'ru': 'Создать кошелёк', 'en': 'Create'},
  'step_to_check': {'ru': 'Перейти к проверке', 'en': 'Go to the check'},
  'step_done': {'ru': 'Готово', 'en': 'Done'},
  'step_name_title': {'ru': 'Имя кошелька', 'en': 'Wallet name'},
  'step_name_subtitle': {
    'ru': 'Шаг 1 из 4. Кошелёк хранится зашифрованным на этом устройстве.',
    'en': 'Step 1 of 4. The wallet is stored encrypted on this device.',
  },
  'step_prefs_title': {'ru': 'Параметры кошелька', 'en': 'Wallet parameters'},
  'name_field': {'ru': 'Название', 'en': 'Name'},
  'step_password_title': {'ru': 'Пароль кошелька', 'en': 'Wallet password'},
  'step_password_subtitle': {
    'ru': 'Шаг 2 из 4. Расшифровывает хранилище на этом устройстве; '
        'восстановление пароля невозможно.',
    'en': 'Step 2 of 4. It decrypts the storage on this device; password '
        'recovery is impossible.',
  },
  'encryption_title': {'ru': 'Шифрование', 'en': 'Encryption'},
  'password_field': {'ru': 'Пароль', 'en': 'Password'},
  'password_min_helper': {
    'ru': 'Минимум {n} символов',
    'en': 'At least {n} characters',
  },
  'password_repeat_field': {'ru': 'Повтор пароля', 'en': 'Repeat password'},
  'password_min_note': {
    'ru': 'Пароль короче {n} символов — кнопка создания заблокирована.',
    'en': 'With a password shorter than {n} characters the create button '
        'stays disabled.',
  },
  'step_seed_title': {'ru': 'Резервная фраза', 'en': 'Recovery phrase'},
  'step_seed_subtitle': {
    'ru': 'Шаг 3 из 4. Показывается один раз — запишите её на бумаге.',
    'en': 'Step 3 of 4. Shown once — write it down on paper.',
  },
  'seed_header': {'ru': 'BIP39-фраза — 24 слова', 'en': 'BIP39 phrase — 24 words'},
  'shown_once_chip': {'ru': 'показ один раз', 'en': 'shown once'},
  'wrote_it_down_btn': {
    'ru': 'Я записал фразу на бумаге',
    'en': 'I wrote the phrase down',
  },
  'step_check_title': {'ru': 'Проверка фразы', 'en': 'Phrase check'},
  'step_check_subtitle': {
    'ru': 'Шаг 4 из 4. Введите слова на выбранных позициях.',
    'en': 'Step 4 of 4. Enter the words at the chosen positions.',
  },
  'enter_words_title': {'ru': 'Введите слова', 'en': 'Enter the words'},
  'word_n_field': {'ru': 'Слово № {n}', 'en': 'Word #{n}'},
  'position_n_of_m': {
    'ru': 'Позиция {n} из {m}',
    'en': 'Position {n} of {m}',
  },
  'check_after_all_words': {
    'ru': 'Проверка пройдёт после ввода всех четырёх слов.',
    'en': 'The check runs after all four words are entered.',
  },
  'matches_chip': {'ru': 'Совпадает', 'en': 'Matches'},
  // Импорт кошелька.
  'import_title': {'ru': 'Импорт кошелька', 'en': 'Import a wallet'},
  'wallet_restored_snack': {
    'ru': 'Кошелёк «{name}» восстановлен',
    'en': 'Wallet "{name}" restored',
  },
  'import_from_phrase_title': {
    'ru': 'Восстановление из фразы',
    'en': 'Restore from a phrase',
  },
  'import_from_phrase_subtitle': {
    'ru': 'Собственный BIP39-фразы достаточно для полного восстановления. '
        'Фраза остаётся на устройстве.',
    'en': 'A valid BIP39 phrase alone is enough for a full restoration. '
        'The phrase never leaves the device.',
  },
  'wallet_card': {'ru': 'Кошелёк', 'en': 'Wallet'},
  'wallet_name_field': {'ru': 'Название кошелька', 'en': 'Wallet name'},
  'phrase_field': {'ru': 'BIP39-фраза (12 или 24 слова)', 'en': 'BIP39 phrase (12 or 24 words)'},
  'words_entered': {'ru': 'Слов введено: {count}', 'en': 'Words entered: {count}'},
  'words_counter': {
    'ru': 'Слов: {count} — нужно 12 или 24',
    'en': 'Words: {count} — 12 or 24 needed',
  },
  'passphrase_field': {
    'ru': 'Passphrase (25-е слово, необязательно)',
    'en': 'Passphrase (25th word, optional)',
  },
  'device_encryption_title': {
    'ru': 'Шифрование на этом устройстве',
    'en': 'Encryption on this device',
  },
  'restore_wallet_btn': {
    'ru': 'Восстановить кошелёк',
    'en': 'Restore the wallet',
  },
  'implemented_tag': {'ru': '· реализован', 'en': '· implemented'},
  // Отправка BTC.
  'send_title': {'ru': 'Отправить BTC', 'en': 'Send BTC'},
  'recipient_card': {'ru': 'Получатель', 'en': 'Recipient'},
  'address_field': {
    'ru': 'Адрес (P2WPKH / P2SH / P2PKH / P2TR)',
    'en': 'Address (P2WPKH / P2SH / P2PKH / P2TR)',
  },
  'address_hint': {
    'ru': 'tb1q… для testnet, bc1q… для mainnet',
    'en': 'tb1q… for testnet, bc1q… for mainnet',
  },
  'amount_card': {'ru': 'Сумма', 'en': 'Amount'},
  'amount_field': {'ru': 'Сумма, BTC', 'en': 'Amount, BTC'},
  'available_row': {'ru': 'Доступно: {value} BTC', 'en': 'Available: {value} BTC'},
  'available_row_ltc': {
    'ru': 'Доступно: {value} LTC',
    'en': 'Available: {value} LTC',
  },
  'fee_card': {'ru': 'Комиссия и скорость', 'en': 'Fee and speed'},
  'fee_fast': {'ru': 'Быстро — {rate} sat/vB', 'en': 'Fast — {rate} sat/vB'},
  'fee_normal': {
    'ru': 'Обычно — {rate} sat/vB',
    'en': 'Normal — {rate} sat/vB',
  },
  'fee_slow': {'ru': 'Медленно — {rate} sat/vB', 'en': 'Slow — {rate} sat/vB'},
  'fee_manual_field': {
    'ru': 'Своя ставка, sat/vB',
    'en': 'Custom rate, sat/vB',
  },
  'fees_fallback_note': {
    'ru': 'Сервер не дал оценку комиссии — показаны консервативные '
        'дефолты, а не измерение. Ставку можно ввести вручную.',
    'en': 'The server returned no fee estimate — conservative defaults '
        'are shown, not a measurement. The rate can be set manually.',
  },
  'fees_error_note': {
    'ru': 'Пресеты сервера недоступны: {error}\nВведите ставку вручную (sat/vB).',
    'en': 'Server fee presets unavailable: {error}\nSet the rate manually (sat/vB).',
  },
  'send_submit_btn': {'ru': 'Отправить', 'en': 'Send'},
  'sending_now': {
    'ru': 'Подписание и broadcast…',
    'en': 'Signing and broadcasting…',
  },
  'sign_local_note': {
    'ru': 'Подпись выполняется локально в Rust (BIP143). Seed и '
        'приватные ключи не покидают ядро и не отправляются на сервер.',
    'en': 'Signing happens locally in Rust (BIP143). The seed and private '
        'keys never leave the core and are not sent to any server.',
  },
  'err_recipient': {
    'ru': 'Введите адрес получателя.',
    'en': 'Enter the recipient address.',
  },
  'err_amount': {
    'ru': 'Сумма задана некорректно: цифры и точка, до 8 знаков.',
    'en': 'Incorrect amount: digits and a dot, up to 8 decimals.',
  },
  'err_amount_positive': {
    'ru': 'Сумма должна быть больше нуля.',
    'en': 'The amount must be greater than zero.',
  },
  'err_fee_rate': {
    'ru': 'Ставка комиссии: целое sat/vB больше нуля.',
    'en': 'Fee rate: an integer sat/vB greater than zero.',
  },
  'err_send_rejected': {
    'ru': 'Ядро отклонило отправку: {error}',
    'en': 'The core rejected the send: {error}',
  },
  // Результат отправки.
  'tx_sent_title': {
    'ru': 'Транзакция отправлена',
    'en': 'Transaction sent',
  },
  'tx_already_known': {
    'ru': 'Эта транзакция уже была известна сети — повторная '
        'отправка не выполнялась (идемпотентный broadcast).',
    'en': 'This transaction was already known to the network — it was '
        'not broadcast again (idempotent broadcast).',
  },
  'tx_broadcast_chip': {
    'ru': 'Отправлено в сеть',
    'en': 'Broadcast to the network',
  },
  'tx_status_chip': {'ru': 'Статус: {status}', 'en': 'Status: {status}'},
  'tx_to_recipient': {
    'ru': '{value} получателю',
    'en': '{value} to the recipient',
  },
  'tx_fee_row': {
    'ru': 'Комиссия: {btc} BTC ({sats} сат, {vsize} vSize, {rate} sat/vB)',
    'en': 'Fee: {btc} BTC ({sats} sat, {vsize} vSize, {rate} sat/vB)',
  },
  'tx_fee_row_ltc': {
    'ru': 'Комиссия: {ltc} LTC ({sats} лит.)',
    'en': 'Fee: {ltc} LTC ({sats} lits)',
  },
  'change_label': {'ru': 'Сдача', 'en': 'Change'},
  'copy_txid': {'ru': 'Копировать TXID', 'en': 'Copy TXID'},
  'done_btn': {'ru': 'Готово', 'en': 'Done'},
  'error_prefix': {'ru': 'Ошибка: {error}', 'en': 'Error: {error}'},
  // Подтверждение отправки.
  'tx_confirm_title': {
    'ru': 'Подтверждение отправки',
    'en': 'Confirm the send',
  },
  'tx_asset_network': {'ru': 'Актив и сеть', 'en': 'Asset and network'},
  'asset_label': {'ru': 'Актив', 'en': 'Asset'},
  'confirm_network_desc': {
    'ru': 'Подпись выполняется в Rust-ядре для сети активной '
        'сессии; транзакция уйдёт только на выбранный '
        'Electrum-сервер.',
    'en': 'Signing happens in the Rust core for the active session '
        'network; the transaction goes only to the selected '
        'Electrum server.',
  },
  'recipient_amount_card': {
    'ru': 'Получатель и сумма',
    'en': 'Recipient and amount',
  },
  'no_active_session': {
    'ru': '— (сессия ядра не активна)',
    'en': '— (no core session)',
  },
  'speed_label': {'ru': 'Скорость', 'en': 'Speed'},
  'fee_final_note': {
    'ru': 'Финальная комиссия считается ядром при подписи '
        'и показывается в результате отправки.',
    'en': 'The final fee is computed by the core at signing time and is '
        'shown in the send result.',
  },
  'send_irreversible': {
    'ru': 'Отправка необратима. Перепроверьте адрес: '
        'транзакцию нельзя отменить после broadcast. '
        'Подпись локальная (BIP143): ключи не покидают ядро.',
    'en': 'The send is irreversible. Re-check the address: the '
        'transaction cannot be undone after broadcast. Signing is '
        'local (BIP143): keys never leave the core.',
  },
  'sign_send_btn': {
    'ru': 'Подписать и отправить',
    'en': 'Sign and send',
  },
  'core_session_read_error': {
    'ru': 'Ядро недоступно (состояние сессии BTC не прочитано): {error}',
    'en': 'Core unavailable (the BTC session state could not be read): {error}',
  },
  // История.
  'history_title': {'ru': 'История BTC', 'en': 'BTC history'},
  'sync_refresh_tooltip': {
    'ru': 'Синхронизировать и обновить (сетевая операция)',
    'en': 'Sync and refresh (a network operation)',
  },
  'sync_error_snackbar': {
    'ru': 'Ошибка синхронизации: {error}',
    'en': 'Sync failed: {error}',
  },
  'history_need_sync': {
    'ru': 'История собирается при синхронизации адресов. Выполните '
        'синхронизацию на экране BTC (или ниже).',
    'en': 'History is built while syncing addresses. Sync on the BTC '
        'screen (or below).',
  },
  'history_sync_btn': {
    'ru': 'Синхронизировать и обновить',
    'en': 'Sync and refresh',
  },
  'history_empty': {
    'ru': 'История пуста: ни один адрес кошелька ещё не получал средств '
        '(или не выполнена синхронизация).',
    'en': 'History is empty: no wallet address has received funds yet '
        '(or no sync has been run).',
  },
  'search_txid': {'ru': 'Поиск по TXID', 'en': 'Search by TXID'},
  'filter_incoming': {'ru': 'Входящие', 'en': 'Incoming'},
  'filter_outgoing': {'ru': 'Исходящие', 'en': 'Outgoing'},
  'filter_pending': {'ru': 'Ожидающие', 'en': 'Pending'},
  'filter_confirmed': {'ru': 'Подтверждённые', 'en': 'Confirmed'},
  'filter_failed': {'ru': 'Неудачные', 'en': 'Failed'},
  'failed_chip_tooltip': {
    'ru': 'Ядро не отдаёт неуспешные транзакции: их нет в истории. '
        'Фильтр оставлен отключённым, чтобы не имитировать работу.',
    'en': 'The core returns no failed transactions: they are absent from '
        'history. The filter stays disabled so nothing is imitated.',
  },
  'nothing_found_msg': {
    'ru': 'По текущему фильтру и поиску транзакций нет. '
        'Измените фильтр или очистите поиск.',
    'en': 'No transactions match the current filter and search. '
        'Change the filter or clear the search.',
  },
  'reset_filters': {
    'ru': 'Сбросить фильтр и поиск',
    'en': 'Reset filter and search',
  },
  'height_n': {'ru': 'высота {height}', 'en': 'height {height}'},
  'in_mempool': {'ru': 'в мемпуле', 'en': 'in mempool'},
  'unknown_direction': {
    'ru': 'Направление не определено',
    'en': 'Direction unknown',
  },
  'dir_incoming': {'ru': 'Получение', 'en': 'Incoming'},
  'dir_outgoing': {'ru': 'Отправка', 'en': 'Outgoing'},
  'dir_internal': {
    'ru': 'Смена адреса (внутри кошелька)',
    'en': 'Address change (within the wallet)',
  },
  'fee_prefix': {'ru': ' · комиссия {value}', 'en': ' · fee {value}'},
  // Welcome и вход.
  'welcome_create': {'ru': 'Создать кошелёк', 'en': 'Create a wallet'},
  'welcome_import_phrase': {
    'ru': 'Импорт кошелька из фразы',
    'en': 'Import from a seed phrase',
  },
  'welcome_note': {
    'ru': 'Адреса и балансы отображаются только на сетях с '
        'реализованными адаптерами. Остальные активы — справочно, '
        'после своих обновлений.\nСекреты не покидают устройство.',
    'en': 'Addresses and balances appear only for networks with '
        'implemented adapters. The other assets are reference-only '
        'until their updates.\nSecrets never leave the device.',
  },
  'lock_password_field': {'ru': 'Пароль кошелька', 'en': 'Wallet password'},
  'lock_submit': {'ru': 'Войти', 'en': 'Sign in'},
  'lock_switch_wallet': {'ru': 'Другой кошелёк', 'en': 'Another wallet'},
  'lock_empty_password': {
    'ru': 'Введите пароль кошелька.',
    'en': 'Enter the wallet password.',
  },
  'lock_wrong_password': {
    'ru': 'Неверный пароль для «{name}». '
        'Если у кошельков разные пароли — смените кошелёк ниже.',
    'en': 'Wrong password for "{name}". If the wallets have different '
        'passwords — switch the wallet below.',
  },
  'err_lock_connection': {
    'ru': 'Не удалось подключиться к серверу. Проверьте '
        'интернет-подключение и попробуйте ещё раз.',
    'en': 'Could not reach the server. Check your internet connection '
        'and try again.',
  },
  'error_detail_prefix': {'ru': 'подробности: ', 'en': 'details: '},
  'lock_registry_error': {
    'ru': 'Реестр кошельков недоступен: {error}',
    'en': 'The wallet registry is unavailable: {error}',
  },
  'lock_wallet_label': {
    'ru': 'Кошелёк «{name}»',
    'en': 'Wallet "{name}"',
  },
  'filter_all': {'ru': 'Все', 'en': 'All'},
  'filter_implemented': {'ru': 'Реализованные', 'en': 'Implemented'},
  'filter_researched': {'ru': 'Исследованные', 'en': 'Researched'},
  'filter_special': {'ru': 'Особые статусы', 'en': 'Special statuses'},
  'group_by_status': {'ru': 'Группировать по статусу', 'en': 'Group by status'},
  'sort_matrix': {'ru': 'Порядок матрицы', 'en': 'Matrix order'},
  'sort_az': {'ru': 'A→Я по тикеру', 'en': 'A→Z by ticker'},
  'catalog_note': {
    'ru': 'Справочник статусов {count} активов. Балансы и транзакции — '
        'только реализованные активы; остальное — честные вердикты '
        'матрицы, без имитаций.',
    'en': 'Status reference for {count} assets. Balances and transactions '
        '— implemented assets only; the rest is honest matrix verdicts, '
        'no imitation.',
  },
  'prefs_degraded_catalog': {
    'ru': 'Настройки не сохраняются: БД недоступна',
    'en': 'Preferences are not persisted: DB unavailable',
  },
  // Статусы жизненного цикла реестра.
  'lc_researched': {'ru': 'Исследовано', 'en': 'Researched'},
  'lc_receive_supported': {
    'ru': 'Приём проверен (live)',
    'en': 'Receives verified (live)',
  },
  'lc_send_supported': {
    'ru': 'Отправка проверена (testnet)',
    'en': 'Sends verified (testnet)',
  },
  'lc_research_required': {'ru': 'Требует изучения', 'en': 'Needs research'},
  'lc_blocked': {'ru': 'Заблокировано', 'en': 'Blocked'},
  'lc_historical': {'ru': 'Исторический тикер', 'en': 'Historical ticker'},
  // Выбор актива для отправки.
  'send_pick_title': {'ru': 'Отправка — выбор актива', 'en': 'Send — pick an asset'},
  'receive_pick_title': {'ru': 'Получение — выбор актива', 'en': 'Receive — pick an asset'},
  'session_open_chip': {
    'ru': 'Сессия: {network} — форма открыта',
    'en': 'Session: {network} — form is open',
  },
  'no_wallets_chip': {
    'ru': 'Нет кошельков — создать в «Кошельки»',
    'en': 'No wallets — create one in "Wallets"',
  },
  'wallet_not_chosen': {'ru': 'кошелёк не выбран', 'en': 'no wallet selected'},
  'session_closed_chip': {
    'ru': 'Сессия закрыта — разблокировать: {wallet}',
    'en': 'Session closed — unlock: {wallet}',
  },
  'session_pending_chip': {'ru': 'Статус сессии: …', 'en': 'Session status: …'},
  'disabled_adapter_tooltip': {
    'ru': 'Receive/Send недоступны: адаптер этой сети не реализован '
        'в ядре ({status}).',
    'en': 'Receive/Send unavailable: this network adapter is not '
        'implemented in the core ({status}).',
  },
};

/// Перевод с подстановкой переменных: t('wallet_deleted', {'name': x}).
String tf(String key, Map<String, String> vars) {
  var value = t(key);
  vars.forEach((name, replacement) {
    value = value.replaceAll('{$name}', replacement);
  });
  return value;
}

/// Перевод по выбранному языку; отсутствующий ключ/язык — русский.
String t(String key) {
  final entry = _strings[key];
  if (entry == null) return key;
  return entry[DisplayPrefs.language] ?? entry['ru'] ?? key;
}

/// Локализованная краткая характеристика сети актива (реестр): EN —
/// по карте точных совпадений; что не переведено — строка как есть.
String networkLabel(String network) {
  if (DisplayPrefs.language != 'en') return network;
  const en = <String, String>{
    'L1 · PoUW (AI-вычисления)': 'L1 · PoUW (AI computing)',
    'L1 · Substrate · постквантовая': 'L1 · Substrate · post-quantum',
    'L1 · Mimblewimble · гибридный PoW': 'L1 · Mimblewimble · hybrid PoW',
    'L1 · EVM-форк (GPU-рынок)': 'L1 · EVM fork (GPU market)',
    'L1 · форк Monero': 'L1 · Monero fork',
    'L1 · PoW (5 алгоритмов)': 'L1 · PoW (5 algorithms)',
    'L1 · PoW (форк BCH)': 'L1 · PoW (BCH fork)',
    'L1 · PoW SHA-256d (форк BTC)': 'L1 · PoW SHA-256d (BTC fork)',
    'L1 · BlockFlow (16 цепей)': 'L1 · BlockFlow (16 chains)',
    'L1 · Merge-mined SHA256d': 'L1 · merge-mined SHA256d',
  };
  return en[network] ?? network;
}
