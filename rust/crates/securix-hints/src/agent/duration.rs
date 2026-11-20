// SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
//
// SPDX-License-Identifier: MIT

#[must_use]
pub fn remaining(seconds: i64) -> String {
    if seconds <= 0 {
        return "maintenant".to_owned();
    }

    let hours = seconds / 3_600;
    let minutes = (seconds % 3_600) / 60;
    let secs = seconds % 60;

    let mut parts = Vec::with_capacity(2);
    if hours > 0 {
        parts.push(format!("{hours} h"));
    }
    if minutes > 0 {
        parts.push(format!("{minutes} min"));
    }
    if parts.is_empty() {
        parts.push(format!("{secs} s"));
    }

    parts.join(" ")
}

#[cfg(test)]
mod tests {
    use super::remaining;

    #[test]
    fn a_long_time_uses_hours_and_minutes() {
        assert_eq!(remaining(8 * 3_600), "8 h");
        assert_eq!(remaining(8 * 3_600 + 5 * 60), "8 h 5 min");
        assert_eq!(remaining(3_600 + 60), "1 h 1 min");
    }

    #[test]
    fn a_long_time_drops_the_seconds() {
        assert_eq!(remaining(3_600 + 59), "1 h");
    }

    #[test]
    fn a_short_time_uses_seconds() {
        assert_eq!(remaining(45), "45 s");
        assert_eq!(remaining(0), "maintenant");
        assert_eq!(remaining(-5), "maintenant");
    }
}
