// SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
//
// SPDX-License-Identifier: MIT

use std::collections::BTreeMap;
use std::sync::{Arc, RwLock, RwLockReadGuard, RwLockWriteGuard};

use crate::agent::reconcile::HintKey;
use crate::hints::Hint;

#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum SnoozeError {
    #[error("a critical hint cannot be snoozed")]
    Critical,
}

#[derive(Debug, Clone, Default)]
pub struct Visibility {
    inner: Arc<RwLock<Inner>>,
}

#[derive(Debug, Default)]
struct Inner {
    snoozes: BTreeMap<HintKey, i64>,
    dismissals: BTreeMap<HintKey, i64>,
}

impl Visibility {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    #[must_use]
    pub fn is_hidden(&self, hint: &Hint, now: i64) -> bool {
        let key = crate::agent::reconcile::key_of(hint);
        let inner = self.read();

        if inner.snoozes.get(&key).is_some_and(|until| *until > now) {
            return true;
        }
        inner
            .dismissals
            .get(&key)
            .is_some_and(|dismissed_at| *dismissed_at >= hint.updated_at)
    }

    /// # Errors
    ///
    /// Return [`SnoozeError::Critical`] if the hint is critical.
    pub fn snooze(&self, hint: &Hint, duration_seconds: i64, now: i64) -> Result<(), SnoozeError> {
        if hint.severity >= crate::severity::CRITICAL {
            return Err(SnoozeError::Critical);
        }

        self.write().snoozes.insert(
            crate::agent::reconcile::key_of(hint),
            now + duration_seconds,
        );
        Ok(())
    }

    pub fn dismiss(&self, hint: &Hint) {
        self.write()
            .dismissals
            .insert(crate::agent::reconcile::key_of(hint), hint.updated_at);
    }

    pub fn prune(&self, present: &std::collections::BTreeSet<HintKey>) {
        let mut inner = self.write();
        inner.snoozes.retain(|key, _| present.contains(key));
        inner.dismissals.retain(|key, _| present.contains(key));
    }

    fn read(&self) -> RwLockReadGuard<'_, Inner> {
        self.inner.read().expect("the visibility lock is fine")
    }

    fn write(&self) -> RwLockWriteGuard<'_, Inner> {
        self.inner.write().expect("the visibility lock is fine")
    }
}

#[cfg(test)]
mod tests {
    use super::{SnoozeError, Visibility};
    use crate::hints::Hint;

    fn hint(severity: i64, updated_at: i64) -> Hint {
        Hint {
            id: "id".to_owned(),
            source: "updates".to_owned(),
            key: "reboot".to_owned(),
            kind: "reboot".to_owned(),
            severity,
            title: "title".to_owned(),
            body: "body".to_owned(),
            created_at: 0,
            updated_at,
            expires_at: 0,
            actions: vec![],
        }
    }

    #[test]
    fn a_snooze_hides_the_hint_until_it_ends() {
        let visibility = Visibility::new();
        let hint = hint(2, 0);

        visibility.snooze(&hint, 60, 100).expect("the hint snoozes");

        assert!(visibility.is_hidden(&hint, 100));
        assert!(visibility.is_hidden(&hint, 159));
        assert!(!visibility.is_hidden(&hint, 160), "the snooze ended");
    }

    #[test]
    fn a_critical_hint_is_immune_to_a_snooze() {
        let visibility = Visibility::new();
        let hint = hint(3, 0);

        assert_eq!(
            visibility.snooze(&hint, 60, 100),
            Err(SnoozeError::Critical)
        );
        assert!(!visibility.is_hidden(&hint, 100));
    }

    #[test]
    fn a_dismissal_lasts_until_the_producer_changes_the_hint() {
        let visibility = Visibility::new();
        let original = hint(2, 10);

        visibility.dismiss(&original);
        assert!(visibility.is_hidden(&original, 100));

        let updated = hint(2, 20);
        assert!(
            !visibility.is_hidden(&updated, 100),
            "an update clears the dismissal"
        );
    }
}
