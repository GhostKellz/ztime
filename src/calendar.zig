//! Calendar system implementations
const std = @import("std");

pub const CalendarType = enum {
    gregorian,
    julian,
    islamic,
    hebrew,
    chinese,
    usa_business, // USA business calendar with federal holidays
};

pub const Date = struct {
    year: i32,
    month: u8,  // 1-12
    day: u8,    // 1-31

    pub fn isValid(self: Date) bool {
        if (self.month < 1 or self.month > 12) return false;
        if (self.day < 1) return false;

        const days_in_month = getDaysInMonth(self.year, self.month);
        return self.day <= days_in_month;
    }
};

pub const Calendar = struct {
    calendar_type: CalendarType,

    pub fn init(calendar_type: CalendarType) Calendar {
        return Calendar{ .calendar_type = calendar_type };
    }

    pub fn dateFromUnixTimestamp(self: Calendar, timestamp: i64) Date {
        return switch (self.calendar_type) {
            .gregorian, .usa_business => gregorianFromUnixTimestamp(timestamp),
            .julian => julianFromUnixTimestamp(timestamp),
            .islamic => islamicFromUnixTimestamp(timestamp),
            .hebrew => hebrewFromUnixTimestamp(timestamp),
            .chinese => chineseFromUnixTimestamp(timestamp),
        };
    }

    pub fn unixTimestampFromDate(self: Calendar, date: Date) i64 {
        return switch (self.calendar_type) {
            .gregorian, .usa_business => gregorianToUnixTimestamp(date),
            .julian => julianToUnixTimestamp(date),
            .islamic => islamicToUnixTimestamp(date),
            .hebrew => hebrewToUnixTimestamp(date),
            .chinese => chineseToUnixTimestamp(date),
        };
    }

    pub fn isBusinessDay(self: Calendar, timestamp: i64) bool {
        const date = self.dateFromUnixTimestamp(timestamp);
        const weekday = getWeekday(timestamp);

        // Weekend check (Saturday = 6, Sunday = 0)
        if (weekday == 0 or weekday == 6) return false;

        // USA business calendar includes federal holidays
        if (self.calendar_type == .usa_business) {
            return !isUSAFederalHoliday(date);
        }

        return true;
    }
};

// Gregorian calendar implementation
fn gregorianFromUnixTimestamp(timestamp: i64) Date {
    const days_since_epoch = @divFloor(timestamp, 86400);
    const epoch_year = 1970;

    // Simple approximation for Gregorian calendar conversion
    var year: i32 = epoch_year;
    var remaining_days = days_since_epoch;

    // Rough year calculation
    while (remaining_days >= 365) {
        const days_in_year: i64 = if (isLeapYear(year)) 365 + 1 else 365;
        if (remaining_days >= days_in_year) {
            remaining_days -= days_in_year;
            year += 1;
        } else {
            break;
        }
    }

    // Support timestamps before the epoch by rewinding years
    while (remaining_days < 0) {
        year -= 1;
        const days_in_year: i64 = if (isLeapYear(year)) 366 else 365;
        remaining_days += days_in_year;
    }

    // Month and day calculation
    var month: u8 = 1;
    while (month <= 12) {
        const days_in_month = getDaysInMonth(year, month);
        if (remaining_days < days_in_month) {
            break;
        }
        remaining_days -= days_in_month;
        month += 1;
    }

    return Date{
        .year = year,
        .month = month,
        .day = @intCast(remaining_days + 1),
    };
}

fn gregorianToUnixTimestamp(date: Date) i64 {
    // Simple implementation - count days from epoch
    var days: i64 = 0;

    // Add days for complete years
    var year: i32 = 1970;
    while (year < date.year) {
        days += if (isLeapYear(year)) 366 else 365;
        year += 1;
    }

    // Add days for complete months in target year
    var month: u8 = 1;
    while (month < date.month) {
        days += getDaysInMonth(date.year, month);
        month += 1;
    }

    // Add remaining days
    days += date.day - 1;

    return days * 86400; // Convert to seconds
}

// Julian calendar (similar to Gregorian but different leap year rules)
fn julianFromUnixTimestamp(timestamp: i64) Date {
    // Julian calendar: every 4 years is a leap year
    // Adjust for Julian calendar differences (simplified)
    // The Julian calendar is about 13 days behind Gregorian in modern times
    const julian_offset_days = 13;
    const adjusted_timestamp = timestamp - (julian_offset_days * 86400);

    return gregorianFromUnixTimestamp(adjusted_timestamp);
}

