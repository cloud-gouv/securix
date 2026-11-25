// SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
//
// SPDX-License-Identifier: MIT

//! The interface that writes the hints.

#![allow(clippy::too_many_arguments)]

use serde::{Deserialize, Serialize};
use zlink::introspect;

pub use crate::types::HintAction;

/// The output of `UpsertHint`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, introspect::Type)]
pub struct UpsertHint {
    /// The identifier of the hint.
    pub id: String,
}

/// The errors of this interface.
#[derive(Debug, Clone, PartialEq, Eq, zlink::ReplyError, introspect::ReplyError)]
#[zlink(interface = "fr.gouv.securix.HintsControl")]
pub enum HintsControlError {
    /// The producer sent a hint that the daemon refuses.
    InvalidHint {
        /// The reason of the refusal.
        message: String,
    },
}

/// The client that writes the hints.
#[zlink::proxy("fr.gouv.securix.HintsControl")]
pub trait HintsControl {
    /// Create a hint, or update the hint with the same `source` and `key`.
    async fn upsert_hint(
        &mut self,
        source: &str,
        key: &str,
        kind: &str,
        severity: i64,
        title: &str,
        body: &str,
        expires_at: i64,
        actions: &[HintAction],
    ) -> zlink::Result<Result<UpsertHint, HintsControlError>>;

    /// Remove one hint.
    async fn clear_hint(
        &mut self,
        source: &str,
        key: &str,
    ) -> zlink::Result<Result<(), HintsControlError>>;

    /// Remove each hint of one source.
    async fn clear_source(&mut self, source: &str) -> zlink::Result<Result<(), HintsControlError>>;
}
