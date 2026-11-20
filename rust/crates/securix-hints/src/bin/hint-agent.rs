// SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
//
// SPDX-License-Identifier: MIT

// The agent uses one thread. The stream of the daemon is not `Send`.
#![allow(clippy::future_not_send)]

use std::collections::{BTreeSet, HashMap};
use std::path::Path;
use std::pin::pin;
use std::sync::{Arc, RwLock};
use std::time::Duration;

use clap::Parser;
use futures_util::StreamExt;
use securix_hints::agent::apply;
use securix_hints::agent::presenter::{ActionHandler, KdePresenter, Presenter};
use securix_hints::agent::reconcile::{key_of, reconcile, HintKey, PresentationState};
use securix_hints::agent::state::Visibility;
use securix_hints::clock;
use securix_hints::hints::{Hint, Hints as _};
use tokio::sync::mpsc;

const SNOOZE_SECONDS: i64 = 30 * 60;

const DEFAULT_RETRY_SECONDS: u64 = 30;

const REBOOT_RETRY_SECONDS: i64 = 60 * 60;

#[derive(Debug, Parser)]
#[command(name = "securix-hint-agent", about = "Show the Sécurix hints")]
struct Cli {
    #[arg(long, default_value = securix_hints::CONSUMER_SOCKET)]
    socket: std::path::PathBuf,

    #[arg(long, default_value_t = DEFAULT_RETRY_SECONDS)]
    retry: u64,

    #[arg(long)]
    once: bool,
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt().with_target(false).init();

    let cli = Cli::parse();

    let config = securix_hints::agent::Config::from_env();
    let visibility = Visibility::new();
    let seen: Arc<RwLock<HashMap<HintKey, Hint>>> = Arc::new(RwLock::new(HashMap::new()));

    let (feedback, mut notices) = mpsc::unbounded_channel::<Hint>();

    let handler = Arc::new(AgentActions {
        visibility: visibility.clone(),
        seen: Arc::clone(&seen),
        feedback,
    });
    let presenter: Arc<dyn Presenter> = Arc::new(KdePresenter::new(handler));

    let notifier = Arc::clone(&presenter);
    tokio::spawn(async move {
        while let Some(notice) = notices.recv().await {
            if let Err(error) = notifier.present(&notice) {
                tracing::warn!(%error, "the notice is not shown");
            }
        }
    });

    if cli.once {
        return read_once(&cli.socket, &seen, &visibility, presenter.as_ref(), &config).await;
    }

    loop {
        if let Err(error) =
            watch(&cli.socket, &seen, &visibility, presenter.as_ref(), &config).await
        {
            tracing::warn!(%error, "the consumer socket is not readable");
        }
        tokio::time::sleep(Duration::from_secs(cli.retry)).await;
    }
}

async fn read_once(
    socket: &Path,
    seen: &RwLock<HashMap<HintKey, Hint>>,
    visibility: &Visibility,
    presenter: &dyn Presenter,
    config: &securix_hints::agent::Config,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut connection = zlink::tokio::unix::connect(socket).await?;
    let reply = connection
        .list_hints(0)
        .await?
        .map_err(|error| format!("the daemon refused the list: {error:?}"))?;

    let mut presentation = PresentationState::default();
    handle(
        &reply.hints,
        seen,
        visibility,
        &mut presentation,
        presenter,
        config,
    );
    Ok(())
}