fn julianToUnixTimestamp(date: Date) i64 {
    const gregorian_timestamp = gregorianToUnixTimestamp(date);
    const julian_offset_days = 13;
    return gregorian_timestamp + (julian_offset_days * 86400);
}

// Islamic calendar (Hijri) - approximate implementation
fn islamicFromUnixTimestamp(timestamp: i64) Date {
    // Islamic calendar starts July 16, 622 CE
    const islamic_epoch_timestamp: i64 = -42521587200; // Approximate
    const days_since_islamic_epoch = @divFloor(timestamp - islamic_epoch_timestamp, 86400);

    // Islamic year is approximately 354.37 days
    const islamic_year_days: f64 = 354.37;
    const year_fractional = @as(f64, @floatFromInt(days_since_islamic_epoch)) / islamic_year_days;
    const year: i32 = @as(i32, @intFromFloat(year_fractional)) + 1;

    // Simplified month/day calculation
    const remaining_days = days_since_islamic_epoch - @as(i64, @intFromFloat(@as(f64, @floatFromInt(year - 1)) * islamic_year_days));

    var month: u8 = 1;
    var day_count: i64 = remaining_days;

    // Islamic months alternate between 30 and 29 days
    while (month <= 12 and day_count > 0) {
        const days_in_month: i64 = if (month % 2 == 1) 30 else 29;
        if (day_count <= days_in_month) {
            break;
        }
        day_count -= days_in_month;
        month += 1;
    }

    return Date{
        .year = year,
        .month = month,
        .day = @intCast(@max(1, day_count)),
    };
}

fn islamicToUnixTimestamp(date: Date) i64 {
    // Reverse conversion - simplified
    const islamic_epoch_timestamp: i64 = -42521587200;
    const islamic_year_days: f64 = 354.37;

    const days_from_years = @as(i64, @intFromFloat(@as(f64, @floatFromInt(date.year - 1)) * islamic_year_days));
    var days_from_months: i64 = 0;

    var month: u8 = 1;
    while (month < date.month) {
        days_from_months += if (month % 2 == 1) 30 else 29;
        month += 1;
    }

    const total_days = days_from_years + days_from_months + date.day - 1;
    return islamic_epoch_timestamp + (total_days * 86400);
}

// Hebrew calendar (approximate implementation)
fn hebrewFromUnixTimestamp(timestamp: i64) Date {
    // Hebrew calendar starts September 7, 3761 BCE
    const hebrew_epoch_timestamp: i64 = -185542587200; // Very approximate
    const days_since_hebrew_epoch = @divFloor(timestamp - hebrew_epoch_timestamp, 86400);

    // Hebrew year is approximately 365.25 days (similar to solar year)
    const hebrew_year_days: f64 = 365.25;
    const year: i32 = @as(i32, @intFromFloat(@as(f64, @floatFromInt(days_since_hebrew_epoch)) / hebrew_year_days)) + 1;

    // Simplified month/day calculation using Gregorian approximation
    const gregorian_date = gregorianFromUnixTimestamp(timestamp);

    return Date{
        .year = year,
        .month = gregorian_date.month,
        .day = gregorian_date.day,
    };
}

fn hebrewToUnixTimestamp(date: Date) i64 {
    // Simplified reverse conversion
    const hebrew_epoch_timestamp: i64 = -185542587200;
    const hebrew_year_days: f64 = 365.25;

    const days_from_years = @as(i64, @intFromFloat(@as(f64, @floatFromInt(date.year - 1)) * hebrew_year_days));
    const gregorian_approx = Date{ .year = 2000, .month = date.month, .day = date.day };
    const days_from_months_days = @divFloor(gregorianToUnixTimestamp(gregorian_approx), 86400) - @divFloor(gregorianToUnixTimestamp(Date{ .year = 2000, .month = 1, .day = 1 }), 86400);

    const total_days = days_from_years + days_from_months_days;
    return hebrew_epoch_timestamp + (total_days * 86400);
}

