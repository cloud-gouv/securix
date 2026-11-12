// SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
//
// SPDX-License-Identifier: MIT

//! The severity scale.

/// An informational hint. No action is expected.
pub const INFO: i64 = 0;

/// An advisory hint.
pub const ADVISORY: i64 = 1;

/// An important hint.
pub const IMPORTANT: i64 = 2;

/// A critical hint. The user cannot hide it.
pub const CRITICAL: i64 = 3;

/// The highest value of the scale.
pub const MAX: i64 = CRITICAL;

/// Return true if `value` is a value of the scale.
#[must_use]
pub const fn is_valid(value: i64) -> bool {
    value >= INFO && value <= MAX
}
