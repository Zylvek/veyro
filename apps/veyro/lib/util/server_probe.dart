//! Списки кандидатов Electrum-серверов по коду сети (решение владельца:
//! никакой ручной настройки — автоподбор). Разблокировка BTC перебирает
//! кандидатов ПОСЛЕДОВАТЕЛЬНО начиная с сохранённого дефолта; финальную
//! fund-safety-проверку (genesis, «чужая сеть — отказ») делает ядро на
//! каждом unlock — доверять списку не обязательно.
//!
//! Прозвон-подсистема (TCP/ELECTRUM-зонд с кэшем 3 минуты) была удалена
//! как мёртвый код: перебор кандидатов при unlock уже сам по себе честный
//! подбор, а параллельный прозвон рискует попасть под rate-limit публичных
//! серверов.

/// Кандидаты Electrum-серверов по коду сети. Для каждого есть
/// верифицированный дефолт, плюс альтернативы.
List<String> serverCandidates(int code) {
  switch (code) {
    case 0:
      return const [
        'ssl://fulcrum.bullbitcoin.com:50002',
        'ssl://electrum.blockstream.info:50002',
        'ssl://E-x.not.fyi:50002',
        'ssl://electrum.emzy.de:50002',
        'tcp://electrum.blockstream.info:50001',
      ];
    case 1:
      return const ['ssl://electrum.blockstream.info:60002'];
    case 2:
      return const ['ssl://blackie.c3-soft.com:57010'];
    default:
      return const [];
  }
}
