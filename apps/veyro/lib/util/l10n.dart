//! Словарь интерфейса VEYRO (решение владельца: «в настройках добавь
//! поддержку других языков»). Русский — база; English переводит
//! основную оболочку (Обзор, настройки, каталог); редкие глубокие
//! экраны и честные статусы сетей добираются по ходу обновлений.
//! Использование: t('total_balance').

import 'package:veyro/util/display_prefs.dart';

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
  // Каталог: фильтры и честная поясняющая строка.
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
