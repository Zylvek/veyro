//! Адресная книга (спека UI 9.11): контакты с несколькими адресами,
//! метками и назначением актива/сети.
//!
//! Хранение — решение владельца (11.11.2026): локальные не-секретные
//! SQLite-настройки моста (db_set/db_get_setting), один ключ
//! `book.contacts` с JSON-массивом. Адреса и метки — не-секретные
//! данные по модели угроз (пароли/фразы — только в vault ядра).
//! При недоступной БД — честная деградация: данные живут только в
//! памяти сессии, UI показывает пометку. Никаких выдуманных контактов
//! по умолчанию: книга пуста, пока пользователь не добавил запись.

import 'dart:convert';

import 'package:veyro/src/rust/api/storage.dart';

/// Ключ настроек с JSON-массивом контактов.
const String kAddressBookKey = 'book.contacts';

/// Один адрес контакта: значение, метка, назначение (тикер/сеть).
class BookAddress {
  final String address;
  final String label;
  final String ticker;

  /// Код сети ядра (0 mainnet / 1 testnet3 / 2 testnet4) или null —
  /// «не указана» (для нереализованных активов сеть честно не назначить).
  final int? networkCode;

  const BookAddress({
    required this.address,
    required this.label,
    required this.ticker,
    this.networkCode,
  });

  Map<String, dynamic> toJson() => {
        'address': address,
        'label': label,
        'ticker': ticker,
        if (networkCode != null) 'networkCode': networkCode,
      };

  static BookAddress fromJson(Map<String, dynamic> json) => BookAddress(
        address: json['address'] as String,
        label: json['label'] as String? ?? '',
        ticker: json['ticker'] as String? ?? 'BTC',
        networkCode: json['networkCode'] as int?,
      );
}

/// Контакт: имя + список адресов (несколько у одного контакта — 9.11).
class BookContact {
  final String id;
  final String name;
  final List<BookAddress> addresses;

  const BookContact({
    required this.id,
    required this.name,
    required this.addresses,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'addresses': [for (final a in addresses) a.toJson()],
      };

  static BookContact fromJson(Map<String, dynamic> json) => BookContact(
        id: json['id'] as String,
        name: json['name'] as String,
        addresses: [
          for (final a in (json['addresses'] as List? ?? const []))
            BookAddress.fromJson((a as Map).cast<String, dynamic>()),
        ],
      );
}

/// Слой адресной книги. Функции чтения/записи настроек подменяемы
/// в тестах; в проде — db_get/db_set_setting моста.
class AddressBook {
  AddressBook._(this._contacts, this.storageHealthy);

  final List<BookContact> _contacts;
  List<BookContact> get contacts => List.unmodifiable(_contacts);  /// true — данные читаются/пишутся реальным хранилищем SQLite;
  /// false — только память этой сессии (БД недоступна), UI помечает.
  final bool storageHealthy;

  /// Точка замены для тестов: чтение настройки по ключу.
  Future<String?> Function(String key)? settingLoader;

  /// Точка замены для тестов: запись значения по ключу.
  Future<void> Function(String key, String value)? settingSaver;

  static Future<String?> _realLoad(String key) => dbGetSetting(key: key);
  static Future<void> _realSave(String key, String value) =>
      dbSetSetting(key: key, value: value);

  /// Загрузка книги. Ошибка хранилища → пустая книга в памяти
  /// (storageHealthy == false) — не фейк, а честная деградация.
  static Future<AddressBook> load({
    Future<String?> Function(String key)? settingLoader,
  }) async {
    try {
      final raw = await (settingLoader ?? _realLoad)(kAddressBookKey);
      return AddressBook._(_decode(raw), true)
        ..settingLoader = settingLoader;
    } catch (_) {
      return AddressBook._(const [], false)
        ..settingLoader = settingLoader;
    }
  }

  static List<BookContact> decodeJson(String raw) => _decode(raw);

  static List<BookContact> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final c in decoded)
        if (c is Map) BookContact.fromJson(c.cast<String, dynamic>()),
    ];
  }

  static String _encode(List<BookContact> contacts) =>
      jsonEncode([for (final c in contacts) c.toJson()]);

  /// Добавить/обновить контакт и сохранить. Отказ хранилища не
  /// выбрасывается: книга сохраняется в памяти с пометкой degraded.
  Future<AddressBook> upsert(BookContact contact) async {
    final next = _contacts.where((c) => c.id != contact.id).toList()
      ..add(contact);
    return _persist(next);
  }

  Future<AddressBook> remove(String contactId) =>
      _persist(_contacts.where((c) => c.id != contactId).toList());

  Future<AddressBook> _persist(List<BookContact> next) async {
    try {
      await (settingSaver ?? _realSave)(kAddressBookKey, _encode(next));
      return AddressBook._(next, true)
        ..settingLoader = settingLoader
        ..settingSaver = settingSaver;
    } catch (_) {
      return AddressBook._(next, false)
        ..settingLoader = settingLoader
        ..settingSaver = settingSaver;
    }
  }
}

/// Префиксная эвристика совместимости BTC-адреса с сетью. Это ТОЛЬКО
/// эвристика: полноценная проверка скрипта происходит в ядре при подписи.
/// Возвращает: true — совместим, false — префикс чужой сети,
/// null — по префиксу не отличить (testnet3/testnet4 оба tb1/m/n/2)
/// или для не-BTC активов эвристики нет.
bool? addressNetworkCompatible(String address, int? networkCode) {
  final a = address.trim();
  if (a.isEmpty) return null;
  switch (networkCode) {
    case 0: // mainnet: bc1… (bech32/bech32m), 1…/3… (P2PKH/P2SH)
      if (a.startsWith('bc1') ||
          a.startsWith('1') ||
          a.startsWith('3')) {
        return true;
      }
      return false;
    case 1: // testnet3: tb1…, m/n/2… (легаси-совместимость)
      if (a.startsWith('tb1') ||
          a.startsWith('m') ||
          a.startsWith('n') ||
          a.startsWith('2')) {
        return true;
      }
      return false;
    case 2: // testnet4: тот же tb1…/m/n/2 — по префиксу не отличить
      // от testnet3; честный null (ядро проверит при подписи).
      if (a.startsWith('tb1') ||
          a.startsWith('m') ||
          a.startsWith('n') ||
          a.startsWith('2')) {
        return null;
      }
      return false;
    default:
      return null;
  }
}
