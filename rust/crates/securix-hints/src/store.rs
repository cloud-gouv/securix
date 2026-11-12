// SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
//
// SPDX-License-Identifier: MIT

//! The hint store and its persistence on disk.

use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};

use crate::hints::{Hint, HintAction};

/// The fields that a producer sends.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HintSpec {
    /// The name of the producer, for example `securix-auto-updates`.
    pub source: String,
    /// The stable key of the hint inside its source.
    pub key: String,
    /// The kind of the hint, for example `reboot`.
    pub kind: String,
    /// The severity of the hint, a value of [`crate::severity`].
    pub severity: i64,
    /// The short title.
    pub title: String,
    /// The longer text.
    pub body: String,
    /// The Unix time when the hint expires. Zero means no expiry.
    pub expires_at: i64,
    /// The actions that the user can select.
    pub actions: Vec<HintAction>,
}

/// The hints, keyed by `(source, key)`.
#[derive(Debug, Default)]
pub struct HintStore {
    hints: BTreeMap<(String, String), Hint>,
}

impl HintStore {
    /// Create an empty store.
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Create a hint, or update the hint with the same source and key.
    ///
    /// On update, the store keeps the identifier and the creation time. It
    /// sets the update time to `now`. It uses `new_id` only for a new hint.
    /// The function returns the identifier in use.
    pub fn upsert(&mut self, spec: HintSpec, new_id: String, now: i64) -> String {
        let key = (spec.source.clone(), spec.key.clone());

        if let Some(existing) = self.hints.get_mut(&key) {
            existing.kind = spec.kind;
            existing.severity = spec.severity;
            existing.title = spec.title;
            existing.body = spec.body;
            existing.expires_at = spec.expires_at;
            existing.actions = spec.actions;
            existing.updated_at = now;
            return existing.id.clone();
        }

        self.hints.insert(
            key,
            Hint {
                id: new_id.clone(),
                source: spec.source,
                key: spec.key,
                kind: spec.kind,
                severity: spec.severity,
                title: spec.title,
                body: spec.body,
                created_at: now,
                updated_at: now,
                expires_at: spec.expires_at,
                actions: spec.actions,
            },
        );
        new_id
    }

    /// Remove one hint. Return true if the store held it.
    pub fn clear(&mut self, source: &str, key: &str) -> bool {
        self.hints
            .remove(&(source.to_owned(), key.to_owned()))
            .is_some()
    }

    /// Remove each hint of one source. Return the number of removed hints.
    pub fn clear_source(&mut self, source: &str) -> usize {
        let before = self.hints.len();
        self.hints
            .retain(|(hint_source, _), _| hint_source != source);
        before - self.hints.len()
    }

    /// Remove each hint that expired at or before `now`.
    ///
    /// A hint with `expires_at == 0` never expires.
    pub fn sweep_expired(&mut self, now: i64) -> usize {
        let before = self.hints.len();
        self.hints
            .retain(|_, hint| hint.expires_at == 0 || hint.expires_at > now);
        before - self.hints.len()
    }

    /// Return one hint.
    #[must_use]
    pub fn get(&self, source: &str, key: &str) -> Option<&Hint> {
        self.hints.get(&(source.to_owned(), key.to_owned()))
    }

    /// Return every hint, ordered by source and key.
    #[must_use]
    pub fn snapshot(&self) -> Vec<Hint> {
        self.hints.values().cloned().collect()
    }

    /// Return the number of hints.
    #[must_use]
    pub fn len(&self) -> usize {
        self.hints.len()
    }

