// SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
//
// SPDX-License-Identifier: MIT

//! The service that reads the hints.

// The `zlink` service macro needs `async fn` methods. `unknown_lints` lets an
// older Clippy build the code.
#![allow(unknown_lints, clippy::unused_async, clippy::unused_async_trait_impl)]

use crate::daemon::state::HintState;
use std::pin::Pin;

use futures_util::{Stream, StreamExt};

use crate::hints::{GetHint, GetStatus, HintsError, ListHints};

/// The read-only service.
#[derive(Debug, Clone)]
pub struct HintConsumer {
    state: HintState,
}

impl HintConsumer {
    /// Create the read-only service.
    #[must_use]
    pub const fn new(state: HintState) -> Self {
        Self { state }
    }
}

#[zlink::service(
    interface = "fr.gouv.securix.Hints",
    types = [
        crate::hints::Hint,
        crate::hints::HintAction,
        crate::hints::HintsStatus,
    ],
    product = "Sécurix hints",
    version = env!("CARGO_PKG_VERSION"),
)]
impl HintConsumer {
    /// Return each hint with a severity of at least `min_severity`.
    async fn list_hints(&self, min_severity: i64) -> ListHints {
        ListHints {
            hints: self.state.list(min_severity),
        }
    }

    /// Return one hint.
    async fn get_hint(&self, source: &str, key: &str) -> Result<GetHint, HintsError> {
        self.state.get(source, key).map_or_else(
            || {
                Err(HintsError::HintNotFound {
                    source: source.to_owned(),
                    key: key.to_owned(),
                })
            },
            |hint| Ok(GetHint { hint }),
        )
    }

    /// Return a summary of the daemon state.
    async fn get_status(&self) -> GetStatus {
        GetStatus {
            status: self.state.status(),
        }
    }

    /// Return the hints now, then one reply for each change.
    ///
    /// Each reply holds the full list. Thus, a reader that misses a change
    /// receives the next change.
    #[zlink(more)]
    async fn watch(&self, more: bool) -> impl Stream<Item = zlink::Reply<ListHints>> + Unpin {
        // The snapshot and the subscription use the same locked read. Thus,
        // the reader sees each change one time, in order.
        let (hints, changes) = if more {
            let (hints, changes) = self.state.snapshot_and_subscribe();
            (hints, Some(changes))
        } else {
            (self.state.list(0), None)
        };
        let snapshot = ListHints { hints };

        let stream: Pin<Box<dyn Stream<Item = zlink::Reply<ListHints>> + Send>> =
            if let Some(changes) = changes {
                let first = futures_util::stream::once(async move {
                    zlink::Reply::new(Some(snapshot)).set_continues(Some(true))
                });
                let changes = tokio_stream::wrappers::BroadcastStream::new(changes).filter_map(
                    |change| async move {
                        change.ok().map(|hints| {
                            zlink::Reply::new(Some(ListHints { hints })).set_continues(Some(true))
                        })
                    },
                );
                Box::pin(first.chain(changes))
            } else {
                Box::pin(futures_util::stream::once(async move {
                    zlink::Reply::new(Some(snapshot)).set_continues(Some(false))
                }))
            };

        stream
    }
}

#[cfg(all(test, unix))]
mod tests {
    use zlink::tokio::unix::{bind, connect};
    use zlink::Server;

    use super::HintConsumer;
    use crate::daemon::state::HintState;
    use crate::hints::Hints as _;
    use crate::store::HintSpec;

    fn spec(key: &str) -> HintSpec {
        HintSpec {
            source: "updates".to_owned(),
            key: key.to_owned(),
            kind: "reboot".to_owned(),
            severity: 2,
            title: "title".to_owned(),
            body: "body".to_owned(),
            expires_at: 0,
            actions: vec![],
        }
    }

    #[tokio::test]
    async fn list_get_and_status() {
        let directory = tempfile::tempdir().expect("a temporary directory");
        let path = directory.path().join("consumer.sock");
        let state = HintState::new(directory.path().join("hints.json"), "test");
        let _ = state.upsert(spec("reboot"), "id-1".to_owned(), 100);

        let listener = bind(&path).expect("the consumer socket");
        let server = Server::new(listener, HintConsumer::new(state.clone()));

        let client = async {
            let mut connection = connect(&path).await.expect("the connection");

            let listed = connection
                .list_hints(0)
                .await
                .expect("the call")
                .expect("the reply");
            assert_eq!(listed.hints.len(), 1);

            let filtered = connection
                .list_hints(3)
                .await
                .expect("the call")
                .expect("the reply");
            assert!(filtered.hints.is_empty(), "the hint is not critical");

            let fetched = connection
                .get_hint("updates", "reboot")
                .await
                .expect("the call")
                .expect("the reply");
            assert_eq!(fetched.hint.id, "id-1");

            let status = connection
                .get_status()
                .await
                .expect("the call")
                .expect("the reply");
            assert_eq!(status.status.hint_count, 1);
        };

        tokio::select! {
            result = server.run() => result.expect("the server runs"),
            () = client => {}
        }
    }

    #[tokio::test]
    async fn watch_delivers_each_change() {
        use futures_util::StreamExt;

        let directory = tempfile::tempdir().expect("a temporary directory");
        let path = directory.path().join("consumer.sock");
        let state = HintState::new(directory.path().join("hints.json"), "test");

        let listener = bind(&path).expect("the consumer socket");
        let server = Server::new(listener, HintConsumer::new(state.clone()));

        let client = async {
            let mut connection = connect(&path).await.expect("the connection");
            let mut stream = connection.watch().await.expect("the call");

            let first = stream
                .next()
                .await
                .expect("a reply")
                .expect("ok")
                .expect("no error");
            assert_eq!(first.hints.len(), 0);

            let _ = state.upsert(spec("reboot"), "id-1".to_owned(), 100);

            let second = stream
                .next()
                .await
                .expect("a reply")
                .expect("ok")
                .expect("no error");
            assert_eq!(second.hints.len(), 1, "the change arrives");
        };

        tokio::select! {
            result = server.run() => result.expect("the server runs"),
            () = client => {}
        }
    }

    #[tokio::test]
    async fn a_missing_hint_is_an_error() {
        let directory = tempfile::tempdir().expect("a temporary directory");
        let path = directory.path().join("consumer.sock");
        let state = HintState::new(directory.path().join("hints.json"), "test");

        let listener = bind(&path).expect("the consumer socket");
        let server = Server::new(listener, HintConsumer::new(state));

        let client = async {
            let mut connection = connect(&path).await.expect("the connection");
            let error = connection
                .get_hint("updates", "absent")
                .await
                .expect("the call")
                .expect_err("the hint does not exist");
            assert!(matches!(
                error,
                crate::hints::HintsError::HintNotFound { .. }
            ));
        };

        tokio::select! {
            result = server.run() => result.expect("the server runs"),
            () = client => {}
        }
    }
}
