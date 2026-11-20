// SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
//
// SPDX-License-Identifier: MIT

//! The sockets of the daemon.
//!
//! systemd makes the sockets when it starts the daemon from a socket unit via socket activation.
//!
//! Without systemd, the daemon makes the sockets and sets the permissions.

use std::error::Error;
use std::io;
use std::os::fd::OwnedFd;
use std::os::unix::fs::{chown, PermissionsExt};
use std::path::Path;

use zlink::tokio::unix::{bind, Listener};

/// The group that owns the control socket.
pub const CONTROL_GROUP: &str = "securix-hints";

/// The mode of the control socket.
pub const CONTROL_MODE: u32 = 0o600;

/// The mode of the consumer socket.
pub const CONSUMER_MODE: u32 = 0o666;

/// The `LISTEN_FDNAMES` name of the control socket.
pub const CONTROL_FD_NAME: &str = "control";

/// The `LISTEN_FDNAMES` name of the consumer socket.
pub const CONSUMER_FD_NAME: &str = "consumer";

/// Take the two listeners that systemd gave, if systemd gave them.
///
/// systemd gives the sockets of the socket units that name this service. The
/// names in `LISTEN_FDNAMES` identify each socket.
///
/// # Errors
///
/// Return an error if systemd passed the sockets but one is missing or is not
/// a Unix stream socket.
pub fn inherited() -> Result<Option<(Listener, Listener)>, Box<dyn Error>> {
    let Ok(names) = std::env::var("LISTEN_FDNAMES") else {
        return Ok(None);
    };
    let names: Vec<&str> = names.split(':').collect();
    let (Some(control_index), Some(consumer_index)) = (
        names.iter().position(|name| *name == CONTROL_FD_NAME),
        names.iter().position(|name| *name == CONSUMER_FD_NAME),
    ) else {
        return Ok(None);
    };

    let mut listenfd = listenfd::ListenFd::from_env();
    if listenfd.len() == 0 {
        return Ok(None);
    }

    let control = take_listener(&mut listenfd, control_index)?;
    let consumer = take_listener(&mut listenfd, consumer_index)?;
    Ok(Some((control, consumer)))
}

/// Take one Unix listener from systemd and give it to `zlink`.
fn take_listener(
    listenfd: &mut listenfd::ListenFd,
    index: usize,
) -> Result<Listener, Box<dyn Error>> {
    let listener = listenfd.take_unix_listener(index)?.ok_or_else(|| {
        io::Error::new(io::ErrorKind::NotFound, "systemd did not pass the socket")
    })?;
    let fd: OwnedFd = listener.into();
    Ok(Listener::try_from(fd)?)
}

/// Make the control socket when systemd is absent.
///
/// # Errors
///
/// Return an error if the bind or a permission change fails.
pub fn bind_control(path: &Path) -> Result<Listener, Box<dyn Error>> {
    let listener = bind(path)?;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(CONTROL_MODE))?;
    if let Some(gid) = group_id(CONTROL_GROUP) {
        chown(path, None, Some(gid))?;
    }
    Ok(listener)
}

/// Make the consumer socket when systemd is absent.
///
/// # Errors
///
/// Return an error if the bind or the permission change fails.
pub fn bind_consumer(path: &Path) -> Result<Listener, Box<dyn Error>> {
    let listener = bind(path)?;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(CONSUMER_MODE))?;
    Ok(listener)
}

/// Return the gid of `name` from `/etc/group`.
///
/// Return `None` if the group does not exist. Thus, the daemon can start before
/// the group exists.
fn group_id(name: &str) -> Option<u32> {
    let content = std::fs::read_to_string("/etc/group").ok()?;
    content.lines().find_map(|line| {
        let mut fields = line.split(':');
        let group = fields.next()?;
        if group != name {
            return None;
        }
        let _password = fields.next()?;
        fields.next()?.parse().ok()
    })
}
