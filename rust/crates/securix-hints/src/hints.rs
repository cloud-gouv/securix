// SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
//
// SPDX-License-Identifier: MIT

//! The interface that reads the hints.

#![allow(clippy::too_many_arguments)]

use serde::{Deserialize, Serialize};
use zlink::introspect;

pub use crate::types::{Hint, HintAction, HintsStatus};

/// The output of `ListHints`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, introspect::Type)]
pub struct ListHints {
    /// The hints that the daemon holds.
    pub hints: Vec<Hint>,
}

/// The output of `GetHint`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, introspect::Type)]
pub struct GetHint {
    /// The hint.
    pub hint: Hint,
}

/// The output of `GetStatus`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, introspect::Type)]
pub struct GetStatus {
    /// The summary of the daemon state.
    pub status: HintsStatus,
}

/// The errors of this interface.
#[derive(Debug, Clone, PartialEq, Eq, zlink::ReplyError, introspect::ReplyError)]
#[zlink(interface = "fr.gouv.securix.Hints")]
pub enum HintsError {
    /// The requested hint does not exist.
    HintNotFound {
        /// The producer name.
        source: String,
        /// The key of the hint.
        key: String,
    },
}

/// The client that reads the hints.
#[zlink::proxy("fr.gouv.securix.Hints")]
pub trait Hints {
    /// Return each hint with a severity at least `min_severity`.
    async fn list_hints(
        &mut self,
        min_severity: i64,
    ) -> zlink::Result<Result<ListHints, HintsError>>;

    /// Return one hint.
    async fn get_hint(
        &mut self,
        source: &str,
        key: &str,
    ) -> zlink::Result<Result<GetHint, HintsError>>;

    /// Return a summary of the daemon state.
    async fn get_status(&mut self) -> zlink::Result<Result<GetStatus, HintsError>>;

    /// Return the hints now, then one reply for each change.
    #[zlink(more)]
    async fn watch(
        &mut self,
    ) -> zlink::Result<impl futures_util::Stream<Item = zlink::Result<Result<ListHints, HintsError>>>>;
}