    /// Return true if the store holds no hint.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.hints.is_empty()
    }

    /// Return the number of distinct sources.
    #[must_use]
    pub fn source_count(&self) -> usize {
        self.hints
            .keys()
            .map(|(source, _)| source.as_str())
            .collect::<BTreeSet<_>>()
            .len()
    }

    /// Return the creation time of the oldest hint, or zero.
    #[must_use]
    pub fn oldest_created_at(&self) -> i64 {
        self.hints
            .values()
            .map(|hint| hint.created_at)
            .min()
            .unwrap_or(0)
    }

    /// Serialize the store to JSON.
    ///
    /// # Errors
    ///
    /// Return [`StoreError::Json`] if the serialization fails.
    pub fn to_json(&self) -> Result<String, StoreError> {
        Ok(serde_json::to_string_pretty(&self.snapshot())?)
    }

    /// Make a store from JSON that [`HintStore::to_json`] made.
    ///
    /// # Errors
    ///
    /// Return [`StoreError::Json`] if the input is not a hint list.
    pub fn from_json(json: &str) -> Result<Self, StoreError> {
        let hints: Vec<Hint> = serde_json::from_str(json)?;
        let mut store = Self::new();
        for hint in hints {
            store
                .hints
                .insert((hint.source.clone(), hint.key.clone()), hint);
        }
        Ok(store)
    }

    /// Write the store to `path` without a partial file.
    ///
    /// The function writes a temporary file. It flushes the file to disk. It
    /// renames the file over `path`. A reader sees the old store or the new
    /// store, and never a part of a store.
    ///
    /// # Errors
    ///
    /// Return [`StoreError::Io`] if a filesystem operation fails, or
    /// [`StoreError::Json`] if the serialization fails.
    pub fn persist(&self, path: &Path) -> Result<(), StoreError> {
        write_json(path, &self.to_json()?)
    }

    /// Read a store from `path`.
    ///
    /// Return `Ok(None)` if the file does not exist yet.
    ///
    /// # Errors
    ///
    /// Return [`StoreError::Io`] if the file is unreadable, or
    /// [`StoreError::Json`] if its content is not a valid store.
    pub fn load(path: &Path) -> Result<Option<Self>, StoreError> {
        match fs::read_to_string(path) {
            Ok(json) => Ok(Some(Self::from_json(&json)?)),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
            Err(error) => Err(StoreError::Io(error)),
        }
    }
}

/// Write `json` to `path` without a partial file.
///
/// It uses a technique to ensure atomicity based on temp files, a reader either sees the old
/// content or the new one.
///
/// # Errors
///
/// Return [`StoreError::Io`] if a filesystem operation fails.
pub fn write_json(path: &Path, json: &str) -> Result<(), StoreError> {
    let directory = path.parent().unwrap_or_else(|| Path::new("."));
    fs::create_dir_all(directory)?;

    let temporary = temporary_path(path);
    {
        let mut file = fs::File::create(&temporary)?;
        file.write_all(json.as_bytes())?;
        file.sync_all()?;
    }
    fs::rename(&temporary, path)?;
    fs::File::open(directory)?.sync_all()?;
    Ok(())
}

/// Return the path of the temporary file that [`write_json`] uses.
fn temporary_path(path: &Path) -> PathBuf {
    let mut name = path.as_os_str().to_owned();
    name.push(".tmp");
    PathBuf::from(name)
}

