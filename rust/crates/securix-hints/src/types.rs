// SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
//
// SPDX-License-Identifier: MIT

//! The types that the two interfaces have.

use serde::{Deserialize, Serialize};
use zlink::introspect;

/// One action that the user can select.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, introspect::CustomType)]
pub struct HintAction {
    /// The identifier that the agent receives.
    pub id: String,
    /// The label that the user reads.
    pub label: String,
    /// How to show the action, for example `primary`.
    pub style: String,
}

/// One hint.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, introspect::CustomType)]
pub struct Hint {
    /// The identifier that the daemon assigns.
    pub id: String,
    /// The producer name.
    pub source: String,
    /// The key of the hint inside the source.
    pub key: String,
    /// The kind of the hint, for example `reboot`.
    pub kind: String,
    /// The severity, from 0 to 3.
    pub severity: i64,
    /// The short title.
    pub title: String,
    /// The longer text.
    pub body: String,
    /// The Unix time when the producer created the hint.
    pub created_at: i64,
    /// The Unix time of the last change to the hint.
    pub updated_at: i64,
    /// The Unix time when the hint expires. Zero means no expiry.
    pub expires_at: i64,
    /// The actions that the user can select.
    pub actions: Vec<HintAction>,
}

/// A summary of the daemon state.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, introspect::CustomType)]
pub struct HintsStatus {
    /// The number of hints.
    pub hint_count: i64,
    /// The number of distinct producers.
    pub source_count: i64,
    /// The creation time of the oldest hint, or zero.
    pub oldest_created_at: i64,
    /// The version of the daemon.
    pub daemon_version: String,
}
