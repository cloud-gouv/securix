// SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
//
// SPDX-License-Identifier: MIT

use std::collections::{BTreeMap, BTreeSet};

use crate::agent::state::Visibility;
use crate::cooldown;
use crate::hints::Hint;

pub type HintKey = (String, String);

#[must_use]
pub fn key_of(hint: &Hint) -> HintKey {
    (hint.source.clone(), hint.key.clone())
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct PresentationState {
    pub presented: BTreeSet<HintKey>,
    pub last_shown: BTreeMap<HintKey, i64>,
    pub critical_since: BTreeMap<HintKey, i64>,
    pub last_severity: BTreeMap<HintKey, i64>,
    pub last_bucket: BTreeMap<HintKey, u8>,
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct Plan {
    pub present: Vec<Hint>,
    pub close: Vec<HintKey>,
    pub state: PresentationState,
}

#[must_use]
pub const fn countdown_bucket(remaining: i64) -> u8 {
    if remaining <= 0 {
        4
    } else if remaining <= 10 * 60 {
        3
    } else if remaining <= 60 * 60 {
        2
    } else if remaining <= 4 * 60 * 60 {
        1
    } else {
        0
    }
}

#[must_use]
pub fn reconcile(
    hints: &[Hint],
    visibility: &Visibility,
    previous: &PresentationState,
    now: i64,
    config: &crate::agent::Config,
) -> Plan {
    let mut presented = previous.presented.clone();
    let mut last_shown = previous.last_shown.clone();
    let mut critical_since = previous.critical_since.clone();
    let mut last_severity = previous.last_severity.clone();
    let mut last_bucket = previous.last_bucket.clone();
    let mut present = Vec::new();

    let current: BTreeSet<HintKey> = hints.iter().map(key_of).collect();
    presented.retain(|key| current.contains(key));

    for hint in hints {
        let key = key_of(hint);
        let expired = hint.expires_at != 0 && hint.expires_at <= now;

        if config.starts_countdown(hint) {
            critical_since.entry(key.clone()).or_insert(now);
        } else {
            critical_since.remove(&key);
        }

        if expired || visibility.is_hidden(hint, now) {
            presented.remove(&key);
            continue;
        }

        let is_open = !presented.insert(key.clone());
        let escalated = last_severity
            .get(&key)
            .is_some_and(|before| hint.severity > *before);
        let bucket = critical_since
            .get(&key)
            .map(|since| countdown_bucket(config.deadline(*since) - now));

        let repeats = bucket.map_or_else(
            || escalated || cooldown::is_due(last_shown.get(&key).copied(), now, hint.severity),
            |bucket| last_bucket.get(&key).is_some_and(|before| bucket > *before),
        );

        if is_open && !repeats {
            continue;
        }

        last_shown.insert(key.clone(), now);
        last_severity.insert(key.clone(), hint.severity);
        if let Some(bucket) = bucket {
            last_bucket.insert(key, bucket);
        }
        present.push(hint.clone());
    }

    let close: Vec<HintKey> = previous.presented.difference(&presented).cloned().collect();
    last_shown.retain(|key, _| presented.contains(key));
    last_severity.retain(|key, _| presented.contains(key));
    last_bucket.retain(|key, _| presented.contains(key));
    critical_since.retain(|key, _| current.contains(key));

    Plan {
        present,
        close,
        state: PresentationState {
            presented,
            last_shown,
            critical_since,
            last_severity,
            last_bucket,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::{key_of, reconcile, PresentationState};
    use crate::agent::state::Visibility;
    use crate::cooldown::ADVISORY_SECONDS;
    use crate::hints::Hint;

    fn hint(key: &str, severity: i64, updated_at: i64) -> Hint {
        Hint {
            id: format!("id-{key}"),
            source: "updates".to_owned(),
            key: key.to_owned(),
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

    fn tick(hints: &[Hint], previous: &PresentationState, now: i64) -> super::Plan {
        reconcile(hints, &Visibility::new(), previous, now, &config())
    }

    fn config() -> crate::agent::Config {
        crate::agent::Config::new()
    }

    #[test]
    fn a_hint_is_shown_once_per_cooldown() {
        let hints = vec![hint("reboot", 1, 0)];

        let first = tick(&hints, &PresentationState::default(), 0);
        assert_eq!(first.present.len(), 1);

        let early = tick(&hints, &first.state, ADVISORY_SECONDS - 1);
        assert_eq!(early.present.len(), 0, "the cooldown holds");

        let late = tick(&hints, &first.state, ADVISORY_SECONDS);
        assert_eq!(late.present.len(), 1, "the hint is shown again");
    }

    #[test]
    fn a_more_severe_hint_is_shown_at_once() {
        let hints = vec![hint("reboot", 1, 0)];
        let first = tick(&hints, &PresentationState::default(), 0);
        assert_eq!(first.present.len(), 1);

        let severe = vec![hint("reboot", 2, 0)];
        let second = tick(&severe, &first.state, 10);
        assert_eq!(second.present.len(), 1, "the escalation is shown");
    }

    #[test]
    fn the_countdown_is_shown_again_when_it_shrinks() {
        let hints = vec![kernel_hint(3, 0)];
        let first = tick(&hints, &PresentationState::default(), 1_000);
        assert_eq!(first.present.len(), 1);

        let soon = tick(&hints, &first.state, 1_000 + 60);
        assert_eq!(soon.present.len(), 0);

        let later = tick(&hints, &first.state, 1_000 + 5 * 3_600);
        assert_eq!(later.present.len(), 1);
    }

    #[test]
    fn a_removed_hint_is_closed() {
        let hints = vec![hint("reboot", 2, 0)];
        let first = tick(&hints, &PresentationState::default(), 0);

        let second = tick(&[], &first.state, 10);
        assert_eq!(second.present.len(), 0);
        assert_eq!(second.close, vec![key_of(&hints[0])]);
    }

    #[test]
    fn a_snoozed_hint_is_hidden_and_closed() {
        let hints = vec![hint("reboot", 2, 0)];
        let first = tick(&hints, &PresentationState::default(), 0);

        let visibility = Visibility::new();
        visibility
            .snooze(&hints[0], 3_600, 0)
            .expect("the hint snoozes");
        let second = reconcile(&hints, &visibility, &first.state, 10, &config());

        assert_eq!(second.present.len(), 0);
        assert_eq!(second.close, vec![key_of(&hints[0])]);
    }

    fn kernel_hint(severity: i64, updated_at: i64) -> Hint {
        Hint {
            source: config().critical_source,
            ..hint("reboot", severity, updated_at)
        }
    }

    #[test]
    fn an_untrusted_source_never_counts_down() {
        let hints = vec![hint("reboot", 3, 0)];
        let plan = tick(&hints, &PresentationState::default(), 1_000);
        assert!(plan.state.critical_since.is_empty());
    }

    #[test]
    fn the_countdown_starts_when_the_hint_becomes_critical() {
        let hints = vec![kernel_hint(3, 0)];
        let first = tick(&hints, &PresentationState::default(), 1_000);
        let since = key_of(&hints[0]);

        assert_eq!(first.state.critical_since.get(&since), Some(&1_000));

        let updated = vec![kernel_hint(3, 2_000)];
        let second = tick(&updated, &first.state, 5_000);
        assert_eq!(second.state.critical_since.get(&since), Some(&1_000));
    }

    #[test]
    fn a_demoted_hint_forgets_its_countdown() {
        let critical = vec![kernel_hint(3, 0)];
        let first = tick(&critical, &PresentationState::default(), 1_000);

        let important = vec![hint("reboot", 2, 0)];
        let second = tick(&important, &first.state, 2_000);
        assert!(second.state.critical_since.is_empty());
    }

    #[test]
    fn an_expired_hint_is_closed() {
        let mut expiring = hint("reboot", 2, 0);
        expiring.expires_at = 50;
        let hints = vec![expiring];
        let first = tick(&hints, &PresentationState::default(), 0);

        let second = tick(&hints, &first.state, 50);
        assert_eq!(second.present.len(), 0);
        assert_eq!(second.close.len(), 1);
    }
}
