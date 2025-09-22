//! ztime: Advanced Date/Time Library for Zig
//! Provides timezone handling, calendar systems, and astronomical calculations
const std = @import("std");
const Allocator = std.mem.Allocator;

// Re-export all public modules
pub const timezone = @import("timezone.zig");
pub const calendar = @import("calendar.zig");
pub const format = @import("format.zig");
pub const astronomy = @import("astronomy.zig");
pub const business = @import("business.zig");

// Core types
pub const Duration = struct {
    nanoseconds: i64,

    pub fn fromSeconds(seconds: i64) Duration {
        return Duration{ .nanoseconds = seconds * std.time.ns_per_s };
    }

    pub fn fromMinutes(minutes: i64) Duration {
        return Duration{ .nanoseconds = minutes * std.time.ns_per_min };
    }

    pub fn fromHours(hours: i64) Duration {
        return Duration{ .nanoseconds = hours * std.time.ns_per_hour };
    }

    pub fn fromDays(days: i64) Duration {
        return Duration{ .nanoseconds = days * std.time.ns_per_day };
    }

    pub fn add(self: Duration, other: Duration) Duration {
        return Duration{ .nanoseconds = self.nanoseconds + other.nanoseconds };
    }

    pub fn sub(self: Duration, other: Duration) Duration {
        return Duration{ .nanoseconds = self.nanoseconds - other.nanoseconds };
    }

    pub fn toSeconds(self: Duration) f64 {
        return @as(f64, @floatFromInt(self.nanoseconds)) / @as(f64, @floatFromInt(std.time.ns_per_s));
    }

    pub fn toMinutes(self: Duration) f64 {
        return @as(f64, @floatFromInt(self.nanoseconds)) / @as(f64, @floatFromInt(std.time.ns_per_min));
    }

    pub fn toHours(self: Duration) f64 {
        return @as(f64, @floatFromInt(self.nanoseconds)) / @as(f64, @floatFromInt(std.time.ns_per_hour));
    }

    pub fn toDays(self: Duration) f64 {
        return @as(f64, @floatFromInt(self.nanoseconds)) / @as(f64, @floatFromInt(std.time.ns_per_day));
    }
};

pub const Locale = struct {
    language: []const u8,
    country: []const u8,

    pub const DEFAULT = Locale{ .language = "en", .country = "US" };
    pub const EN_US = Locale{ .language = "en", .country = "US" };
    pub const DE_DE = Locale{ .language = "de", .country = "DE" };
    pub const FR_FR = Locale{ .language = "fr", .country = "FR" };
};

pub const TimeZone = struct {
    name: []const u8,
    offset_seconds: i32,

    pub fn fromName(name: []const u8) !TimeZone {
        // Use IANA timezone database
        if (timezone.lookupTimeZone(name)) |tz_data| {
            // Get current offset (simplified - would need current time for DST)
            const base_offset = if (tz_data.rules.len > 0) tz_data.rules[0].offset_seconds else 0;
            return TimeZone{ .name = tz_data.name, .offset_seconds = base_offset };
        }

        // Fallback to basic timezone support
        if (std.mem.eql(u8, name, "UTC")) {
            return TimeZone{ .name = name, .offset_seconds = 0 };
        } else if (std.mem.eql(u8, name, "EST")) {
            return TimeZone{ .name = name, .offset_seconds = -5 * 3600 };
        } else if (std.mem.eql(u8, name, "PST")) {
            return TimeZone{ .name = name, .offset_seconds = -8 * 3600 };
        }
        return error.UnknownTimeZone;
    }

    pub fn getOffset(self: TimeZone, when: DateTime) Duration {
        // For IANA timezones, use the database
        if (timezone.lookupTimeZone(self.name)) |tz_data| {
            return tz_data.getOffset(@divFloor(when.timestamp_ns, std.time.ns_per_s));
        }
        // Fallback to static offset
        return Duration.fromSeconds(self.offset_seconds);
    }

    pub fn isDST(self: TimeZone, when: DateTime) bool {
        if (timezone.lookupTimeZone(self.name)) |tz_data| {
            return tz_data.isDST(@divFloor(when.timestamp_ns, std.time.ns_per_s));
        }
        return false;
    }
};

