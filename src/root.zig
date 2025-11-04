//! ztime: Advanced Date/Time Library for Zig
//! Provides timezone handling, calendar systems, and astronomical calculations
const std = @import("std");
const builtin = @import("builtin");
const errors = @import("errors.zig");
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

    pub fn fromName(name: []const u8) errors.TimeZoneError!TimeZone {
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
        return errors.TimeZoneError.UnknownTimeZone;
    }

    pub fn getOffset(self: TimeZone, when: DateTime) Duration {
        // For IANA timezones, use the database
        if (timezone.lookupTimeZone(self.name)) |tz_data| {
            return timezone.getOffset(tz_data, @divFloor(when.timestamp_ns, std.time.ns_per_s));
        }
        // Fallback to static offset
        return Duration.fromSeconds(self.offset_seconds);
    }

    pub fn isDST(self: TimeZone, when: DateTime) bool {
        if (timezone.lookupTimeZone(self.name)) |tz_data| {
            return timezone.isDST(tz_data, @divFloor(when.timestamp_ns, std.time.ns_per_s));
        }
        return false;
    }
};

pub const DateTime = struct {
    timestamp_ns: i64, // Nanoseconds since Unix epoch
    timezone: TimeZone,

    pub fn now(tz: TimeZone) DateTime {
            const ns = systemTimestampNs();
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
    const allocator = std.heap.page_allocator;
    const has_fraction = std.mem.indexOfScalar(u8, input, '.') != null;

    const patterns_with_fraction = [_][]const u8{
        "%Y-%m-%dT%H:%M:%S.%f%z",
        "%Y-%m-%dT%H:%M:%S.%f%Z",
        "%Y-%m-%dT%H:%M:%S.%f",
    };

    const patterns_without_fraction = [_][]const u8{
        "%Y-%m-%dT%H:%M:%S%z",
        "%Y-%m-%dT%H:%M:%S%Z",
        "%Y-%m-%dT%H:%M:%S",
    };

    const patterns = if (has_fraction) patterns_with_fraction[0..] else patterns_without_fraction[0..];

    var last_err: anyerror = error.InvalidFormat;
    for (patterns) |pattern| {
        const parsed = fmt_mod.parseDateTime(input, pattern, allocator) catch |err| {
            last_err = err;
            continue;
        };
        return parsed;
    }

    return last_err;
}

fn systemTimestampNs() i64 {
    return switch (builtin.os.tag) {
        .windows => systemTimestampWindows(),
        else => systemTimestampPosix(),
    };
}

fn systemTimestampPosix() i64 {
    const ts = std.posix.clock_gettime(std.posix.CLOCK.REALTIME) catch |err| clockUnavailable(err);
    const seconds: i64 = ts.sec;
    const nanos: i64 = @intCast(ts.nsec);
    return seconds * std.time.ns_per_s + nanos;
}

fn systemTimestampWindows() i64 {
    const windows = std.os.windows;
    var ft: windows.FILETIME = undefined;
    if (@hasDecl(windows.kernel32, "GetSystemTimePreciseAsFileTime")) {
        windows.kernel32.GetSystemTimePreciseAsFileTime(&ft);
    } else {
        windows.kernel32.GetSystemTimeAsFileTime(&ft);
    }

    const ticks = (@as(u64, ft.dwHighDateTime) << 32) | ft.dwLowDateTime;
    const epoch_offset: u64 = 116444736000000000; // 100ns between 1601-01-01 and 1970-01-01
    if (ticks < epoch_offset) std.debug.panic("ztime: system clock before Unix epoch", .{});
    const unix_ticks = ticks - epoch_offset;
    const unix_ns = unix_ticks * 100;
    return @intCast(unix_ns);
}

fn clockUnavailable(err: anyerror) noreturn {
    std.debug.panic("ztime: system clock unavailable ({s})", .{@errorName(err)});
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

test "integration: timezone calendar business astronomy" {
    const allocator = std.testing.allocator;
    const dt = try format.parseDateTime("2024-07-03T09:30:00-0400", "%Y-%m-%dT%H:%M:%S%z", allocator);

    // Calendar projection
    const greg = calendar.Calendar.init(.gregorian);
    const date = greg.dateFromUnixTimestamp(dt.toUnixTimestamp());
    try std.testing.expectEqual(@as(i32, 2024), date.year);
    try std.testing.expectEqual(@as(u8, 7), date.month);

    // Timezone offset consistency using generated tzdb
    const tz_data = try timezone.requireTimeZone("America/New_York");
    const offset_seconds = timezone.getOffsetSeconds(tz_data, dt.toUnixTimestamp());
    try std.testing.expectEqual(@as(i32, -4 * 3600), offset_seconds);

    // Business calendar coordination
    const business_cal = business.BusinessCalendar.US_FEDERAL;
    const next_business = business_cal.getNextBusinessDay(dt);
    try std.testing.expect(next_business.timestamp_ns > dt.timestamp_ns);

    // Astronomy coupling
    const coords = astronomy.Coordinates{ .latitude = 40.7128, .longitude = -74.0060 };
    const solar = dt.getSolarEvents(coords);
    try std.testing.expect(solar.sunrise.timestamp_ns < solar.sunset.timestamp_ns);
    try std.testing.expect(solar.day_length.nanoseconds > 10 * std.time.ns_per_hour);
}
