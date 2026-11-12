// SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
//
// SPDX-License-Identifier: MIT

//! The hint daemon.

use std::path::PathBuf;

use securix_hints::clock;
use securix_hints::daemon::consumer::HintConsumer;
use securix_hints::daemon::control::HintControl;
use securix_hints::daemon::sockets;
use securix_hints::daemon::state::HintState;
use zlink::Server;

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt().with_target(false).init();

    let mut arguments = std::env::args().skip(1);
    let control_path = arguments.next().map_or_else(
        || PathBuf::from(securix_hints::CONTROL_SOCKET),
        PathBuf::from,
    );
    let consumer_path = arguments.next().map_or_else(
        || PathBuf::from(securix_hints::CONSUMER_SOCKET),
        PathBuf::from,
    );

    let state = HintState::new(clock::store_path(), env!("CARGO_PKG_VERSION"));
    if let Err(error) = state.load() {
        tracing::warn!(%error, "the persisted hints are not readable");
    }

    // systemd passes the sockets when it starts the daemon from a socket unit.
    // Outside systemd, the daemon binds them itself.
    let (control_listener, consumer_listener) = match sockets::inherited()? {
        Some(listeners) => listeners,
        None => (
            sockets::bind_control(&control_path)?,
            sockets::bind_consumer(&consumer_path)?,
        ),
    };

    let control = Server::new(control_listener, HintControl::new(state.clone()));
    let consumer = Server::new(consumer_listener, HintConsumer::new(state.clone()));
    let sweeper = sweep(state);

    tokio::select! {
        result = control.run() => result?,
        result = consumer.run() => result?,
        () = sweeper => {}
    }

    Ok(())
}

/// Remove the expired hints on a timer.
async fn sweep(state: HintState) {
    let mut interval = tokio::time::interval(clock::sweep_interval());
    loop {
        interval.tick().await;
        state.sweep_expired(clock::now());
    }
}
