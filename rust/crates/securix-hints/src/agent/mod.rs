// SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
//
// SPDX-License-Identifier: MIT

pub mod duration;
pub mod presenter;
pub mod reconcile;
pub mod state;

use presenter::Presenter;
use reconcile::Plan;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    pub critical_source: String,

    pub auto_reboot_after_seconds: i64,

    pub auto_reboot: bool,
}

impl Config {
    #[must_use]
    pub fn new() -> Self {
        Self {
            critical_source: "securix-kernel".to_owned(),
            auto_reboot_after_seconds: 8 * 60 * 60,
            auto_reboot: true,
        }
    }

    #[must_use]
    pub fn from_env() -> Self {
        let mut config = Self::new();
        if let Ok(source) = std::env::var("SECURIX_HINTS_CRITICAL_SOURCE") {
            config.critical_source = source;
        }
        if let Ok(seconds) = std::env::var("SECURIX_HINTS_AUTO_REBOOT_AFTER_SECONDS") {
            if let Ok(seconds) = seconds.parse() {
                config.auto_reboot_after_seconds = seconds;
            }
        }
        config.auto_reboot = std::env::var("SECURIX_HINTS_AUTO_REBOOT").as_deref() != Ok("0");
        config
    }

    #[must_use]
    pub fn starts_countdown(&self, hint: &crate::hints::Hint) -> bool {
        hint.severity >= crate::severity::CRITICAL
            && hint.kind == "reboot"
            && hint.source == self.critical_source
    }

    #[must_use]
    pub const fn deadline(&self, since: i64) -> i64 {
        since + self.auto_reboot_after_seconds
    }

    #[must_use]
    pub const fn is_due(&self, since: i64, now: i64) -> bool {
        now >= self.deadline(since)
    }

    #[must_use]
    pub fn countdown(&self, hint: &crate::hints::Hint, since: i64, now: i64) -> Option<String> {
        if !self.starts_countdown(hint) {
            return None;
        }

        Some(format!(
            "Reboot in {}.",
            duration::remaining(self.deadline(since) - now)
        ))
    }
}

impl Default for Config {
    fn default() -> Self {
        Self::new()
    }
}

pub fn apply(plan: &Plan, presenter: &dyn Presenter, now: i64, config: &Config) {
    for hint in &plan.present {
        let mut shown = hint.clone();
        if let Some(since) = plan.state.critical_since.get(&reconcile::key_of(hint)) {
            if let Some(text) = config.countdown(hint, *since, now) {
                shown.body = format!("{}\n\n{text}", hint.body);
            }
        }

        tracing::info!(source = %hint.source, key = %hint.key, "the agent shows a hint");
        if let Err(error) = presenter.present(&shown) {
            tracing::warn!(%error, source = %hint.source, key = %hint.key, "the hint is not shown");
        }
    }

    for key in &plan.close {
        presenter.close(key);
    }
}

#[cfg(test)]
mod tests {
    use super::{apply, Config};
    use crate::agent::presenter::{Presenter, PresenterError};
    use crate::agent::reconcile::{key_of, PresentationState};
    use crate::hints::{Hint, HintAction};

    fn config() -> Config {
        Config::new()
    }

    fn hint(severity: i64) -> Hint {
        Hint {
            id: "id".to_owned(),
            source: "securix-kernel".to_owned(),
            key: "reboot".to_owned(),
            kind: "reboot".to_owned(),
            severity,
            title: "Title".to_owned(),
            body: "Body".to_owned(),
            created_at: 0,
            updated_at: 0,
            expires_at: 0,
            actions: vec![HintAction {
                id: "reboot".to_owned(),
                label: "Reboot".to_owned(),
                style: "primary".to_owned(),
            }],
        }
    }

    #[test]
    fn a_critical_hint_reboots_after_the_delay() {
        let config = config();
        let delay = config.auto_reboot_after_seconds;

        assert_eq!(config.deadline(1_000), 1_000 + delay);
        assert!(!config.is_due(1_000, 1_000 + delay - 1));
        assert!(config.is_due(1_000, 1_000 + delay));
    }

    #[test]
    fn only_the_trusted_source_starts_a_countdown() {
        let config = config();

        assert!(config.starts_countdown(&hint(3)));

        let other = Hint {
            source: "somebody".to_owned(),
            ..hint(3)
        };
        assert!(!config.starts_countdown(&other));

        assert!(!config.starts_countdown(&hint(2)));
    }

    #[test]
    fn the_delay_comes_from_the_configuration() {
        let config = Config {
            auto_reboot_after_seconds: 60,
            ..Config::new()
        };
        assert_eq!(config.deadline(0), 60);
    }

    #[test]
    fn the_countdown_text_uses_the_generic_formatter() {
        let config = config();
        let critical = hint(3);

        assert_eq!(
            config.countdown(&critical, 0, 0).as_deref(),
            Some("Reboot in 8 h.")
        );
        assert_eq!(
            config.countdown(&critical, 0, 3_600).as_deref(),
            Some("Reboot in 7 h.")
        );
        assert_eq!(
            config.countdown(&critical, 0, 8 * 3_600 - 1).as_deref(),
            Some("Reboot in 1 s.")
        );
    }

    #[derive(Default)]
    struct Recorder {
        shown: std::sync::Mutex<Vec<Hint>>,
    }

    impl Presenter for Recorder {
        fn present(&self, hint: &Hint) -> Result<(), PresenterError> {
            self.shown
                .lock()
                .expect("the recorder lock is fine")
                .push(hint.clone());
            Ok(())
        }

        fn close(&self, _key: &crate::agent::reconcile::HintKey) {}
    }

    #[test]
    fn the_countdown_is_added_to_the_body() {
        let config = config();
        let critical = hint(3);
        let recorder = Recorder::default();

        let mut state = PresentationState::default();
        state.critical_since.insert(key_of(&critical), 0);

        let plan = crate::agent::reconcile::Plan {
            present: vec![critical],
            close: vec![],
            state,
        };
        apply(&plan, &recorder, 0, &config);

        let shown = recorder.shown.lock().expect("the recorder lock is fine");
        assert_eq!(shown[0].body, "Body\n\nReboot in 8 h.");
    }

    #[test]
    fn a_hint_without_a_countdown_keeps_its_body() {
        let config = config();
        let important = hint(2);
        let recorder = Recorder::default();

        let plan = crate::agent::reconcile::Plan {
            present: vec![important],
            close: vec![],
            state: PresentationState::default(),
        };
        apply(&plan, &recorder, 0, &config);

        let shown = recorder.shown.lock().expect("the recorder lock is fine");
        assert_eq!(shown[0].body, "Body");
    }
}
