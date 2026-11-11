//! Экран 18 спеки: Address book. Контакты с несколькими адресами, метками
//! и назначением актива/сети (9.11). Хранится локально в SQLite-настройках
//! моста (решение владельца); при недоступной БД — честная деградация в
//! память сессии с пометкой. Совместимость адреса с сетью: префиксная
//! эвристика на экране, полная проверка — в ядре при подписи. «Отправить»
//! работает только для BTC (реализован один адаптер); прочие тикеры —
//! честно отключены. Данные экрана — только AddressBook; никаких
//! выдуманных контактов по умолчанию.

import 'package:flutter/material.dart';

import 'package:veyro/data/asset_registry.dart';
import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/util/address_book.dart';
import 'package:veyro/util/ui_helpers.dart';

import 'send_screen.dart';

class AddressBookScreen extends StatefulWidget {
  /// Точка замены для тестов/прод-хранилища: чтение настройки по ключу.
  final Future<String?> Function(String key)? settingLoader;

  /// Точка замены: запись настройки по ключу (в проде оставить null —
  /// AddressBook использует реальный dbSetSetting).
  final Future<void> Function(String key, String value)? settingSaver;

  const AddressBookScreen({super.key, this.settingLoader, this.settingSaver});

  @override
  State<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends State<AddressBookScreen> {
  AddressBook? _book;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    // AddressBook.load никогда не бросает: без хранилища — честная
    // деградация в книгу в памяти (storageHealthy=false, UI пометит).
    final book = await AddressBook.load(settingLoader: widget.settingLoader);
    book.settingSaver ??= widget.settingSaver;
    if (!mounted) return;
    setState(() {
      _book = book;
      _loading = false;
    });
  }

  /// Диалог создания/редактирования контакта. После диалога оперируем
  /// копией книги в памяти: перечитывать хранилище не нужно
  /// (однопользовательский локальный UI), сохранение делает upsert.
  Future<void> _openContactDialog({BookContact? existing}) async {
    final book = _book;
    if (book == null) return;
    final saved = await showDialog<BookContact>(
      context: context,
      builder: (_) => _ContactDialog(existing: existing),
    );
    if (saved == null) return;
    final next = await book.upsert(saved);
    if (!mounted) return;
    setState(() => _book = next);
  }

  /// Удаление — с явным подтверждением (спека 9.11).
  Future<void> _deleteContact(BookContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Удалить «${contact.name}»?'),
        content: const Text(
            'Контакт, его адреса и метки удалятся из локального '
            'хранилища настроек. Данные ядра (кошельки, история) '
            'не затрагиваются.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: VColors.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final book = _book;
    if (book == null) return;
    final next = await book.remove(contact.id);
    if (!mounted) return;
    setState(() => _book = next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Адресная книга'),
        actions: [
          IconButton(
            tooltip: 'Добавить контакт',
            icon: const Icon(Icons.person_add_outlined),
            onPressed: _book == null || _loading ? null : () => _openContactDialog(),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final book = _book;
    if (_loading || book == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (!book.storageHealthy)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: VStatusChip(
                  'Хранилище настроек недоступно: изменения сохранятся '
                  'только до закрытия приложения',
                  kind: VChipKind.warning,
                ),
              ),
            ),
          Text(
            'Контакты, метки и назначение актив/сеть хранятся локально '
            '(адреса — не-секретные данные). Совместимость с сетью здесь '
            '— префиксная эвристика; перед подписью ядро проверит адрес '
            'полностью.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (book.contacts.isEmpty)
            VEmptyState(
              icon: Icons.import_contacts_outlined,
              title: 'Контактов нет',
              message: 'Добавьте первый контакт кнопкой «+» в панели '
                  'приложения: имя, адреса с метками и назначением '
                  'актив/сеть. Данные — только локальные.',
            )
          else
            for (final contact in book.contacts)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ContactCard(
                  contact: contact,
                  onEdit: () => _openContactDialog(existing: contact),
                  onDelete: () => _deleteContact(contact),
                ),
              ),
        ],
      ),
    );
  }
}

