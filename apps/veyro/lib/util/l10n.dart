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
  // Выбор актива (плитки без статус-пометок — решение владельца).
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