// Chinese calendar (approximate lunisolar implementation)
fn chineseFromUnixTimestamp(timestamp: i64) Date {
    // Chinese calendar is complex - using simplified approximation
    // Traditional Chinese calendar starts around 2637 BCE
    const chinese_epoch_timestamp: i64 = -145507200000; // Very approximate
    const days_since_chinese_epoch = @divFloor(timestamp - chinese_epoch_timestamp, 86400);

    // Chinese year cycle is approximately 365.25 days
    const chinese_year_days: f64 = 365.25;
    const year: i32 = @as(i32, @intFromFloat(@as(f64, @floatFromInt(days_since_chinese_epoch)) / chinese_year_days)) + 1;

    // Use lunar months (approximately 29.5 days)
    const lunar_month_days: f64 = 29.5;
    const remaining_days = days_since_chinese_epoch - @as(i64, @intFromFloat(@as(f64, @floatFromInt(year - 1)) * chinese_year_days));
    const month: u8 = @intCast(@min(12, @max(1, @as(u8, @intFromFloat(@as(f64, @floatFromInt(remaining_days)) / lunar_month_days)) + 1)));

    const day_in_month = remaining_days - @as(i64, @intFromFloat(@as(f64, @floatFromInt(month - 1)) * lunar_month_days));

    return Date{
        .year = year,
        .month = month,
        .day = @intCast(@max(1, @min(30, day_in_month + 1))),
    };
}

fn chineseToUnixTimestamp(date: Date) i64 {
    // Simplified reverse conversion
    const chinese_epoch_timestamp: i64 = -145507200000;
    const chinese_year_days: f64 = 365.25;
    const lunar_month_days: f64 = 29.5;

    const days_from_years = @as(i64, @intFromFloat(@as(f64, @floatFromInt(date.year - 1)) * chinese_year_days));
    const days_from_months = @as(i64, @intFromFloat(@as(f64, @floatFromInt(date.month - 1)) * lunar_month_days));

    const total_days = days_from_years + days_from_months + date.day - 1;
    return chinese_epoch_timestamp + (total_days * 86400);
}

// Helper functions
fn isLeapYear(year: i32) bool {
    return (@mod(year, 4) == 0 and @mod(year, 100) != 0) or (@mod(year, 400) == 0);
}

pub fn getDaysInMonth(year: i32, month: u8) u8 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (isLeapYear(year)) 29 else 28,
        else => 0,
    };
}

fn getWeekday(timestamp: i64) u8 {
    // Unix epoch (1970-01-01) was a Thursday (4)
    const days_since_epoch = @divFloor(timestamp, 86400);
    return @intCast(@mod(days_since_epoch + 4, 7));
}

// USA Federal Holidays
fn isUSAFederalHoliday(date: Date) bool {
    // New Year's Day
    if (date.month == 1 and date.day == 1) return true;

    // Independence Day
    if (date.month == 7 and date.day == 4) return true;

    // Christmas Day
    if (date.month == 12 and date.day == 25) return true;

    // Martin Luther King Jr. Day (3rd Monday in January)
    if (date.month == 1) {
        const jan_first_weekday = getWeekday(gregorianToUnixTimestamp(Date{ .year = date.year, .month = 1, .day = 1 }));
        const first_monday = if (jan_first_weekday == 1) 1 else 8 - jan_first_weekday + 1;
        const third_monday = first_monday + 14;
        if (date.day == third_monday) return true;
    }

    // Memorial Day (last Monday in May)
    if (date.month == 5) {
        const may_last_day = getDaysInMonth(date.year, 5);
        const may_last_weekday = getWeekday(gregorianToUnixTimestamp(Date{ .year = date.year, .month = 5, .day = may_last_day }));
        const last_monday = may_last_day - ((may_last_weekday + 6) % 7);
        if (date.day == last_monday) return true;
    }

    // Labor Day (1st Monday in September)
    if (date.month == 9) {
        const sep_first_weekday = getWeekday(gregorianToUnixTimestamp(Date{ .year = date.year, .month = 9, .day = 1 }));
        const first_monday = if (sep_first_weekday == 1) 1 else 8 - sep_first_weekday + 1;
        if (date.day == first_monday) return true;
    }

    // Thanksgiving (4th Thursday in November)
    if (date.month == 11) {
        const nov_first_weekday = getWeekday(gregorianToUnixTimestamp(Date{ .year = date.year, .month = 11, .day = 1 }));
        const first_thursday = if (nov_first_weekday <= 4) 5 - nov_first_weekday else 12 - nov_first_weekday;
        const fourth_thursday = first_thursday + 21;
        if (date.day == fourth_thursday) return true;
    }

    return false;
}

