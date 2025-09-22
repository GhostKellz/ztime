//! Advanced business day calculations and holiday handling
const std = @import("std");
const DateTime = @import("root.zig").DateTime;
const Duration = @import("root.zig").Duration;
const calendar = @import("calendar.zig");

pub const HolidayType = enum {
    fixed,          // Same date every year (e.g., Christmas)
    relative,       // Relative to other dates (e.g., Easter)
    weekday_based,  // Nth weekday of month (e.g., Labor Day)
    floating,       // Custom calculation needed
};

pub const Holiday = struct {
    name: []const u8,
    holiday_type: HolidayType,
    month: ?u8 = null,
    day: ?u8 = null,
    weekday: ?u8 = null,        // 0=Sunday, 1=Monday, etc.
    week_number: ?i8 = null,    // 1=first, -1=last, etc.
    calculate_fn: ?*const fn (year: i32) calendar.Date = null,

    pub fn getDateForYear(self: Holiday, year: i32) ?calendar.Date {
        return switch (self.holiday_type) {
            .fixed => if (self.month != null and self.day != null)
                calendar.Date{ .year = year, .month = self.month.?, .day = self.day.? }
            else
                null,
            .weekday_based => calculateWeekdayBasedHoliday(self, year),
            .relative, .floating => if (self.calculate_fn != null) self.calculate_fn.?(year) else null,
        };
    }
};

// US Federal Holidays
pub const US_FEDERAL_HOLIDAYS = [_]Holiday{
    Holiday{ .name = "New Year's Day", .holiday_type = .fixed, .month = 1, .day = 1 },
    Holiday{ .name = "Martin Luther King Jr. Day", .holiday_type = .weekday_based, .month = 1, .weekday = 1, .week_number = 3 },
    Holiday{ .name = "Presidents' Day", .holiday_type = .weekday_based, .month = 2, .weekday = 1, .week_number = 3 },
    Holiday{ .name = "Memorial Day", .holiday_type = .weekday_based, .month = 5, .weekday = 1, .week_number = -1 },
    Holiday{ .name = "Independence Day", .holiday_type = .fixed, .month = 7, .day = 4 },
    Holiday{ .name = "Labor Day", .holiday_type = .weekday_based, .month = 9, .weekday = 1, .week_number = 1 },
    Holiday{ .name = "Columbus Day", .holiday_type = .weekday_based, .month = 10, .weekday = 1, .week_number = 2 },
    Holiday{ .name = "Veterans Day", .holiday_type = .fixed, .month = 11, .day = 11 },
    Holiday{ .name = "Thanksgiving", .holiday_type = .weekday_based, .month = 11, .weekday = 4, .week_number = 4 },
    Holiday{ .name = "Christmas Day", .holiday_type = .fixed, .month = 12, .day = 25 },
    Holiday{ .name = "Good Friday", .holiday_type = .relative, .calculate_fn = calculateGoodFriday },
    Holiday{ .name = "Easter Sunday", .holiday_type = .relative, .calculate_fn = calculateEaster },
};

// Financial Markets Holidays (NYSE)
pub const NYSE_HOLIDAYS = [_]Holiday{
    Holiday{ .name = "New Year's Day", .holiday_type = .fixed, .month = 1, .day = 1 },
    Holiday{ .name = "Martin Luther King Jr. Day", .holiday_type = .weekday_based, .month = 1, .weekday = 1, .week_number = 3 },
    Holiday{ .name = "Presidents' Day", .holiday_type = .weekday_based, .month = 2, .weekday = 1, .week_number = 3 },
    Holiday{ .name = "Good Friday", .holiday_type = .relative, .calculate_fn = calculateGoodFriday },
    Holiday{ .name = "Memorial Day", .holiday_type = .weekday_based, .month = 5, .weekday = 1, .week_number = -1 },
    Holiday{ .name = "Independence Day", .holiday_type = .fixed, .month = 7, .day = 4 },
    Holiday{ .name = "Labor Day", .holiday_type = .weekday_based, .month = 9, .weekday = 1, .week_number = 1 },
    Holiday{ .name = "Thanksgiving", .holiday_type = .weekday_based, .month = 11, .weekday = 4, .week_number = 4 },
    Holiday{ .name = "Christmas Day", .holiday_type = .fixed, .month = 12, .day = 25 },
};

