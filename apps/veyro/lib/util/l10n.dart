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