async fn watch(
    socket: &Path,
    seen: &RwLock<HashMap<HintKey, Hint>>,
    visibility: &Visibility,
    presenter: &dyn Presenter,
    config: &securix_hints::agent::Config,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut connection = zlink::tokio::unix::connect(socket).await?;
    let mut hints = pin!(connection.watch().await?);
    let mut presentation = PresentationState::default();
    let mut retry_at: Option<i64> = None;

    loop {
        let next = [next_deadline(&presentation, config), retry_at]
            .into_iter()
            .flatten()
            .min();
        let wake = next
            .map(|at| Duration::from_secs(u64::try_from((at - clock::now()).max(0)).unwrap_or(0)));

        let reply = if let Some(wake) = wake {
            if let Ok(reply) = tokio::time::timeout(wake, hints.next()).await {
                reply
            } else {
                retry_at = settle(&presentation, retry_at, config, presenter)?;
                continue;
            }
        } else {
            hints.next().await
        };

        let Some(reply) = reply else {
            return Ok(());
        };

        let snapshot =
            reply?.map_err(|error| format!("the daemon refused the watch: {error:?}"))?;
        handle(
            &snapshot.hints,
            seen,
            visibility,
            &mut presentation,
            presenter,
            config,
        );

        retry_at = settle(&presentation, retry_at, config, presenter)?;
    }
}

enum Attempt {
    Rebooting,
    Refused(i64),
    Waiting,
}

// A refusal must not become a loop of reboots.
fn maybe_reboot(
    presentation: &PresentationState,
    retry_at: Option<i64>,
    config: &securix_hints::agent::Config,
    presenter: &dyn Presenter,
) -> Attempt {
    if !config.auto_reboot || retry_at.is_some() || !due(presentation, config, clock::now()) {
        return Attempt::Waiting;
    }

    if reboot() {
        return Attempt::Rebooting;
    }

    let _ = presenter.present(&refused_auto());
    Attempt::Refused(clock::now() + REBOOT_RETRY_SECONDS)
}

fn settle(
    presentation: &PresentationState,
    retry_at: Option<i64>,
    config: &securix_hints::agent::Config,
    presenter: &dyn Presenter,
) -> Result<Option<i64>, Box<dyn std::error::Error>> {
    let retry_at = retry_at.filter(|at| clock::now() < *at);

    match maybe_reboot(presentation, retry_at, config, presenter) {
        Attempt::Rebooting => Err("the machine reboots".into()),
        Attempt::Refused(at) => Ok(Some(at)),
        Attempt::Waiting => Ok(retry_at),
    }
}

fn next_deadline(
    presentation: &PresentationState,
    config: &securix_hints::agent::Config,
) -> Option<i64> {
    presentation
        .critical_since
        .values()
        .map(|since| config.deadline(*since))
        .min()
}

/// Return true if a critical hint reached its reboot time.
///
/// A dismissal must not cancel the reboot. Thus, the check reads the countdown
/// data, not the hints that the agent shows.
fn due(presentation: &PresentationState, config: &securix_hints::agent::Config, now: i64) -> bool {
    presentation
        .critical_since
        .values()
        .any(|since| config.is_due(*since, now))
}

fn handle(
    hints: &[Hint],
    seen: &RwLock<HashMap<HintKey, Hint>>,
    visibility: &Visibility,
    presentation: &mut PresentationState,
    presenter: &dyn Presenter,
    config: &securix_hints::agent::Config,
) {
    {
        let mut seen = seen.write().expect("the hint map is not poisoned");
        seen.clear();
        for hint in hints {
            seen.insert(key_of(hint), hint.clone());
        }
    }

    let present: BTreeSet<HintKey> = hints.iter().map(key_of).collect();
    visibility.prune(&present);

    let now = clock::now();
    let mut plan = reconcile(hints, visibility, presentation, now, config);
    if !config.auto_reboot {
        plan.state.critical_since.clear();
    }
    apply(&plan, presenter, now, config);
    *presentation = plan.state;
}

fn reboot() -> bool {
    tracing::warn!("the countdown ended, the machine reboots");
    match std::process::Command::new("systemctl")
        .arg("reboot")
        .status()
    {
        Ok(status) if status.success() => {
            tracing::info!("the machine reboots");
            true
        }
        _ => {
            tracing::warn!("the reboot is refused");
            false
        }
    }
}

