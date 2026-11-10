// SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
//
// SPDX-License-Identifier: MIT

//! The state that the two sockets share.

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard};

use tokio::sync::broadcast;

use crate::hints::{Hint, HintsStatus};
use crate::store::{HintSpec, HintStore, StoreError};

/// The number of snapshots that a reader can miss.
const CHANGE_CAPACITY: usize = 16;

/// The hints, the path of the store, and the version.
#[derive(Debug, Clone)]
pub struct HintState {
    store: Arc<Mutex<HintStore>>,
    changes: broadcast::Sender<Vec<Hint>>,
    path: PathBuf,
    version: String,
}

impl HintState {
    /// Create an empty state.
    #[must_use]
    pub fn new(path: PathBuf, version: impl Into<String>) -> Self {
        // A slow reader misses a change rather than blocking a producer.
        let (changes, _) = broadcast::channel(CHANGE_CAPACITY);

        Self {
            store: Arc::new(Mutex::new(HintStore::new())),
            changes,
            path,
            version: version.into(),
        }
    }

    /// Read the hints from the store on disk.
    ///
    /// A store that exists and is not valid gives an error. The daemon must not
    /// discard the hints without a message.
    ///
    /// # Errors
    ///
    /// Return the error of the store if the file is invalid.
    pub fn load(&self) -> Result<(), StoreError> {
        let loaded = HintStore::load(&self.path)?;
        if let Some(store) = loaded {
            *self.lock() = store;
        }
        Ok(())
    }

    /// Create a hint, or update the hint with the same `source` and `key`.
    ///
    /// Return the identifier of the hint.
    #[must_use]
    pub fn upsert(&self, spec: HintSpec, new_id: String, now: i64) -> String {
        self.apply(|store| (store.upsert(spec, new_id, now), true))
    }

    /// Remove one hint.
    pub fn clear(&self, source: &str, key: &str) {
        self.apply(|store| ((), store.clear(source, key)));
    }

    /// Remove each hint of one source.
    pub fn clear_source(&self, source: &str) {
        self.apply(|store| ((), store.clear_source(source) > 0));
    }

    /// Remove each hint that expired.
    pub fn sweep_expired(&self, now: i64) {
        self.apply(|store| ((), store.sweep_expired(now) > 0));
    }

    /// Return each hint with a severity of at least `min_severity`.
    #[must_use]
    pub fn list(&self, min_severity: i64) -> Vec<Hint> {
        self.lock()
            .snapshot()
            .into_iter()
            .filter(|hint| hint.severity >= min_severity)
            .collect()
    }

    /// Return one hint.
    #[must_use]
    pub fn get(&self, source: &str, key: &str) -> Option<Hint> {
        self.lock().get(source, key).cloned()
    }

    /// Return the summary of the state.
    #[must_use]
    pub fn status(&self) -> HintsStatus {
        let store = self.lock();
        HintsStatus {
            hint_count: i64::try_from(store.len()).unwrap_or(i64::MAX),
            source_count: i64::try_from(store.source_count()).unwrap_or(i64::MAX),
            oldest_created_at: store.oldest_created_at(),
            daemon_version: self.version.clone(),
        }
    }

    /// Return the path of the store.
    #[must_use]
    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Run `f` on the store. Then write and publish the result if `f` changed
    /// the store.
    ///
    /// The write holds the lock.
    fn apply<T>(&self, f: impl FnOnce(&mut HintStore) -> (T, bool)) -> T {
        let (value, json, snapshot) = {
            let mut store = self.lock();
            let (value, changed) = f(&mut store);
            let json = changed.then(|| store.to_json());
            let snapshot = changed.then(|| store.snapshot());
            (value, json, snapshot)
        };

        if let Some(json) = json {
            self.write(json);
        }
        if let Some(snapshot) = snapshot {
            // Nobody listens yet, or the readers are gone. That is fine.
            let _ = self.changes.send(snapshot);
        }
        value
    }

    /// Return the hints now, and the changes that follow.
    #[must_use]
    pub fn snapshot_and_subscribe(&self) -> (Vec<Hint>, broadcast::Receiver<Vec<Hint>>) {
        let store = self.lock();
        let hints = store.snapshot();
        let changes = self.changes.subscribe();
        drop(store);
        (hints, changes)
    }

    /// Write the store to disk. Log a failure.
    fn write(&self, json: Result<String, StoreError>) {
        let result = json.and_then(|json| crate::store::write_json(&self.path, &json));

        if let Err(error) = result {
            tracing::warn!(%error, path = %self.path.display(), "the store is not persisted");
        }
    }

    /// Take the lock on the store.
    fn lock(&self) -> MutexGuard<'_, HintStore> {
        self.store.lock().expect("the store lock is not poisoned")
    }
}

#[cfg(test)]
mod tests {
    use super::HintState;
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

    #[test]
    fn a_mutation_is_persisted() {
        let directory = tempfile::tempdir().expect("a temporary directory");
        let path = directory.path().join("hints.json");
        let state = HintState::new(path.clone(), "test");

        let _ = state.upsert(spec("reboot"), "id-1".to_owned(), 100);

        let reloaded = HintState::new(path, "test");
        reloaded.load().expect("the store loads");
        assert_eq!(reloaded.list(0).len(), 1);
    }

    #[test]
    fn a_sweep_is_persisted() {
        let directory = tempfile::tempdir().expect("a temporary directory");
        let path = directory.path().join("hints.json");
        let state = HintState::new(path.clone(), "test");

        let mut expiring = spec("old");
        expiring.expires_at = 50;
        let _ = state.upsert(expiring, "id-1".to_owned(), 0);

        state.sweep_expired(50);

        let reloaded = HintState::new(path, "test");
        reloaded.load().expect("the store loads");
        assert_eq!(reloaded.list(0).len(), 0);
    }
}
