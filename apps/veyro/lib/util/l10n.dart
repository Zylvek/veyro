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
};

/// Перевод по выбранному языку; отсутствующий ключ/язык — русский.
String t(String key) {
  final entry = _strings[key];
  if (entry == null) return key;
  return entry[DisplayPrefs.language] ?? entry['ru'] ?? key;
}
