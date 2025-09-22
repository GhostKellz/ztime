const std = @import("std");
const ztime = @import("ztime");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ztime: Advanced Date/Time Library Demo ===\n\n", .{});

    // === BASIC OPERATIONS ===
    std.debug.print("1. Basic Operations:\n", .{});

    // Create timezone instances using IANA database
    const ny_tz = try ztime.TimeZone.fromName("America/New_York");
    const tokyo_tz = try ztime.TimeZone.fromName("Asia/Tokyo");

    // Get current time
    const now = ztime.utcNow();
    std.debug.print("   Current UTC time: {d}\n", .{now.toUnixTimestamp()});

    // Format current time
    const formatted = try now.format("%Y-%m-%d %H:%M:%S %Z", ztime.Locale.DEFAULT, allocator);
    defer allocator.free(formatted);
    std.debug.print("   Formatted: {s}\n", .{formatted});

    // === TIMEZONE OPERATIONS ===
    std.debug.print("\n2. Timezone Operations:\n", .{});

    const ny_time = now.toTimeZone(ny_tz);
    const tokyo_time = now.toTimeZone(tokyo_tz);

    const ny_formatted = try ny_time.format("%Y-%m-%d %H:%M:%S %Z", ztime.Locale.DEFAULT, allocator);
    defer allocator.free(ny_formatted);
    std.debug.print("   New York: {s}\n", .{ny_formatted});

    const tokyo_formatted = try tokyo_time.format("%Y-%m-%d %H:%M:%S %Z", ztime.Locale.DEFAULT, allocator);
    defer allocator.free(tokyo_formatted);
    std.debug.print("   Tokyo: {s}\n", .{tokyo_formatted});

    std.debug.print("   NY DST?: {}\n", .{ny_tz.isDST(now)});

    // === CALENDAR SYSTEMS ===
    std.debug.print("\n3. Calendar Systems:\n", .{});

    const gregorian_date = now.toDate(.gregorian);
    const islamic_date = now.toDate(.islamic);
    const hebrew_date = now.toDate(.hebrew);
    const chinese_date = now.toDate(.chinese);

    std.debug.print("   Gregorian: {d}-{d:0>2}-{d:0>2}\n", .{ gregorian_date.year, gregorian_date.month, gregorian_date.day });
    std.debug.print("   Islamic (Hijri): {d}-{d:0>2}-{d:0>2}\n", .{ islamic_date.year, islamic_date.month, islamic_date.day });
    std.debug.print("   Hebrew: {d}-{d:0>2}-{d:0>2}\n", .{ hebrew_date.year, hebrew_date.month, hebrew_date.day });
    std.debug.print("   Chinese: {d}-{d:0>2}-{d:0>2}\n", .{ chinese_date.year, chinese_date.month, chinese_date.day });

    // === BUSINESS DAY CALCULATIONS ===
    std.debug.print("\n4. Business Day Operations:\n", .{});

    std.debug.print("   Is today a business day?: {}\n", .{now.isBusinessDay()});

    const holiday_name = now.isHoliday();
    if (holiday_name) |name| {
        std.debug.print("   Today is a holiday: {s}\n", .{name});
    } else {
        std.debug.print("   Today is not a US federal holiday\n", .{});
    }

    const next_business_day = now.addBusinessDays(1);
    const next_bday_formatted = try next_business_day.format("%Y-%m-%d", ztime.Locale.DEFAULT, allocator);
    defer allocator.free(next_bday_formatted);
    std.debug.print("   Next business day: {s}\n", .{next_bday_formatted});

    // NYSE calendar
    const nyse_cal = ztime.business.BusinessCalendar.NYSE;
    const next_trading_day = nyse_cal.addBusinessDays(now, 1);
    const next_trading_formatted = try next_trading_day.format("%Y-%m-%d", ztime.Locale.DEFAULT, allocator);
    defer allocator.free(next_trading_formatted);
    std.debug.print("   Next NYSE trading day: {s}\n", .{next_trading_formatted});

    // === ASTRONOMICAL CALCULATIONS ===
    std.debug.print("\n5. Astronomical Calculations:\n", .{});

    // New York City coordinates
    const nyc_coords = ztime.astronomy.Coordinates{
        .latitude = 40.7128,
        .longitude = -74.0060,
    };

    const solar_events = now.getSolarEvents(nyc_coords);
    const sunrise_formatted = try solar_events.sunrise.format("%H:%M", ztime.Locale.DEFAULT, allocator);
    defer allocator.free(sunrise_formatted);
    const sunset_formatted = try solar_events.sunset.format("%H:%M", ztime.Locale.DEFAULT, allocator);
    defer allocator.free(sunset_formatted);

    std.debug.print("   NYC Sunrise: {s}\n", .{sunrise_formatted});
    std.debug.print("   NYC Sunset: {s}\n", .{sunset_formatted});
    std.debug.print("   Day length: {d:.1} hours\n", .{solar_events.day_length.toHours()});

    const solar_elevation = now.getSolarElevation(nyc_coords);
    const solar_azimuth = now.getSolarAzimuth(nyc_coords);
    std.debug.print("   Solar elevation: {d:.1}°\n", .{solar_elevation});
    std.debug.print("   Solar azimuth: {d:.1}°\n", .{solar_azimuth});

    // === LUNAR CALCULATIONS ===
    std.debug.print("\n6. Lunar Phase Information:\n", .{});

    const lunar_phase = now.getLunarPhase();
    const phase_name = switch (lunar_phase.phase) {
        .new_moon => "New Moon",
        .waxing_crescent => "Waxing Crescent",
        .first_quarter => "First Quarter",
        .waxing_gibbous => "Waxing Gibbous",
        .full_moon => "Full Moon",
        .waning_gibbous => "Waning Gibbous",
        .last_quarter => "Last Quarter",
        .waning_crescent => "Waning Crescent",
    };

    std.debug.print("   Current phase: {s}\n", .{phase_name});
    std.debug.print("   Illumination: {d:.1}%\n", .{lunar_phase.illumination * 100});
    std.debug.print("   Age: {d:.1} days\n", .{lunar_phase.age_days});

    // === MULTILINGUAL FORMATTING ===
    std.debug.print("\n7. Multilingual Formatting:\n", .{});

    const en_formatted = try now.format("%A, %B %d, %Y", ztime.Locale.EN_US, allocator);
    defer allocator.free(en_formatted);
    std.debug.print("   English: {s}\n", .{en_formatted});

    const de_formatted = try now.format("%A, %d. %B %Y", ztime.Locale.DE_DE, allocator);
    defer allocator.free(de_formatted);
    std.debug.print("   German: {s}\n", .{de_formatted});

    const fr_formatted = try now.format("%A %d %B %Y", ztime.Locale.FR_FR, allocator);
    defer allocator.free(fr_formatted);
    std.debug.print("   French: {s}\n", .{fr_formatted});

    // === DURATION CALCULATIONS ===
    std.debug.print("\n8. Duration Operations:\n", .{});

    const one_week = ztime.Duration.fromDays(7);
    const one_day = ztime.Duration.fromHours(24);
    const total_duration = one_week.add(one_day);

    std.debug.print("   One week + one day = {d:.1} days\n", .{total_duration.toDays()});

    const future_time = now.addDuration(total_duration);
    const duration_between = future_time.durationBetween(now);
    std.debug.print("   Duration between now and future: {d:.1} hours\n", .{duration_between.toHours()});

    // === PARSING DEMO ===
    std.debug.print("\n9. Parsing Examples:\n", .{});

    const iso_string = "2024-12-25T12:00:00Z";
    const parsed_dt = ztime.DateTime.parse(iso_string, "%Y-%m-%dT%H:%M:%SZ", allocator) catch |err| {
        std.debug.print("   Parse error: {}\n", .{err});
        return;
    };

    const parsed_formatted = try parsed_dt.format("%A, %B %d, %Y at %H:%M", ztime.Locale.DEFAULT, allocator);
    defer allocator.free(parsed_formatted);
    std.debug.print("   Parsed '{s}' as: {s}\n", .{ iso_string, parsed_formatted });

    std.debug.print("\n=== ztime Library Demo Complete! ===\n", .{});
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
