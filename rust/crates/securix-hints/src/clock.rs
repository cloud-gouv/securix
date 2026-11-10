// SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
//
// SPDX-License-Identifier: MIT

use std::path::PathBuf;

/// Return the Unix time now, in seconds.
#[must_use]
pub fn now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |duration| {
            i64::try_from(duration.as_secs()).unwrap_or(i64::MAX)
        })
}

/// Return a new random identifier.
#[must_use]
pub fn new_id() -> String {
    uuid::Uuid::new_v4().to_string()
}

/// Return the delay between two removals of the expired hints.
#[must_use]
pub fn sweep_interval() -> std::time::Duration {
    std::env::var("SECURIX_HINTS_SWEEP_INTERVAL_SECONDS")
        .ok()
        .and_then(|value| value.parse::<u64>().ok())
        .map_or(
            std::time::Duration::from_secs(60),
            std::time::Duration::from_secs,
        )
}

/// Return the path of the store.
#[must_use]
pub fn store_path() -> PathBuf {
    std::env::var("SECURIX_HINTS_STORE")
        .map_or_else(|_| PathBuf::from(crate::STORE_PATH), PathBuf::from)
}
