//! Where the core gets fresh ids, random numbers and the time of day.
//!
//! By default these are a v4 uuid, the thread rng and the local clock. A host
//! that needs reproducible runs (replay tests, a browser page compared against
//! the desktop app) installs its own [`Sources`] for the current thread with
//! [`with_sources`] or [`set_sources`]; [`Seeded`] is the deterministic one.

use std::cell::RefCell;

use chrono::NaiveDateTime;

/// What the core asks the outside world for.
pub trait Sources {
    /// An id unique within one document.
    fn new_id(&mut self) -> String;
    /// A whole number in `lo..=hi` (`lo <= hi`).
    fn random_int(&mut self, lo: i64, hi: i64) -> i64;
    /// A number in `lo..=hi` (`lo <= hi`).
    fn random_float(&mut self, lo: f64, hi: f64) -> f64;
    /// The local wall clock.
    fn now(&mut self) -> NaiveDateTime;
}

/// The default: uuids, the thread rng and the local clock.
pub struct System;

impl Sources for System {
    fn new_id(&mut self) -> String {
        uuid::Uuid::new_v4().simple().to_string()
    }

    fn random_int(&mut self, lo: i64, hi: i64) -> i64 {
        use rand::RngExt;
        rand::rng().random_range(lo..=hi)
    }

    fn random_float(&mut self, lo: f64, hi: f64) -> f64 {
        use rand::RngExt;
        rand::rng().random_range(lo..=hi)
    }

    fn now(&mut self) -> NaiveDateTime {
        chrono::Local::now().naive_local()
    }
}

/// Deterministic sources: counted ids, a seeded generator and a fixed clock.
/// Two runs built with the same seed and clock ask for the same values.
pub struct Seeded {
    counter: u64,
    state: u64,
    /// What `now` answers; move it to advance time.
    pub clock: NaiveDateTime,
}

impl Seeded {
    pub fn new(seed: u64, clock: NaiveDateTime) -> Self {
        Self {
            counter: 0,
            state: seed,
            clock,
        }
    }

    // splitmix64: small, and the same on every target.
    fn next(&mut self) -> u64 {
        self.state = self.state.wrapping_add(0x9e37_79b9_7f4a_7c15);
        let mut z = self.state;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
        z ^ (z >> 31)
    }
}

impl Sources for Seeded {
    fn new_id(&mut self) -> String {
        self.counter += 1;
        // Same length and alphabet as a simple uuid, so nothing downstream
        // can tell the difference.
        format!("{:032x}", self.counter)
    }

    fn random_int(&mut self, lo: i64, hi: i64) -> i64 {
        let span = (hi as i128 - lo as i128 + 1) as u128;
        (lo as i128 + (self.next() as u128 % span) as i128) as i64
    }

    fn random_float(&mut self, lo: f64, hi: f64) -> f64 {
        let unit = (self.next() >> 11) as f64 / (1u64 << 53) as f64;
        lo + unit * (hi - lo)
    }

    fn now(&mut self) -> NaiveDateTime {
        self.clock
    }
}

thread_local! {
    static SOURCES: RefCell<Option<Box<dyn Sources>>> = const { RefCell::new(None) };
}

/// Installs `sources` for this thread until replaced or cleared (`None`).
/// Returns what was installed before.
pub fn set_sources(sources: Option<Box<dyn Sources>>) -> Option<Box<dyn Sources>> {
    SOURCES.with(|s| s.replace(sources))
}

/// Runs `f` with `sources` installed on this thread, then puts back whatever
/// was there, even if `f` panics.
pub fn with_sources<R>(sources: impl Sources + 'static, f: impl FnOnce() -> R) -> R {
    struct Restore(Option<Box<dyn Sources>>);
    impl Drop for Restore {
        fn drop(&mut self) {
            set_sources(self.0.take());
        }
    }
    let _restore = Restore(set_sources(Some(Box::new(sources))));
    f()
}

fn ask<R>(f: impl FnOnce(&mut dyn Sources) -> R) -> R {
    SOURCES.with(|s| match s.borrow_mut().as_mut() {
        Some(sources) => f(sources.as_mut()),
        None => f(&mut System),
    })
}

pub fn new_id() -> String {
    ask(|s| s.new_id())
}

pub fn random_int(lo: i64, hi: i64) -> i64 {
    ask(|s| s.random_int(lo, hi))
}

pub fn random_float(lo: f64, hi: f64) -> f64 {
    ask(|s| s.random_float(lo, hi))
}

pub fn now() -> NaiveDateTime {
    ask(|s| s.now())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn clock() -> NaiveDateTime {
        chrono::NaiveDate::from_ymd_opt(2026, 10, 23)
            .unwrap()
            .and_hms_opt(9, 30, 0)
            .unwrap()
    }

    #[test]
    fn seeded_sources_repeat_and_restore() {
        let run = || {
            with_sources(Seeded::new(7, clock()), || {
                (
                    new_id(),
                    new_id(),
                    random_int(1, 6),
                    random_float(0.0, 1.0),
                    now(),
                )
            })
        };
        let (a, b) = (run(), run());
        assert_eq!(a, b);
        assert_eq!(a.0, format!("{:032x}", 1));
        assert_ne!(a.0, a.1);
        assert!((1..=6).contains(&a.2));
        assert!((0.0..=1.0).contains(&a.3));
        assert_eq!(a.4, clock());
        // Outside the scope the system sources are back.
        assert_eq!(new_id().len(), 32);
        assert_ne!(new_id(), format!("{:032x}", 1));
    }

    #[test]
    fn seeded_ints_cover_the_range() {
        let mut s = Seeded::new(1, clock());
        let mut seen = [false; 3];
        for _ in 0..200 {
            seen[(s.random_int(-1, 1) + 1) as usize] = true;
        }
        assert_eq!(seen, [true; 3]);
        // The full range doesn't overflow.
        s.random_int(i64::MIN, i64::MAX);
    }
}