/// Карточка контакта: имя + адреса (метка/тикер/сеть), копирование и
/// переход в реальную отправку для BTC-адресов.
class _ContactCard extends StatelessWidget {
  final BookContact contact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ContactCard({
    required this.contact,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return VCard(
      title: contact.name,
      icon: Icons.import_contacts_outlined,
      children: [
        if (contact.addresses.isEmpty)
          Text('Адресов в контакте нет.',
              style: Theme.of(context).textTheme.bodySmall)
        else
          for (final a in contact.addresses)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          a.label.isEmpty ? '(без метки)' : a.label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      _CompatChip(address: a),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: VMono(a.address, fontSize: 12)),
                      IconButton(
                        tooltip: 'Копировать адрес',
                        icon: const Icon(Icons.copy_outlined, size: 16),
                        color: VColors.textSecondary,
                        onPressed: () =>
                            copyToClipboard(context, 'Адрес', a.address),
                      ),
                      _SendAction(address: a),
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      VStatusChip(a.ticker, kind: VChipKind.info),
                      if (a.networkCode != null)
                        VStatusChip(
                          switch (a.networkCode) {
                            0 => 'mainnet',
                            1 => 'testnet3',
                            2 => 'testnet4',
                            _ => 'сеть ${a.networkCode}',
                          },
                          kind: VChipKind.neutral,
                        ),
                    ],
                  ),
                ],
              ),
            ),
        const Divider(height: 20),
        Row(
          children: [
            TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Редактировать'),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline, size: 16, color: VColors.error),
              label: Text('Удалить', style: TextStyle(color: VColors.error)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Эвристический статус совместимости адреса с назначенной сетью:
/// true — совместим (чип не нужен), false — префикс чужой сети (ошибка),
/// null при заданной сети — префиксы testnet3/testnet4 совпадают,
/// ядро проверит при подписи (предупреждение).
class _CompatChip extends StatelessWidget {
  final BookAddress address;

  const _CompatChip({required this.address});

  @override
  Widget build(BuildContext context) {
    final compat =
        addressNetworkCompatible(address.address, address.networkCode);
    switch (compat) {
      case true:
        return const SizedBox.shrink();
      case false:
        return const VStatusChip(
          'Префикс не совпадает с сетью',
          kind: VChipKind.error,
        );
      case null:
        if (address.networkCode != null) {
          return const VStatusChip(
            'По префиксу не отличить — проверит ядро',
            kind: VChipKind.warning,
          );
        }
        return const SizedBox.shrink();
    }
  }
}

/// «Отправить на адрес»: только BTC и только если префикс не явно
/// чужой. Не-BTC и явно несовместимые адреса — честно отключены.
class _SendAction extends StatelessWidget {
  final BookAddress address;

  const _SendAction({required this.address});

  @override
  Widget build(BuildContext context) {
    final isBtc = address.ticker == 'BTC';
    final compat = addressNetworkCompatible(
      address.address,
      address.networkCode,
    );
    final blocked = !isBtc || compat == false;
    return IconButton(
      tooltip: blocked
          ? (isBtc
              ? 'Адрес сохранён с префиксом чужой сети — отправка '
                  'заблокирована до исправления'
              : 'Отправка доступна только для BTC: остальные адаптеры '
                  'нереализованы в ядре')
          : 'Отправить на этот адрес',
      icon: Icon(
        Icons.north_east,
        size: 18,
        color: blocked ? VColors.textSecondary : VColors.primary,
      ),
      onPressed: blocked
          ? null
          : () {
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => SendScreen(initialRecipient: address.address),
              ));
            },
    );
  }
}

/// Черновик адреса внутри диалога контакта.
class _AddrDraft {
  final TextEditingController addressCtrl;
  final TextEditingController labelCtrl;
  String ticker;
  int? networkCode;

  _AddrDraft({String address = '', String label = '', this.ticker = 'BTC', this.networkCode})
      : addressCtrl = TextEditingController(text: address),
        labelCtrl = TextEditingController(text: label);

  BookAddress? toBook() {
    final addr = addressCtrl.text.trim();
    if (addr.isEmpty) return null;
    return BookAddress(
      address: addr,
      label: labelCtrl.text.trim(),
      ticker: ticker,
      networkCode: ticker == 'BTC' ? networkCode : null,
    );
  }

  void dispose() {
    addressCtrl.dispose();
    labelCtrl.dispose();
  }
}

/// Диалог создания/редактирования контакта: имя + редактор адресов
/// (адрес, метка, тикер из справочника, сеть — только для BTC).
class _ContactDialog extends StatefulWidget {
  final BookContact? existing;

  const _ContactDialog({this.existing});

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  late final TextEditingController _nameCtrl;
  late final List<_AddrDraft> _drafts;
  String? _error;

  static List<String> _tickerChoices() => [
        'BTC',
        for (final a in kAssetRegistry)
          if (a.ticker != 'BTC') a.ticker,
      ];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _drafts = [
      for (final a in existing?.addresses ?? const <BookAddress>[])
        _AddrDraft(
          address: a.address,
          label: a.label,
          ticker: a.ticker,
          networkCode: a.networkCode,
        ),
      // Новый контакт начинается с одной пустой строки адреса.
      if (existing == null) _AddrDraft(),
    ];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  void _addAddress() => setState(() => _drafts.add(_AddrDraft()));

  void _removeAddress(int index) =>
      setState(() => _drafts.removeAt(index).dispose());

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Введите имя контакта.');
      return;
    }
    if (_drafts.isEmpty) {
      setState(() => _error = 'Добавьте хотя бы один адрес.');
      return;
    }
    final addresses = <BookAddress>[];
    for (final d in _drafts) {
      final a = d.toBook();
      if (a == null) {
        setState(() =>
            _error = 'Строка адреса пуста — заполните или удалите её.');
        return;
      }
      addresses.add(a);
    }
    final id = widget.existing?.id ?? 'c${DateTime.now().microsecondsSinceEpoch}';
    Navigator.of(context).pop(
      BookContact(id: id, name: name, addresses: addresses),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Новый контакт'
          : 'Редактирование контакта'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameCtrl,
                autocorrect: false,
                enableIMEPersonalizedLearning: false,
                decoration: const InputDecoration(
                  labelText: 'Имя контакта',
                  hintText: 'Алиса',
                ),
              ),
              const SizedBox(height: 14),
              if (_drafts.isEmpty)
                Text(
                  'Адресов нет — добавьте хотя бы один.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              for (var i = 0; i < _drafts.length; i++)
                _buildAddressEditor(context, i),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addAddress,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Добавить адрес'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(
                  _error!,
                  style: TextStyle(color: VColors.error, fontSize: 13),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                'Сеть назначается только для BTC (адаптер реализован). '
                'Префиксная эвристика: перед подписью ядро проверит '
                'адрес полностью.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }

  Widget _buildAddressEditor(BuildContext context, int index) {
    final draft = _drafts[index];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Адрес ${index + 1}',
                    style: const TextStyle(
                        fontSize: 12, color: VColors.textSecondary),
                  ),
                ),
                IconButton(
                  tooltip: 'Удалить адрес',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: VColors.textSecondary,
                  onPressed: () => _removeAddress(index),
                ),
              ],
            ),
            TextField(
              controller: draft.addressCtrl,
              autocorrect: false,
              enableIMEPersonalizedLearning: false,
              maxLines: 2,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: 'Адрес',
                hintText: 'tb1q… / bc1q… / 1… / 3… / m…',
              ),
            ),
            TextField(
              controller: draft.labelCtrl,
              autocorrect: false,
              enableIMEPersonalizedLearning: false,
              decoration: const InputDecoration(
                labelText: 'Метка',
                hintText: 'Холодный кошелёк, биржа, сдача…',
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: draft.ticker,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Актив (тикер)',
              ),
              onChanged: (t) => setState(() {
                draft.ticker = t ?? 'BTC';
                // Сеть назначается только для BTC: у нереализованных
                // адаптеров честно остаётся «не задана».
                if (draft.ticker != 'BTC') draft.networkCode = null;
              }),
              items: [
                for (final ticker in _tickerChoices())
                  DropdownMenuItem(
                    value: ticker,
                    child: Text(ticker),
                  ),
              ],
            ),
            if (draft.ticker == 'BTC') ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<int?>(
                initialValue: draft.networkCode,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Сеть (BTC)',
                ),
                onChanged: (v) => setState(() => draft.networkCode = v),
                items: const [
                  DropdownMenuItem<int?>(
                    value: null,
                    child: Text('— не задана'),
                  ),
                  DropdownMenuItem<int?>(
                    value: 0,
                    child: Text('Mainnet (0)'),
                  ),
                  DropdownMenuItem<int?>(
                    value: 1,
                    child: Text('Testnet 3 (1)'),
                  ),
                  DropdownMenuItem<int?>(
                    value: 2,
                    child: Text('Testnet 4 (2)'),
                  ),
                ],
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Сеть не назначается: адаптер этого актива не реализован.',
                  style: TextStyle(
                      fontSize: 12, color: VColors.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
