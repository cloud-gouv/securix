// SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
//
// SPDX-License-Identifier: MIT

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use crate::agent::reconcile::HintKey;
use crate::hints::Hint;
use crate::severity;

pub trait ActionHandler: Send + Sync {
    fn handle(&self, key: &HintKey, action: &str);
}

pub trait Presenter: Send + Sync {
    /// # Errors
    ///
    /// Return [`PresenterError`] if the notification daemon refuses the hint.
    fn present(&self, hint: &Hint) -> Result<(), PresenterError>;

    fn close(&self, key: &HintKey);
}

#[derive(Debug, thiserror::Error)]
pub enum PresenterError {
    #[error("the notification daemon refused the hint")]
    Notification,
}

/// The presenter of a KDE session.
///
/// It cannot close a notification with an action: `wait_for_action` owns it.
pub struct KdePresenter {
    handler: Arc<dyn ActionHandler>,
    open: Mutex<HashMap<HintKey, notify_rust::NotificationHandle>>,
}

impl KdePresenter {
    #[must_use]
    pub fn new(handler: Arc<dyn ActionHandler>) -> Self {
        Self {
            handler,
            open: Mutex::new(HashMap::new()),
        }
    }
}

impl Presenter for KdePresenter {
    fn present(&self, hint: &Hint) -> Result<(), PresenterError> {
        use notify_rust::{Hint as NotifyHint, Notification, Timeout};

        let mut notification = Notification::new();
        notification
            .appname("Sécurix")
            .summary(&hint.title)
            .body(&hint.body)
            .hint(NotifyHint::Transient(true));

        for action in &hint.actions {
            notification.action(&action.id, &action.label);
        }
        if hint.severity >= severity::CRITICAL {
            notification.timeout(Timeout::Never);
        }

        let handle = notification
            .show()
            .map_err(|_| PresenterError::Notification)?;
        let key = crate::agent::reconcile::key_of(hint);

        if hint.actions.is_empty() {
            let previous = {
                let mut open = self.open.lock().expect("the notification map is fine");
                open.insert(key, handle)
            };
            if let Some(previous) = previous {
                previous.close();
            }
            return Ok(());
        }

        let handler = Arc::clone(&self.handler);
        std::thread::spawn(move || {
            handle.wait_for_action(|action| {
                if action != "__closed" {
                    handler.handle(&key, action);
                }
            });
        });

        Ok(())
    }

    fn close(&self, key: &HintKey) {
        let handle = self
            .open
            .lock()
            .expect("the notification map is fine")
            .remove(key);

        if let Some(handle) = handle {
            handle.close();
        }
    }
}
