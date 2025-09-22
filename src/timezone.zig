//! IANA Timezone Database implementation
const std = @import("std");
const Duration = @import("root.zig").Duration;

pub const TZRule = struct {
    offset_seconds: i32,
    dst_offset_seconds: i32,
    starts_at: i64, // Unix timestamp when this rule starts
    ends_at: i64,   // Unix timestamp when this rule ends
    name: []const u8,
};

pub const TimeZoneData = struct {
    name: []const u8,
    rules: []const TZRule,

    pub fn getOffset(self: TimeZoneData, timestamp: i64) Duration {
        // Find the applicable rule for the given timestamp
        for (self.rules) |rule| {
            if (timestamp >= rule.starts_at and timestamp < rule.ends_at) {
                const total_offset = rule.offset_seconds + rule.dst_offset_seconds;
                return Duration.fromSeconds(total_offset);
            }
        }

        // Default to the last rule if no match found
        if (self.rules.len > 0) {
            const last_rule = self.rules[self.rules.len - 1];
            const total_offset = last_rule.offset_seconds + last_rule.dst_offset_seconds;
            return Duration.fromSeconds(total_offset);
        }

        return Duration.fromSeconds(0);
    }

    pub fn isDST(self: TimeZoneData, timestamp: i64) bool {
        for (self.rules) |rule| {
            if (timestamp >= rule.starts_at and timestamp < rule.ends_at) {
                return rule.dst_offset_seconds != 0;
            }
        }
        return false;
    }
};

// IANA timezone database (simplified version with common zones)
const TIMEZONE_DB = std.StaticStringMap(TimeZoneData).initComptime(.{
    .{ "UTC", TimeZoneData{
        .name = "UTC",
        .rules = &[_]TZRule{
            TZRule{
                .offset_seconds = 0,
                .dst_offset_seconds = 0,
                .starts_at = 0,
                .ends_at = std.math.maxInt(i64),
                .name = "UTC",
            },
        },
    }},
    .{ "America/New_York", TimeZoneData{
        .name = "America/New_York",
        .rules = &[_]TZRule{
            // EST (Standard Time)
            TZRule{
                .offset_seconds = -5 * 3600,
                .dst_offset_seconds = 0,
                .starts_at = 0,
                .ends_at = 1583647200, // March 8, 2020 (example DST start)
                .name = "EST",
            },
            // EDT (Daylight Time)
            TZRule{
                .offset_seconds = -5 * 3600,
                .dst_offset_seconds = 3600,
                .starts_at = 1583647200,
                .ends_at = 1604210400, // November 1, 2020 (example DST end)
                .name = "EDT",
            },
        },
    }},
    .{ "Europe/London", TimeZoneData{
        .name = "Europe/London",
        .rules = &[_]TZRule{
            // GMT (Standard Time)
            TZRule{
                .offset_seconds = 0,
                .dst_offset_seconds = 0,
                .starts_at = 0,
                .ends_at = 1585443600, // March 29, 2020 (example BST start)
                .name = "GMT",
            },
            // BST (British Summer Time)
            TZRule{
                .offset_seconds = 0,
                .dst_offset_seconds = 3600,
                .starts_at = 1585443600,
                .ends_at = 1603584000, // October 25, 2020 (example BST end)
                .name = "BST",
            },
        },
    }},
    .{ "Asia/Tokyo", TimeZoneData{
        .name = "Asia/Tokyo",
        .rules = &[_]TZRule{
            TZRule{
                .offset_seconds = 9 * 3600,
                .dst_offset_seconds = 0,
                .starts_at = 0,
                .ends_at = std.math.maxInt(i64),
                .name = "JST",
            },
        },
    }},
    .{ "Australia/Sydney", TimeZoneData{
        .name = "Australia/Sydney",
        .rules = &[_]TZRule{
            // AEST (Standard Time)
            TZRule{
                .offset_seconds = 10 * 3600,
                .dst_offset_seconds = 0,
                .starts_at = 0,
                .ends_at = 1583053200, // March 1, 2020 (example AEDT end)
                .name = "AEST",
            },
            // AEDT (Daylight Time)
            TZRule{
                .offset_seconds = 10 * 3600,
                .dst_offset_seconds = 3600,
                .starts_at = 1583053200,
                .ends_at = 1601738400, // October 4, 2020 (example AEDT start)
                .name = "AEDT",
            },
        },
    }},
});

pub fn lookupTimeZone(name: []const u8) ?TimeZoneData {
    return TIMEZONE_DB.get(name);
}

test "IANA timezone lookup" {
    const utc = lookupTimeZone("UTC").?;
    try std.testing.expectEqualStrings("UTC", utc.name);

    const ny = lookupTimeZone("America/New_York").?;
    try std.testing.expectEqualStrings("America/New_York", ny.name);
}

test "DST detection" {
    const ny = lookupTimeZone("America/New_York").?;

    // Test EST period (no DST)
    const est_timestamp: i64 = 1577836800; // 2020-01-01 00:00:00 UTC
    try std.testing.expect(!ny.isDST(est_timestamp));

    // Test EDT period (DST)
    const edt_timestamp: i64 = 1590969600; // 2020-06-01 00:00:00 UTC
    try std.testing.expect(ny.isDST(edt_timestamp));
}