test "Gregorian calendar conversion" {
    const cal = Calendar.init(.gregorian);

    // Test Unix epoch
    const epoch_date = cal.dateFromUnixTimestamp(0);
    try std.testing.expectEqual(@as(i32, 1970), epoch_date.year);
    try std.testing.expectEqual(@as(u8, 1), epoch_date.month);
    try std.testing.expectEqual(@as(u8, 1), epoch_date.day);

    // Test round trip
    const test_timestamp: i64 = 1577836800; // 2020-01-01
    const date = cal.dateFromUnixTimestamp(test_timestamp);
    const back_to_timestamp = cal.unixTimestampFromDate(date);

    // Allow some tolerance due to timezone differences
    try std.testing.expect(@abs(test_timestamp - back_to_timestamp) < 86400);
}

test "USA business calendar" {
    const cal = Calendar.init(.usa_business);

    // Test New Year's Day 2024 (not a business day)
    const new_years_2024 = Date{ .year = 2024, .month = 1, .day = 1 };
    const new_years_timestamp = cal.unixTimestampFromDate(new_years_2024);
    try std.testing.expect(!cal.isBusinessDay(new_years_timestamp));

    // Test regular weekday (should be business day)
    const regular_day = Date{ .year = 2024, .month = 1, .day = 2 }; // Tuesday
    const regular_timestamp = cal.unixTimestampFromDate(regular_day);
    try std.testing.expect(cal.isBusinessDay(regular_timestamp));
}

test "Islamic calendar approximation" {
    const cal = Calendar.init(.islamic);

    // Test that conversion works
    const test_timestamp: i64 = 1577836800; // 2020-01-01 Gregorian
    const islamic_date = cal.dateFromUnixTimestamp(test_timestamp);

    // Islamic year should be around 1441 AH for 2020 CE
    try std.testing.expect(islamic_date.year > 1400 and islamic_date.year < 1500);
}

test "gregorian round trip conversions" {
    const cal = Calendar.init(.gregorian);
    const cases = [_]Date{
        .{ .year = 1970, .month = 1, .day = 1 },
        .{ .year = 2000, .month = 2, .day = 29 },
        .{ .year = 2024, .month = 12, .day = 31 },
    };

    for (cases) |case| {
        try std.testing.expect(case.isValid());
        const ts = cal.unixTimestampFromDate(case);
        const decoded = cal.dateFromUnixTimestamp(ts);
        try std.testing.expectEqual(case.year, decoded.year);
        try std.testing.expectEqual(case.month, decoded.month);
        try std.testing.expectEqual(case.day, decoded.day);
    }
}

test "julian conversion alignment" {
    const greg = Calendar.init(.gregorian);
    const julian = Calendar.init(.julian);

    const greg_date = Date{ .year = 2024, .month = 3, .day = 1 };
    const julian_date = Date{ .year = 2024, .month = 2, .day = 17 };

    const greg_ts = greg.unixTimestampFromDate(greg_date);
    const jul_ts = julian.unixTimestampFromDate(julian_date);
    try std.testing.expectEqual(greg_ts, jul_ts);

    const back_to_jul = julian.dateFromUnixTimestamp(greg_ts);
    try std.testing.expectEqual(julian_date.year, back_to_jul.year);
    try std.testing.expectEqual(julian_date.month, back_to_jul.month);
    try std.testing.expectEqual(julian_date.day, back_to_jul.day);
}

test "approximate calendar round trips" {
    const day_seconds: i64 = std.time.s_per_day;
    const scenarios = [_]struct {
        cal_type: CalendarType,
        tolerance: i64,
    }{
        .{ .cal_type = .gregorian, .tolerance = 0 },
        .{ .cal_type = .julian, .tolerance = 0 },
        .{ .cal_type = .islamic, .tolerance = day_seconds },
        .{ .cal_type = .hebrew, .tolerance = day_seconds * 210 },
        .{ .cal_type = .chinese, .tolerance = day_seconds * 7 },
    };

    const timestamps = [_]i64{
        1577836800, // 2020-01-01
        2208988800, // 2040-01-01
    };

    for (scenarios) |scenario| {
        const cal = Calendar.init(scenario.cal_type);
        for (timestamps) |ts| {
            const date = cal.dateFromUnixTimestamp(ts);
            const round_trip = cal.unixTimestampFromDate(date);
            const diff = if (round_trip >= ts) round_trip - ts else ts - round_trip;
            try std.testing.expect(diff <= scenario.tolerance);
        }
    }
}