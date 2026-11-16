//! Внутрипроцессный троттлинг неудачных разблокировок (per-wallet).
//!
//! Угроза: процессное приложение держит FFI-границу открытой; локальный
//! вредоносный код в том же доверенном контексте (или ошибка/скрипт в UI)
//! теоретически мог бы крутить `btc_unlock`/`ltc_unlock` в цикле — Argon2id
//! (64 MiB, t=3) и так стоит дорого, но на быстрой машине это всё равно
//! сотни попыток в минуту. ОФФЛАЙН-атака на vault-файл троттлингом не
//! решается (это сугубо сила KDF), здесь — defense-in-depth против
//! онлайн-перебора через собственный интерфейс.
//!
//! Правила:
//! - счётчик неудачных РАСШИФРОВОК (generic-ошибка vault) per wallet_id;
//! - с 3-й неудачи перед ответом держится растущая пауза
//!   (250 мс · 2^(n-3), кап 4 с) — ошибки остаются честными, ничего не
//!   ломается, перебор становится бессмысленным;
//! - успех сбрасывает счётчик кошелька;
//! - карта живёт в памяти процесса ( Zeroizing-пароли сюда не попадают:
//!   только счётчики) и умирает с процессом — как и весь session state.

use std::collections::HashMap;
use std::sync::{Mutex, MutexGuard};
use std::thread::sleep;
use std::time::Duration;

/// Неудач, после которых начинается штрафная пауза.
const FREE_ATTEMPTS: u32 = 3;
/// Базовый штраф и кап (мс).
const BASE_PENALTY_MS: u64 = 250;
const MAX_PENALTY_MS: u64 = 4000;

static FAILURES: Mutex<Option<HashMap<String, u32>>> = Mutex::new(None);

fn with_lock() -> Result<MutexGuard<'static, Option<HashMap<String, u32>>>, String> {
    FAILURES
        .lock()
        .map_err(|_| "unlock throttle mutex poisoned".to_string())
}

/// Зарегистрировать неудачную расшифровку и ПОДЕРЖАТЬ штрафную паузу,
/// если счётчик уже дожил до лимита. Ошибка наружу не меняется.
pub fn register_failure(wallet_id: &str) {
    let penalty;
    {
        let mut guard = match with_lock() {
            Ok(g) => g,
            Err(_) => return, // сломанный замок не ухудшает честность ответа
        };
        let map = guard.get_or_insert_with(HashMap::new);
        let failures = map.entry(wallet_id.to_string()).or_insert(0);
        *failures = failures.saturating_add(1);
        if *failures < FREE_ATTEMPTS {
            return;
        }
        let extra = *failures - FREE_ATTEMPTS;
        penalty = BASE_PENALTY_MS
            .saturating_mul(1u64 << extra.min(24))
            .min(MAX_PENALTY_MS);
    }
    // Пауза ПОД замком не держим: sleep наружу, замок уже отпущен.
    sleep(Duration::from_millis(penalty));
}

/// Успешная разблокировка — счётчик кошелька сбрасывается.
pub fn register_success(wallet_id: &str) {
    if let Ok(mut guard) = with_lock() {
        if let Some(map) = guard.as_mut() {
            map.remove(wallet_id);
            if map.is_empty() {
                *guard = None;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn penalty_starts_after_free_attempts_and_success_resets() {
        let id = "throttle-test-wallet";
        // Тесты в одном процессе: уникальный id изолирует состояние.
        let t0 = std::time::Instant::now();
        register_failure(id); // 1 — бесплатно
        register_failure(id); // 2 — бесплатно
        let free_elapsed = t0.elapsed();
        let t1 = std::time::Instant::now();
        register_failure(id); // 3 — штраф 250 мс
        let penalized = t1.elapsed();
        assert!(
            penalized.as_millis() >= 250,
            "третья неудача обязана получить штраф, got {penalized:?} (free {free_elapsed:?})"
        );
        assert!(free_elapsed.as_millis() < 250);

        register_success(id);
        let t2 = std::time::Instant::now();
        register_failure(id); // снова 1 — бесплатно
        assert!(t2.elapsed().as_millis() < 250);
        register_success(id);
    }
}