pub const BusinessCalendar = struct {
    holidays: []const Holiday,
    weekend_days: []const u8, // 0=Sunday, 6=Saturday

    pub const US_FEDERAL = BusinessCalendar{
        .holidays = &US_FEDERAL_HOLIDAYS,
        .weekend_days = &[_]u8{ 0, 6 }, // Saturday and Sunday
    };

    pub const NYSE = BusinessCalendar{
        .holidays = &NYSE_HOLIDAYS,
        .weekend_days = &[_]u8{ 0, 6 },
    };

    pub const STANDARD_WEEKDAYS = BusinessCalendar{
        .holidays = &[_]Holiday{},
        .weekend_days = &[_]u8{ 0, 6 },
    };

    pub fn isBusinessDay(self: BusinessCalendar, dt: DateTime) bool {
        const timestamp_seconds = @divFloor(dt.timestamp_ns, std.time.ns_per_s);
        const cal = calendar.Calendar.init(.gregorian);
        const date = cal.dateFromUnixTimestamp(timestamp_seconds);

        // Check if it's a weekend
        const weekday = getWeekday(timestamp_seconds);
        for (self.weekend_days) |weekend_day| {
            if (weekday == weekend_day) return false;
        }

        // Check if it's a holiday
        for (self.holidays) |holiday| {
            if (holiday.getDateForYear(date.year)) |holiday_date| {
                if (holiday_date.year == date.year and
                    holiday_date.month == date.month and
                    holiday_date.day == date.day)
                {
                    return false;
                }
            }
        }

        return true;
    }

    pub fn addBusinessDays(self: BusinessCalendar, dt: DateTime, business_days: i32) DateTime {
        var current_dt = dt;
        var remaining_days = @abs(business_days);
        const direction: i64 = if (business_days >= 0) 1 else -1;

        while (remaining_days > 0) {
            // Move to the next/previous day
            current_dt = DateTime{
                .timestamp_ns = current_dt.timestamp_ns + (direction * std.time.ns_per_day),
                .timezone = current_dt.timezone,
            };

            // Check if this is a business day
            if (self.isBusinessDay(current_dt)) {
                remaining_days -= 1;
            }
        }

        return current_dt;
    }

    pub fn getBusinessDaysBetween(self: BusinessCalendar, start_dt: DateTime, end_dt: DateTime) i32 {
        const start_ts = @divFloor(start_dt.timestamp_ns, std.time.ns_per_s);
        const end_ts = @divFloor(end_dt.timestamp_ns, std.time.ns_per_s);

        const start_day = @divFloor(start_ts, 86400);
        const end_day = @divFloor(end_ts, 86400);

        var business_days: i32 = 0;
        var current_day = start_day;

        const direction: i64 = if (end_day >= start_day) 1 else -1;
        const target_day = end_day;

        while (current_day != target_day) {
            current_day += direction;

            const current_timestamp = current_day * 86400;
            const current_dt = DateTime{
                .timestamp_ns = current_timestamp * std.time.ns_per_s,
                .timezone = start_dt.timezone,
            };

            if (self.isBusinessDay(current_dt)) {
                business_days += @intCast(direction);
            }
        }

        return business_days;
    }

    pub fn getNextBusinessDay(self: BusinessCalendar, dt: DateTime) DateTime {
        return self.addBusinessDays(dt, 1);
    }

    pub fn getPreviousBusinessDay(self: BusinessCalendar, dt: DateTime) DateTime {
        return self.addBusinessDays(dt, -1);
    }

    pub fn isHoliday(self: BusinessCalendar, dt: DateTime) ?[]const u8 {
        const timestamp_seconds = @divFloor(dt.timestamp_ns, std.time.ns_per_s);
        const cal = calendar.Calendar.init(.gregorian);
        const date = cal.dateFromUnixTimestamp(timestamp_seconds);

        for (self.holidays) |holiday| {
            if (holiday.getDateForYear(date.year)) |holiday_date| {
                if (holiday_date.year == date.year and
                    holiday_date.month == date.month and
                    holiday_date.day == date.day)
                {
                    return holiday.name;
                }
            }
        }

        return null;
    }
};

// Helper functions

fn calculateWeekdayBasedHoliday(holiday: Holiday, year: i32) ?calendar.Date {
    if (holiday.month == null or holiday.weekday == null or holiday.week_number == null) {
        return null;
    }

    const month = holiday.month.?;
    const target_weekday = holiday.weekday.?;
    const week_num = holiday.week_number.?;

    if (week_num > 0) {
        // Nth weekday from the beginning of the month
        const first_day = calendar.Date{ .year = year, .month = month, .day = 1 };
        const cal = calendar.Calendar.init(.gregorian);
        const first_day_timestamp = cal.unixTimestampFromDate(first_day);
        const first_weekday = getWeekday(first_day_timestamp);

        // Calculate days to add to get to the first occurrence of target_weekday
        var days_to_first = @as(i32, target_weekday) - @as(i32, first_weekday);
        if (days_to_first < 0) days_to_first += 7;

        // Add weeks to get to the Nth occurrence
        const target_day = 1 + days_to_first + (week_num - 1) * 7;

        // Check if the day exists in the month
        const days_in_month = calendar.getDaysInMonth(year, month);
        if (target_day <= days_in_month) {
            return calendar.Date{ .year = year, .month = month, .day = @intCast(target_day) };
        }
    } else if (week_num < 0) {
        // Nth weekday from the end of the month
        const days_in_month = calendar.getDaysInMonth(year, month);
        const last_day = calendar.Date{ .year = year, .month = month, .day = days_in_month };
        const cal = calendar.Calendar.init(.gregorian);
        const last_day_timestamp = cal.unixTimestampFromDate(last_day);
        const last_weekday = getWeekday(last_day_timestamp);

        // Calculate days to subtract to get to the last occurrence of target_weekday
        var days_to_last = @as(i32, last_weekday) - @as(i32, target_weekday);
        if (days_to_last < 0) days_to_last += 7;

        // Subtract weeks to get to the Nth occurrence from the end
        const target_day = @as(i32, days_in_month) - days_to_last - (@abs(week_num) - 1) * 7;

        if (target_day >= 1) {
            return calendar.Date{ .year = year, .month = month, .day = @intCast(target_day) };
        }
    }

    return null;
}

