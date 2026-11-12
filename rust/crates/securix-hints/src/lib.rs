// SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
//
// SPDX-License-Identifier: MIT

//! Hints about the state of the machine.
//!
//! A hint tells the user about the machine. Example: "A new generation is
//! ready. Reboot to activate it."
//!
//! A producer sends a hint to the daemon. The daemon keeps the hint until the
//! producer removes it, or until the hint expires.
//!
//! The daemon has two Varlink interfaces:
//!
//! - [`hints`] reads the hints. Each user can open its socket.
//! - [`hints_control`] writes the hints. Only the root user and the
//!   `securix-hints` group can open its socket.

pub mod clock;
pub mod cooldown;
pub mod daemon;
pub mod hints;
pub mod hints_control;
pub mod severity;
pub mod store;
pub mod types;

/// The path of the control socket.
pub const CONTROL_SOCKET: &str = "/run/securix-hints/control.sock";

/// The path of the consumer socket.
pub const CONSUMER_SOCKET: &str = "/run/securix-hints/consumer.sock";

/// The path of the persisted hints.
pub const STORE_PATH: &str = "/run/securix-hints/hints.json";
