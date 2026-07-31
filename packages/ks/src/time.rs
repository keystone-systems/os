//! Shared time utilities for ISO 8601 formatting and date arithmetic.
//!
//! Extracted from tasks.rs to enable reuse across commands.

/// Return the current UTC time as an ISO 8601 string (`YYYY-MM-DDTHH:MM:SSZ`).
pub fn iso_now() -> String {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let secs_per_day = 86400u64;
    let days = now / secs_per_day;
    let time_of_day = now % secs_per_day;
    let hours = time_of_day / 3600;
    let minutes = (time_of_day % 3600) / 60;
    let seconds = time_of_day % 60;
    let (year, month, day) = epoch_days_to_ymd(days);
    format!("{year:04}-{month:02}-{day:02}T{hours:02}:{minutes:02}:{seconds:02}Z")
}

/// Convert days since Unix epoch to (year, month, day) using the civil calendar algorithm.
pub fn epoch_days_to_ymd(days: u64) -> (u64, u64, u64) {
    let z = days + 719468;
    let era = z / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    (y, m, d)
}

/// Return an ISO 8601 date string for `days` days ago (`YYYY-MM-DD`).
pub fn chrono_days_ago(days: u64) -> String {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let past = now.saturating_sub(days * 86400);
    let (year, month, day) = epoch_days_to_ymd(past / 86400);
    format!("{year:04}-{month:02}-{day:02}")
}

/// Compute the number of whole days between an ISO 8601 date/datetime and now.
///
/// Accepts both `YYYY-MM-DD` and `YYYY-MM-DDTHH:MM:SSZ` formats.
/// Returns 0 if the date cannot be parsed or is in the future.
pub fn days_since(iso_date: &str) -> u64 {
    let date_part = if iso_date.len() >= 10 {
        &iso_date[..10]
    } else {
        return 0;
    };

    let parts: Vec<&str> = date_part.split('-').collect();
    if parts.len() != 3 {
        return 0;
    }

    let year: u64 = parts[0].parse().unwrap_or(0);
    let month: u64 = parts[1].parse().unwrap_or(0);
    let day: u64 = parts[2].parse().unwrap_or(0);

    if year == 0 || month == 0 || day == 0 {
        return 0;
    }

    // Convert to days since epoch using the inverse of epoch_days_to_ymd
    let target_days = ymd_to_epoch_days(year, month, day);

    let now_secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let now_days = now_secs / 86400;

    now_days.saturating_sub(target_days)
}

/// Convert (year, month, day) to days since Unix epoch.
/// Inverse of `epoch_days_to_ymd`.
fn ymd_to_epoch_days(year: u64, month: u64, day: u64) -> u64 {
    // Adjust year/month for the algorithm (months March=3..Feb=14)
    let (y, m) = if month <= 2 {
        (year - 1, month + 9)
    } else {
        (year, month - 3)
    };
    let era = y / 400;
    let yoe = y - era * 400;
    let doy = (153 * m + 2) / 5 + day - 1;
    let doe = 365 * yoe + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_iso_now_format() {
        let now = iso_now();
        assert!(now.len() == 20, "unexpected length: {now}");
        assert!(now.ends_with('Z'));
        assert_eq!(&now[4..5], "-");
        assert_eq!(&now[10..11], "T");
    }

    #[test]
    fn test_epoch_known_date() {
        let (y, m, d) = epoch_days_to_ymd(20454);
        assert_eq!((y, m, d), (2026, 1, 1));
    }

    #[test]
    fn test_ymd_roundtrip() {
        let days = ymd_to_epoch_days(2026, 1, 1);
        let (y, m, d) = epoch_days_to_ymd(days);
        assert_eq!((y, m, d), (2026, 1, 1));
    }

    #[test]
    fn test_days_since_today_is_zero() {
        let today = &iso_now()[..10];
        assert_eq!(days_since(today), 0);
    }

    #[test]
    fn test_days_since_known_date() {
        // days_since returns approximate days; just verify it's > 0 for a past date
        let d = days_since("2020-01-01");
        assert!(d > 365 * 5, "expected >5 years of days, got {d}");
    }

    #[test]
    fn test_days_since_datetime_format() {
        let d = days_since("2020-01-01T12:00:00Z");
        assert!(d > 365 * 5);
    }

    #[test]
    fn test_days_since_invalid() {
        assert_eq!(days_since("garbage"), 0);
        assert_eq!(days_since(""), 0);
    }
}