pub const DateTime = struct {
    timestamp_ns: i64, // Nanoseconds since Unix epoch
    timezone: TimeZone,

    pub fn now(tz: TimeZone) DateTime {
        const ns = std.time.nanoTimestamp();
        return DateTime{
            .timestamp_ns = @intCast(ns),
            .timezone = tz,
        };
    }

    pub fn fromUnixTimestamp(timestamp: i64, tz: TimeZone) DateTime {
        return DateTime{
            .timestamp_ns = timestamp * std.time.ns_per_s,
            .timezone = tz,
        };
    }

    pub fn fromDate(date: calendar.Date, tz: TimeZone) DateTime {
        const cal = calendar.Calendar.init(.gregorian);
        const timestamp = cal.unixTimestampFromDate(date);
        return DateTime{
            .timestamp_ns = timestamp * std.time.ns_per_s,
            .timezone = tz,
        };
    }

    pub fn parse(input: []const u8, fmt_string: []const u8, allocator: Allocator) !DateTime {
        const fmt_mod = @import("format.zig");
        return fmt_mod.parseDateTime(input, fmt_string, allocator);
    }

    pub fn format(self: DateTime, fmt_string: []const u8, locale: Locale, allocator: Allocator) ![]u8 {
        const fmt_mod = @import("format.zig");
        return fmt_mod.formatDateTime(allocator, self, fmt_string, locale);
    }

    pub fn addBusinessDays(self: DateTime, days: i32) DateTime {
        return business.BusinessCalendar.US_FEDERAL.addBusinessDays(self, days);
    }

    pub fn addBusinessDaysWithCalendar(self: DateTime, days: i32, cal: business.BusinessCalendar) DateTime {
        return cal.addBusinessDays(self, days);
    }

    pub fn addDuration(self: DateTime, duration: Duration) DateTime {
        return DateTime{
            .timestamp_ns = self.timestamp_ns + duration.nanoseconds,
            .timezone = self.timezone,
        };
    }

    pub fn subDuration(self: DateTime, duration: Duration) DateTime {
        return DateTime{
            .timestamp_ns = self.timestamp_ns - duration.nanoseconds,
            .timezone = self.timezone,
        };
    }

    pub fn durationBetween(self: DateTime, other: DateTime) Duration {
        return Duration{ .nanoseconds = self.timestamp_ns - other.timestamp_ns };
    }

    pub fn toUnixTimestamp(self: DateTime) i64 {
        return @divFloor(self.timestamp_ns, std.time.ns_per_s);
    }

    pub fn toDate(self: DateTime, calendar_type: calendar.CalendarType) calendar.Date {
        const cal = calendar.Calendar.init(calendar_type);
        return cal.dateFromUnixTimestamp(self.toUnixTimestamp());
    }

    pub fn toTimeZone(self: DateTime, new_timezone: TimeZone) DateTime {
        return DateTime{
            .timestamp_ns = self.timestamp_ns,
            .timezone = new_timezone,
        };
    }

    pub fn isBusinessDay(self: DateTime) bool {
        return business.BusinessCalendar.US_FEDERAL.isBusinessDay(self);
    }

    pub fn isBusinessDayWithCalendar(self: DateTime, cal: business.BusinessCalendar) bool {
        return cal.isBusinessDay(self);
    }

    pub fn isHoliday(self: DateTime) ?[]const u8 {
        return business.BusinessCalendar.US_FEDERAL.isHoliday(self);
    }

    pub fn getSolarEvents(self: DateTime, coords: astronomy.Coordinates) astronomy.SolarEvent {
        return astronomy.calculateSolarEvents(self, coords);
    }

    pub fn getLunarPhase(self: DateTime) astronomy.MoonPhaseInfo {
        return astronomy.calculateLunarPhase(self);
    }

    pub fn getSolarElevation(self: DateTime, coords: astronomy.Coordinates) f64 {
        return astronomy.calculateSolarElevation(self, coords);
    }

    pub fn getSolarAzimuth(self: DateTime, coords: astronomy.Coordinates) f64 {
        return astronomy.calculateSolarAzimuth(self, coords);
    }
};

// Convenience functions
pub fn utcNow() DateTime {
    return DateTime.now(TimeZone{ .name = "UTC", .offset_seconds = 0 });
}

pub fn parseISO8601(input: []const u8) !DateTime {
    const fmt_mod = @import("format.zig");
    return fmt_mod.parseDateTime(input, "%Y-%m-%dT%H:%M:%SZ", std.testing.allocator);
}

pub fn formatISO8601(dt: DateTime, allocator: Allocator) ![]u8 {
    return dt.format("%Y-%m-%dT%H:%M:%SZ", Locale.DEFAULT, allocator);
}

test "DateTime creation and basic operations" {
    const utc = try TimeZone.fromName("UTC");
    const dt = DateTime.now(utc);

    // Test that timestamp is reasonable (after year 2020)
    const year_2020_timestamp = 1577836800; // 2020-01-01 00:00:00 UTC
    try std.testing.expect(dt.toUnixTimestamp() > year_2020_timestamp);
}

test "TimeZone operations" {
    const utc = try TimeZone.fromName("UTC");
    const est = try TimeZone.fromName("EST");

    try std.testing.expectEqual(@as(i32, 0), utc.offset_seconds);
    try std.testing.expectEqual(@as(i32, -5 * 3600), est.offset_seconds);
}

test "Duration operations" {
    const one_hour = Duration.fromHours(1);
    const sixty_minutes = Duration.fromMinutes(60);

    try std.testing.expectEqual(one_hour.nanoseconds, sixty_minutes.nanoseconds);
}
