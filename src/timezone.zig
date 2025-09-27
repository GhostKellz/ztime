//! IANA Timezone Database implementation
const std = @import("std");
const Duration = @import("root.zig").Duration;
const generated = @import("generated/timezones.zig");

pub const TZRule = generated.TZRule;
pub const TimeZoneData = generated.TimeZoneData;
pub const VERSION = generated.VERSION;
pub const FIXED_OFFSET_NAME = "UTC-offset";

pub fn lookupTimeZone(name: []const u8) ?TimeZoneData {
    return generated.lookupTimeZone(name);
}

pub fn allTimeZones() []const TimeZoneData {
    return generated.allTimeZones();
}

pub fn getOffsetSeconds(data: TimeZoneData, timestamp: i64) i32 {
    if (data.rules.len == 0) return 0;

    var selected = data.rules[0];
    for (data.rules) |rule| {
        if (timestamp >= rule.starts_at and timestamp < rule.ends_at) {
            selected = rule;
            break;
        }
        if (timestamp >= rule.starts_at) {
            selected = rule;
        }
    }

    return selected.offset_seconds + selected.dst_offset_seconds;
}

pub fn getOffset(data: TimeZoneData, timestamp: i64) Duration {
    return Duration.fromSeconds(getOffsetSeconds(data, timestamp));
}

pub fn isDST(data: TimeZoneData, timestamp: i64) bool {
    if (data.rules.len == 0) return false;

    var selected = data.rules[0];
    for (data.rules) |rule| {
        if (timestamp >= rule.starts_at and timestamp < rule.ends_at) {
            selected = rule;
            break;
        }
        if (timestamp >= rule.starts_at) {
            selected = rule;
        }
    }

    return selected.dst_offset_seconds != 0;
}

test "IANA timezone lookup" {
    const utc = lookupTimeZone("UTC").?;
    try std.testing.expectEqualStrings("UTC", utc.name);

    const ny = lookupTimeZone("America/New_York").?;
    try std.testing.expectEqualStrings("America/New_York", ny.name);
}

test "DST detection" {
    const ny = lookupTimeZone("America/New_York").?;

    // Test EST period (no DST) - 2024-01-01 00:00:00 UTC
    const est_timestamp: i64 = 1704067200;
    try std.testing.expect(!isDST(ny, est_timestamp));

    // Test EDT period (DST) - 2024-06-01 00:00:00 UTC
    const edt_timestamp: i64 = 1717200000;
    try std.testing.expect(isDST(ny, edt_timestamp));
}
