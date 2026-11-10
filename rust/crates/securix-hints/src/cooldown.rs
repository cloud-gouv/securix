// SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
//
// SPDX-License-Identifier: MIT

//! When to show a hint again.

use crate::severity;

/// The cooldown of an informational hint, in seconds.
pub const INFO_SECONDS: i64 = 24 * 60 * 60;

/// The cooldown of an advisory hint, in seconds.
pub const ADVISORY_SECONDS: i64 = 4 * 60 * 60;

/// The cooldown of an important hint, in seconds.
pub const IMPORTANT_SECONDS: i64 = 15 * 60;

/// The cooldown of a critical hint, in seconds.
pub const CRITICAL_SECONDS: i64 = 5 * 60;

/// Return the cooldown of `severity`, in seconds.
///
/// A severity outside the scale uses the cooldown of the nearest end.
#[must_use]
pub const fn seconds(severity: i64) -> i64 {
    if severity >= severity::CRITICAL {
        CRITICAL_SECONDS
    } else if severity == severity::IMPORTANT {
        IMPORTANT_SECONDS
    } else if severity == severity::ADVISORY {
        ADVISORY_SECONDS
    } else {
        INFO_SECONDS
    }
}

/// Return true if the agent must show the hint now.
///
/// `last_shown` is the last time the agent showed the hint. It is `None` if
/// the agent never showed the hint.
#[must_use]
pub const fn is_due(last_shown: Option<i64>, now: i64, severity: i64) -> bool {
    match last_shown {
        Some(last) => now - last >= seconds(severity),
        None => true,
    }
}

#[cfg(test)]
mod tests {
    use super::{is_due, ADVISORY_SECONDS};
    use crate::severity;

    #[test]
    fn a_hint_is_due_only_after_the_cooldown() {
        let now = 1_000;

        assert!(!is_due(Some(now), now, severity::ADVISORY));
        assert!(!is_due(
            Some(now),
            now + ADVISORY_SECONDS - 1,
            severity::ADVISORY
        ));
        assert!(is_due(
            Some(now),
            now + ADVISORY_SECONDS,
            severity::ADVISORY
        ));
    }
}