fn inhibitors() -> String {
    let json = std::process::Command::new("systemd-inhibit")
        .args(["--list", "--json=short", "--no-pager"])
        .output();

    if let Ok(output) = json {
        if output.status.success() {
            if let Ok(entries) = serde_json::from_slice::<Vec<serde_json::Value>>(&output.stdout) {
                let lines: Vec<String> = entries
                    .iter()
                    .take(MAX_INHIBITORS)
                    .map(format_inhibitor)
                    .collect();
                return if lines.is_empty() {
                    "aucun inhibiteur déclaré".to_owned()
                } else {
                    lines.join("\n")
                };
            }
        }
    }

    let text = std::process::Command::new("systemd-inhibit")
        .args(["--list", "--no-legend", "--no-pager"])
        .output();

    match text {
        Ok(output) if output.status.success() => {
            let stdout = String::from_utf8_lossy(&output.stdout);
            let lines: Vec<&str> = stdout
                .lines()
                .filter(|line| !line.trim().is_empty())
                .take(MAX_INHIBITORS)
                .collect();
            if lines.is_empty() {
                "aucun inhibiteur déclaré".to_owned()
            } else {
                lines.join("\n")
            }
        }
        _ => "la liste des inhibiteurs n'est pas lisible".to_owned(),
    }
}

const MAX_INHIBITORS: usize = 3;

fn format_inhibitor(entry: &serde_json::Value) -> String {
    let field = |name: &str| {
        entry
            .get(name)
            .and_then(serde_json::Value::as_str)
            .unwrap_or("?")
            .to_owned()
    };

    format!(
        "- {} : {} ({}, {})",
        field("who"),
        field("why"),
        field("what"),
        field("mode")
    )
}

fn refused_auto() -> Hint {
    Hint {
        source: "securix-hint-agent".to_owned(),
        key: "reboot-refused-automatic".to_owned(),
        ..refused(&("securix-hint-agent".to_owned(), "reboot".to_owned()))
    }
}

fn refused(key: &HintKey) -> Hint {
    let body = format!(
        "Le redémarrage a été refusé.\n\n\
         Deux causes sont possibles :\n\
         - un programme retient la session (un inhibiteur) ;\n\
         - l'autorisation a été refusée (polkit).\n\n\
         Inhibiteurs actifs :\n{}\n\n\
         Vérifiez avec : systemd-inhibit --list --no-pager",
        inhibitors()
    );

    Hint {
        id: String::new(),
        source: "securix-hint-agent".to_owned(),
        key: format!("reboot-refused-{}", key.1),
        kind: "notification".to_owned(),
        severity: securix_hints::severity::IMPORTANT,
        title: "Redémarrage refusé".to_owned(),
        body,
        created_at: 0,
        updated_at: 0,
        expires_at: 0,
        actions: Vec::new(),
    }
}

struct AgentActions {
    visibility: Visibility,
    seen: Arc<RwLock<HashMap<HintKey, Hint>>>,
    feedback: mpsc::UnboundedSender<Hint>,
}

impl ActionHandler for AgentActions {
    fn handle(&self, key: &HintKey, action: &str) {
        let hint = {
            let seen = self.seen.read().expect("the hint map is not poisoned");
            seen.get(key).cloned()
        };
        let Some(hint) = hint else {
            tracing::debug!(source = %key.0, key = %key.1, "the hint is gone");
            return;
        };

        match action {
            "snooze" => match self.visibility.snooze(&hint, SNOOZE_SECONDS, clock::now()) {
                Ok(()) => tracing::info!(source = %key.0, key = %key.1, "the user snoozed"),
                Err(error) => tracing::info!(?error, "the hint cannot be snoozed"),
            },
            "dismiss" => {
                self.visibility.dismiss(&hint);
                tracing::info!(source = %key.0, key = %key.1, "the user dismissed");
            }
            "reboot" => {
                match std::process::Command::new("systemctl")
                    .arg("reboot")
                    .status()
                {
                    Ok(status) if status.success() => {
                        tracing::info!(source = %key.0, key = %key.1, "the user reboots");
                    }
                    _ => {
                        tracing::warn!(source = %key.0, key = %key.1, "the reboot is refused");
                        let _ = self.feedback.send(refused(key));
                    }
                }
            }
            other => tracing::debug!(action = other, "unknown hint action"),
        }
    }
}
