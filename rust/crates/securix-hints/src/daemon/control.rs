// SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
//
// SPDX-License-Identifier: MIT

//! The service that writes the hints.

// The `zlink` service macro needs `async fn` methods. `UpsertHint` has the
// parameters that the interface declares. `unknown_lints` lets an older Clippy
// build the code.
#![allow(
    unknown_lints,
    clippy::unused_async,
    clippy::unused_async_trait_impl,
    clippy::too_many_arguments
)]

use crate::daemon::state::HintState;
use crate::hints_control::{HintAction, HintsControlError, UpsertHint};
use crate::severity;

/// The producer service.
#[derive(Debug, Clone)]
pub struct HintControl {
    state: HintState,
}

impl HintControl {
    /// Create the producer service.
    #[must_use]
    pub const fn new(state: HintState) -> Self {
        Self { state }
    }
}

#[zlink::service(
    interface = "fr.gouv.securix.HintsControl",
    types = [HintAction],
    product = "Sécurix hints",
    version = env!("CARGO_PKG_VERSION"),
)]
impl HintControl {
    /// Create a hint, or update the hint with the same `source` and `key`.
    async fn upsert_hint(
        &self,
        source: &str,
        key: &str,
        kind: &str,
        severity: i64,
        title: &str,
        body: &str,
        expires_at: i64,
        actions: Vec<HintAction>,
    ) -> Result<UpsertHint, HintsControlError> {
        if !severity::is_valid(severity) {
            return Err(HintsControlError::InvalidHint {
                message: format!("the severity {severity} is outside the scale"),
            });
        }

        let spec = crate::store::HintSpec {
            source: source.to_owned(),
            key: key.to_owned(),
            kind: kind.to_owned(),
            severity,
            title: title.to_owned(),
            body: body.to_owned(),
            expires_at,
            actions,
        };
        let id = self
            .state
            .upsert(spec, crate::clock::new_id(), crate::clock::now());
        Ok(UpsertHint { id })
    }

    /// Remove one hint.
    async fn clear_hint(&self, source: &str, key: &str) {
        self.state.clear(source, key);
    }

    /// Remove each hint of one source.
    async fn clear_source(&self, source: &str) {
        self.state.clear_source(source);
    }
}

#[cfg(all(test, unix))]
mod tests {
    use zlink::tokio::unix::{bind, connect};
    use zlink::Server;

    use super::HintControl;
    use crate::daemon::state::HintState;
    use crate::hints_control::{HintsControl as _, HintsControlError};

    fn state(directory: &tempfile::TempDir) -> HintState {
        HintState::new(directory.path().join("hints.json"), "test")
    }

    #[tokio::test]
    async fn upsert_and_clear() {
        let directory = tempfile::tempdir().expect("a temporary directory");
        let path = directory.path().join("control.sock");
        let state = state(&directory);

        let listener = bind(&path).expect("the control socket");
        let server = Server::new(listener, HintControl::new(state.clone()));

        let client = async {
            let mut connection = connect(&path).await.expect("the connection");

            {
                let result = connection
                    .upsert_hint("updates", "reboot", "reboot", 2, "title", "body", 0, &[])
                    .await
                    .expect("the call")
                    .expect("the reply");
                assert!(!result.id.is_empty(), "the daemon assigns an identifier");
            }
            assert_eq!(state.list(0).len(), 1);

            connection
                .clear_hint("updates", "reboot")
                .await
                .expect("the call")
                .expect("the reply");
            assert_eq!(state.list(0).len(), 0);
        };

        tokio::select! {
            result = server.run() => result.expect("the server runs"),
            () = client => {}
        }
    }

    #[tokio::test]
    async fn an_invalid_severity_is_refused() {
        let directory = tempfile::tempdir().expect("a temporary directory");
        let path = directory.path().join("control.sock");
        let state = state(&directory);

        let listener = bind(&path).expect("the control socket");
        let server = Server::new(listener, HintControl::new(state.clone()));

        let client = async {
            let mut connection = connect(&path).await.expect("the connection");

            let error = connection
                .upsert_hint("updates", "reboot", "reboot", 9, "t", "b", 0, &[])
                .await
                .expect("the call")
                .expect_err("the daemon refuses the hint");
            assert!(matches!(error, HintsControlError::InvalidHint { .. }));
            assert_eq!(state.list(0).len(), 0);
        };

        tokio::select! {
            result = server.run() => result.expect("the server runs"),
            () = client => {}
        }
    }
}