fn calculateEaster(year: i32) calendar.Date {
    // Anonymous Gregorian algorithm for Easter
    const a = @mod(year, 19);
    const b = @divFloor(year, 100);
    const c = @mod(year, 100);
    const d = @divFloor(b, 4);
    const e = @mod(b, 4);
    const f = @divFloor(b + 8, 25);
    const g = @divFloor(b - f + 1, 3);
    const h = @mod(19 * a + b - d - g + 15, 30);
    const i = @divFloor(c, 4);
    const k = @mod(c, 4);
    const l = @mod(32 + 2 * e + 2 * i - h - k, 7);
    const m = @divFloor(a + 11 * h + 22 * l, 451);
    const n = @divFloor(h + l - 7 * m + 114, 31);
    const p = @mod(h + l - 7 * m + 114, 31);

    return calendar.Date{
        .year = year,
        .month = @intCast(n),
        .day = @intCast(p + 1),
    };
}

fn calculateGoodFriday(year: i32) calendar.Date {
    const easter = calculateEaster(year);
    const cal = calendar.Calendar.init(.gregorian);
    const easter_timestamp = cal.unixTimestampFromDate(easter);

    // Good Friday is 2 days before Easter
    const good_friday_timestamp = easter_timestamp - (2 * 86400);
    return cal.dateFromUnixTimestamp(good_friday_timestamp);
}

fn getWeekday(timestamp: i64) u8 {
    const days_since_epoch = @divFloor(timestamp, 86400);
    return @intCast(@mod(days_since_epoch + 4, 7)); // Unix epoch was Thursday (4)
}

test "US Federal holidays" {
    const cal = BusinessCalendar.US_FEDERAL;

    // Test Christmas 2024
    const timezone = @import("timezone.zig").lookupTimeZone("UTC").?;
    const tz = @import("root.zig").TimeZone{ .name = timezone.name, .offset_seconds = 0 };

    const christmas_2024 = DateTime{
        .timestamp_ns = 1735084800 * std.time.ns_per_s, // 2024-12-25 00:00:00 UTC
        .timezone = tz,
    };

    try std.testing.expect(!cal.isBusinessDay(christmas_2024));

    const holiday_name = cal.isHoliday(christmas_2024);
    try std.testing.expect(holiday_name != null);
    try std.testing.expectEqualStrings("Christmas Day", holiday_name.?);
}

test "business day calculations" {
    const cal = BusinessCalendar.STANDARD_WEEKDAYS;

    const timezone = @import("timezone.zig").lookupTimeZone("UTC").?;
    const tz = @import("root.zig").TimeZone{ .name = timezone.name, .offset_seconds = 0 };

    // Start on Friday 2024-01-05
    const friday = DateTime{
        .timestamp_ns = 1704412800 * std.time.ns_per_s, // 2024-01-05 00:00:00 UTC
        .timezone = tz,
    };

    // Add 1 business day should give us Monday
    const next_business_day = cal.addBusinessDays(friday, 1);
    const next_day_timestamp = @divFloor(next_business_day.timestamp_ns, std.time.ns_per_s);
    const next_weekday = getWeekday(next_day_timestamp);

    try std.testing.expectEqual(@as(u8, 1), next_weekday); // Monday
}

test "Easter calculation" {
    // Test known Easter dates
    const easter_2024 = calculateEaster(2024);
    try std.testing.expectEqual(@as(i32, 2024), easter_2024.year);
    try std.testing.expectEqual(@as(u8, 3), easter_2024.month);
    try std.testing.expectEqual(@as(u8, 31), easter_2024.day);

    const easter_2025 = calculateEaster(2025);
    try std.testing.expectEqual(@as(i32, 2025), easter_2025.year);
    try std.testing.expectEqual(@as(u8, 4), easter_2025.month);
    try std.testing.expectEqual(@as(u8, 20), easter_2025.day);
}

test "weekday-based holiday calculation" {
    // Test Labor Day 2024 (first Monday in September)
    const labor_day_holiday = Holiday{
        .name = "Labor Day",
        .holiday_type = .weekday_based,
        .month = 9,
        .weekday = 1, // Monday
        .week_number = 1, // First
    };

    const labor_day_2024 = labor_day_holiday.getDateForYear(2024).?;
    try std.testing.expectEqual(@as(i32, 2024), labor_day_2024.year);
    try std.testing.expectEqual(@as(u8, 9), labor_day_2024.month);
    try std.testing.expectEqual(@as(u8, 2), labor_day_2024.day); // September 2, 2024 was first Monday
}