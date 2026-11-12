// SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
//
// SPDX-License-Identifier: MIT

//! The command-line client of the hint daemon.

use std::path::PathBuf;

use clap::{Parser, Subcommand};
use securix_hints::hints::Hints as _;
use securix_hints::hints_control::HintsControl as _;

/// The command-line client.
#[derive(Debug, Parser)]
#[command(name = "securix-hintctl", about = "Control the Sécurix hints")]
struct Cli {
    /// The control socket.
    #[arg(long, global = true)]
    control: Option<PathBuf>,

    /// The consumer socket.
    #[arg(long, global = true)]
    consumer: Option<PathBuf>,

    /// The command to run.
    #[command(subcommand)]
    command: Command,
}

/// The command to run.
#[derive(Debug, Subcommand)]
enum Command {
    /// List the hints.
    List {
        /// Keep only the hints with a severity at least this value.
        #[arg(long, default_value_t = 0)]
        min_severity: i64,
    },

    /// Print a summary of the daemon state.
    Status,

    /// Print one hint.
    Get {
        /// The producer name.
        source: String,
        /// The key of the hint.
        key: String,
    },

    /// Create a hint, or update the hint with the same source and key.
    Set {
        /// The producer name.
        #[arg(long)]
        source: String,
        /// The key of the hint.
        #[arg(long)]
        key: String,
        /// The kind of the hint.
        #[arg(long, default_value = "maintenance")]
        kind: String,
        /// The severity of the hint, from 0 to 3.
        #[arg(long, default_value_t = 1)]
        severity: i64,
        /// The short title.
        #[arg(long)]
        title: String,
        /// The longer text.
        #[arg(long, default_value = "")]
        body: String,
        /// The Unix time at which the hint expires. Zero means no expiry.
        #[arg(long, default_value_t = 0)]
        expires_at: i64,
    },

    /// Remove one hint.
    Clear {
        /// The producer name.
        source: String,
        /// The key of the hint.
        key: String,
    },

    /// Remove each hint of one source.
    ClearSource {
        /// The producer name.
        source: String,
    },
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cli = Cli::parse();
    let control = cli
        .control
        .clone()
        .unwrap_or_else(|| PathBuf::from(securix_hints::CONTROL_SOCKET));
    let consumer = cli
        .consumer
        .clone()
        .unwrap_or_else(|| PathBuf::from(securix_hints::CONSUMER_SOCKET));

    match &cli.command {
        Command::List { min_severity } => {
            let mut connection = zlink::tokio::unix::connect(&consumer).await?;
            print(
                &connection
                    .list_hints(*min_severity)
                    .await?
                    .map_err(display)?,
            )?;
        }
        Command::Status => {
            let mut connection = zlink::tokio::unix::connect(&consumer).await?;
            print(&connection.get_status().await?.map_err(display)?)?;
        }
        Command::Get { source, key } => {
            let mut connection = zlink::tokio::unix::connect(&consumer).await?;
            print(&connection.get_hint(source, key).await?.map_err(display)?)?;
        }
        Command::Set {
            source,
            key,
            kind,
            severity,
            title,
            body,
            expires_at,
        } => {
            let mut connection = zlink::tokio::unix::connect(&control).await?;
            let reply = connection
                .upsert_hint(source, key, kind, *severity, title, body, *expires_at, &[])
                .await?
                .map_err(display)?;
            print(&reply)?;
        }
        Command::Clear { source, key } => {
            let mut connection = zlink::tokio::unix::connect(&control).await?;
            connection.clear_hint(source, key).await?.map_err(display)?;
        }
        Command::ClearSource { source } => {
            let mut connection = zlink::tokio::unix::connect(&control).await?;
            connection.clear_source(source).await?.map_err(display)?;
        }
    }

    Ok(())
}

/// Print a value as JSON.
fn print<T: serde::Serialize>(value: &T) -> Result<(), Box<dyn std::error::Error>> {
    println!("{}", serde_json::to_string_pretty(value)?);
    Ok(())
}

/// Turn a protocol error into a printable message.
fn display(error: impl std::fmt::Debug) -> String {
    format!("{error:?}")
}