/// An error from the hint store.
#[derive(Debug, thiserror::Error)]
pub enum StoreError {
    /// The JSON form of the store is not valid.
    #[error("the hint store is not valid JSON")]
    Json(#[from] serde_json::Error),
    /// A filesystem operation failed.
    #[error("the hint store is not accessible")]
    Io(#[from] io::Error),
}

#[cfg(test)]
mod tests {
    use super::{HintSpec, HintStore};
    use crate::hints::HintAction;

    fn spec(source: &str, key: &str) -> HintSpec {
        HintSpec {
            source: source.to_owned(),
            key: key.to_owned(),
            kind: "reboot".to_owned(),
            severity: 2,
            title: "Reboot required".to_owned(),
            body: "A new generation is staged.".to_owned(),
            expires_at: 0,
            actions: vec![HintAction {
                id: "reboot".to_owned(),
                label: "Reboot now".to_owned(),
                style: "primary".to_owned(),
            }],
        }
    }

    #[test]
    fn upsert_inserts_a_new_hint() {
        let mut store = HintStore::new();
        let id = store.upsert(spec("updates", "reboot"), "id-1".to_owned(), 100);

        assert_eq!(id, "id-1");
        assert_eq!(store.len(), 1);
        let hint = store.get("updates", "reboot").expect("the hint exists");
        assert_eq!(hint.created_at, 100);
        assert_eq!(hint.updated_at, 100);
    }

    #[test]
    fn upsert_updates_in_place() {
        let mut store = HintStore::new();
        store.upsert(spec("updates", "reboot"), "id-1".to_owned(), 100);

        let mut updated = spec("updates", "reboot");
        updated.body = "A newer generation is staged.".to_owned();
        updated.severity = 3;
        let id = store.upsert(updated, "id-2".to_owned(), 200);

        assert_eq!(id, "id-1", "the store keeps the identifier");
        assert_eq!(store.len(), 1, "the store keeps one hint");
        let hint = store.get("updates", "reboot").expect("the hint exists");
        assert_eq!(hint.created_at, 100, "the store keeps the creation time");
        assert_eq!(hint.updated_at, 200, "the store bumps the update time");
        assert_eq!(hint.severity, 3);
    }

    #[test]
    fn clear_removes_one_hint() {
        let mut store = HintStore::new();
        store.upsert(spec("updates", "reboot"), "id-1".to_owned(), 100);

        assert!(store.clear("updates", "reboot"));
        assert!(store.is_empty());
        assert!(!store.clear("updates", "reboot"), "the hint is gone");
    }

    #[test]
    fn clear_source_removes_each_hint_of_the_source() {
        let mut store = HintStore::new();
        store.upsert(spec("updates", "reboot"), "id-1".to_owned(), 100);
        store.upsert(spec("updates", "firmware"), "id-2".to_owned(), 100);
        store.upsert(spec("security", "reboot"), "id-3".to_owned(), 100);

        assert_eq!(store.clear_source("updates"), 2);
        assert_eq!(store.len(), 1);
        assert!(store.get("security", "reboot").is_some());
    }

    #[test]
    fn sweep_expired_removes_only_expired_hints() {
        let mut store = HintStore::new();
        store.upsert(spec("updates", "reboot"), "id-1".to_owned(), 100);

        let mut expiring = spec("security", "key");
        expiring.expires_at = 150;
        store.upsert(expiring, "id-2".to_owned(), 100);

        assert_eq!(store.sweep_expired(149), 0, "the hint is not expired yet");
        assert_eq!(store.sweep_expired(150), 1, "the hint expires at 150");
        assert_eq!(store.len(), 1, "the hint with no expiry stays");
    }

    #[test]
    fn snapshot_is_ordered_by_source_and_key() {
        let mut store = HintStore::new();
        store.upsert(spec("updates", "reboot"), "id-1".to_owned(), 100);
        store.upsert(spec("security", "reboot"), "id-2".to_owned(), 100);
        store.upsert(spec("updates", "firmware"), "id-3".to_owned(), 100);

        let keys: Vec<(String, String)> = store
            .snapshot()
            .into_iter()
            .map(|hint| (hint.source, hint.key))
            .collect();
        assert_eq!(
            keys,
            vec![
                ("security".to_owned(), "reboot".to_owned()),
                ("updates".to_owned(), "firmware".to_owned()),
                ("updates".to_owned(), "reboot".to_owned()),
            ]
        );
    }

    #[test]
    fn the_status_counts_distinct_sources_and_the_oldest_hint() {
        let mut store = HintStore::new();
        store.upsert(spec("updates", "reboot"), "id-1".to_owned(), 300);
        store.upsert(spec("updates", "firmware"), "id-2".to_owned(), 100);
        store.upsert(spec("security", "reboot"), "id-3".to_owned(), 200);

        assert_eq!(store.source_count(), 2);
        assert_eq!(store.oldest_created_at(), 100);
    }

    #[test]
    fn from_json_rejects_invalid_input() {
        assert!(HintStore::from_json("not json").is_err());
        assert!(HintStore::from_json(r#"{"not": "a list"}"#).is_err());
    }

    #[test]
    fn persist_and_load_round_trip() {
        let directory = tempfile::tempdir().expect("a temporary directory");
        let path = directory.path().join("hints.json");

        let mut store = HintStore::new();
        store.upsert(spec("updates", "reboot"), "id-1".to_owned(), 100);
        store.persist(&path).expect("the store persists");

        let loaded = HintStore::load(&path)
            .expect("the store loads")
            .expect("the store exists");
        assert_eq!(loaded.len(), 1);

        let missing = HintStore::load(&directory.path().join("absent.json"))
            .expect("an absent store is not an error");
        assert!(missing.is_none());
    }
}
