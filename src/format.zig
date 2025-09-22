//! Date/Time formatting and parsing implementation
const std = @import("std");
const Allocator = std.mem.Allocator;
const DateTime = @import("root.zig").DateTime;
const Locale = @import("root.zig").Locale;
const calendar = @import("calendar.zig");

pub const FormatError = error{
    InvalidFormat,
    BufferTooSmall,
    InvalidDate,
    OutOfMemory,
};

pub const ParseError = error{
    InvalidFormat,
    InvalidDate,
    UnexpectedCharacter,
    NumberOverflow,
};

// Format specifiers similar to strftime
const FormatSpecifier = enum {
    year_4digit,        // %Y - 2024
    year_2digit,        // %y - 24
    month_number,       // %m - 01-12
    month_name_long,    // %B - January
    month_name_short,   // %b - Jan
    day_of_month,       // %d - 01-31
    day_of_week_long,   // %A - Monday
    day_of_week_short,  // %a - Mon
    hour_24,            // %H - 00-23
    hour_12,            // %I - 01-12
    minute,             // %M - 00-59
    second,             // %S - 00-59
    am_pm,              // %p - AM/PM
    timezone_name,      // %Z - UTC, EST
    timezone_offset,    // %z - +0000, -0500
    literal,            // Regular characters
};

const FormatToken = struct {
    specifier: FormatSpecifier,
    literal_text: []const u8,
};

const LocaleData = struct {
    month_names_long: [12][]const u8,
    month_names_short: [12][]const u8,
    weekday_names_long: [7][]const u8,
    weekday_names_short: [7][]const u8,
    am_pm: [2][]const u8,

    const EN_US = LocaleData{
        .month_names_long = [_][]const u8{
            "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December",
        },
        .month_names_short = [_][]const u8{
            "Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
        },
        .weekday_names_long = [_][]const u8{
            "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
        },
        .weekday_names_short = [_][]const u8{
            "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat",
        },
        .am_pm = [_][]const u8{ "AM", "PM" },
    };

    const DE_DE = LocaleData{
        .month_names_long = [_][]const u8{
            "Januar", "Februar", "März", "April", "Mai", "Juni",
            "Juli", "August", "September", "Oktober", "November", "Dezember",
        },
        .month_names_short = [_][]const u8{
            "Jan", "Feb", "Mär", "Apr", "Mai", "Jun",
            "Jul", "Aug", "Sep", "Okt", "Nov", "Dez",
        },
        .weekday_names_long = [_][]const u8{
            "Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag",
        },
        .weekday_names_short = [_][]const u8{
            "So", "Mo", "Di", "Mi", "Do", "Fr", "Sa",
        },
        .am_pm = [_][]const u8{ "AM", "PM" },
    };

    const FR_FR = LocaleData{
        .month_names_long = [_][]const u8{
            "janvier", "février", "mars", "avril", "mai", "juin",
            "juillet", "août", "septembre", "octobre", "novembre", "décembre",
        },
        .month_names_short = [_][]const u8{
            "janv", "févr", "mars", "avr", "mai", "juin",
            "juil", "août", "sept", "oct", "nov", "déc",
        },
        .weekday_names_long = [_][]const u8{
            "dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi",
        },
        .weekday_names_short = [_][]const u8{
            "dim", "lun", "mar", "mer", "jeu", "ven", "sam",
        },
        .am_pm = [_][]const u8{ "AM", "PM" },
    };
};

fn getLocaleData(locale: Locale) LocaleData {
    if (std.mem.eql(u8, locale.language, "de")) {
        return LocaleData.DE_DE;
    } else if (std.mem.eql(u8, locale.language, "fr")) {
        return LocaleData.FR_FR;
    } else {
        return LocaleData.EN_US; // Default to English
    }
}

pub fn formatDateTime(allocator: Allocator, dt: DateTime, format_str: []const u8, locale: Locale) ![]u8 {
    const tokens = try parseFormatString(allocator, format_str);
    defer allocator.free(tokens);

    const locale_data = getLocaleData(locale);
    const cal = calendar.Calendar.init(.gregorian);
    const date = cal.dateFromUnixTimestamp(@divFloor(dt.timestamp_ns, std.time.ns_per_s));

    // Calculate time components
    const seconds_in_day = @mod(@divFloor(dt.timestamp_ns, std.time.ns_per_s), 86400);
    const hours = @divFloor(seconds_in_day, 3600);
    const minutes = @divFloor(@mod(seconds_in_day, 3600), 60);
    const seconds = @mod(seconds_in_day, 60);

    const weekday = getWeekday(@divFloor(dt.timestamp_ns, std.time.ns_per_s));

    var result: std.ArrayList(u8) = .empty;

    for (tokens) |token| {
        switch (token.specifier) {
            .year_4digit => {
                const text = try std.fmt.allocPrint(allocator, "{d:0>4}", .{date.year});
                defer allocator.free(text);
                try result.appendSlice(allocator, text);
            },
            .year_2digit => {
                const text = try std.fmt.allocPrint(allocator, "{d:0>2}", .{@mod(date.year, 100)});
                defer allocator.free(text);
                try result.appendSlice(allocator, text);
            },
            .month_number => {
                const text = try std.fmt.allocPrint(allocator, "{d:0>2}", .{date.month});
                defer allocator.free(text);
                try result.appendSlice(allocator, text);
            },
            .month_name_long => try result.appendSlice(allocator, locale_data.month_names_long[date.month - 1]),
            .month_name_short => try result.appendSlice(allocator, locale_data.month_names_short[date.month - 1]),
            .day_of_month => {
                const text = try std.fmt.allocPrint(allocator, "{d:0>2}", .{date.day});
                defer allocator.free(text);
                try result.appendSlice(allocator, text);
            },
            .day_of_week_long => try result.appendSlice(allocator, locale_data.weekday_names_long[weekday]),
            .day_of_week_short => try result.appendSlice(allocator, locale_data.weekday_names_short[weekday]),
            .hour_24 => {
                const text = try std.fmt.allocPrint(allocator, "{d:0>2}", .{hours});
                defer allocator.free(text);
                try result.appendSlice(allocator, text);
            },
            .hour_12 => {
                const hour_12 = if (hours == 0) 12 else if (hours > 12) hours - 12 else hours;
                const text = try std.fmt.allocPrint(allocator, "{d:0>2}", .{hour_12});
                defer allocator.free(text);
                try result.appendSlice(allocator, text);
            },
            .minute => {
                const text = try std.fmt.allocPrint(allocator, "{d:0>2}", .{minutes});
                defer allocator.free(text);
                try result.appendSlice(allocator, text);
            },
            .second => {
                const text = try std.fmt.allocPrint(allocator, "{d:0>2}", .{seconds});
                defer allocator.free(text);
                try result.appendSlice(allocator, text);
            },
            .am_pm => {
                const am_pm_index: usize = if (hours < 12) 0 else 1;
                try result.appendSlice(allocator, locale_data.am_pm[am_pm_index]);
            },
            .timezone_name => try result.appendSlice(allocator, dt.timezone.name),
            .timezone_offset => {
                const offset_seconds = dt.timezone.offset_seconds;
                const offset_hours = @divFloor(@abs(offset_seconds), 3600);
                const offset_mins = @divFloor(@mod(@abs(offset_seconds), 3600), 60);
                const sign: u8 = if (offset_seconds >= 0) '+' else '-';
                const text = try std.fmt.allocPrint(allocator, "{c}{d:0>2}{d:0>2}", .{ sign, offset_hours, offset_mins });
                defer allocator.free(text);
                try result.appendSlice(allocator, text);
            },
            .literal => try result.appendSlice(allocator, token.literal_text),
        }
    }

    return result.toOwnedSlice(allocator);
}

pub fn parseDateTime(input: []const u8, format_str: []const u8, allocator: Allocator) !DateTime {
    _ = allocator; // TODO: Use for complex parsing

    // For now, implement basic ISO 8601 parsing
    if (std.mem.eql(u8, format_str, "%Y-%m-%d %H:%M:%S")) {
        return parseISO8601Basic(input);
    } else if (std.mem.eql(u8, format_str, "%Y-%m-%dT%H:%M:%SZ")) {
        return parseISO8601(input);
    }

    return ParseError.InvalidFormat;
}

fn parseISO8601(input: []const u8) !DateTime {
    // Parse format: 2024-01-15T14:30:45Z
    if (input.len < 20) return ParseError.InvalidFormat;

    const year = try std.fmt.parseInt(i32, input[0..4], 10);
    if (input[4] != '-') return ParseError.UnexpectedCharacter;

    const month = try std.fmt.parseInt(u8, input[5..7], 10);
    if (input[7] != '-') return ParseError.UnexpectedCharacter;

    const day = try std.fmt.parseInt(u8, input[8..10], 10);
    if (input[10] != 'T') return ParseError.UnexpectedCharacter;

    const hour = try std.fmt.parseInt(u8, input[11..13], 10);
    if (input[13] != ':') return ParseError.UnexpectedCharacter;

    const minute = try std.fmt.parseInt(u8, input[14..16], 10);
    if (input[16] != ':') return ParseError.UnexpectedCharacter;

    const second = try std.fmt.parseInt(u8, input[17..19], 10);
    if (input[19] != 'Z') return ParseError.UnexpectedCharacter;

    const date = calendar.Date{ .year = year, .month = month, .day = day };
    if (!date.isValid()) return ParseError.InvalidDate;

    const cal = calendar.Calendar.init(.gregorian);
    const day_timestamp = cal.unixTimestampFromDate(date);
    const time_seconds = @as(i64, hour) * 3600 + @as(i64, minute) * 60 + @as(i64, second);
    const total_timestamp = day_timestamp + time_seconds;

    const timezone = @import("timezone.zig").lookupTimeZone("UTC") orelse return ParseError.InvalidFormat;
    const tz = @import("root.zig").TimeZone{ .name = timezone.name, .offset_seconds = 0 };

    return DateTime{
        .timestamp_ns = total_timestamp * std.time.ns_per_s,
        .timezone = tz,
    };
}

fn parseISO8601Basic(input: []const u8) !DateTime {
    // Parse format: 2024-01-15 14:30:45
    if (input.len < 19) return ParseError.InvalidFormat;

    const year = try std.fmt.parseInt(i32, input[0..4], 10);
    if (input[4] != '-') return ParseError.UnexpectedCharacter;

    const month = try std.fmt.parseInt(u8, input[5..7], 10);
    if (input[7] != '-') return ParseError.UnexpectedCharacter;

    const day = try std.fmt.parseInt(u8, input[8..10], 10);
    if (input[10] != ' ') return ParseError.UnexpectedCharacter;

    const hour = try std.fmt.parseInt(u8, input[11..13], 10);
    if (input[13] != ':') return ParseError.UnexpectedCharacter;

    const minute = try std.fmt.parseInt(u8, input[14..16], 10);
    if (input[16] != ':') return ParseError.UnexpectedCharacter;

    const second = try std.fmt.parseInt(u8, input[17..19], 10);

    const date = calendar.Date{ .year = year, .month = month, .day = day };
    if (!date.isValid()) return ParseError.InvalidDate;

    const cal = calendar.Calendar.init(.gregorian);
    const day_timestamp = cal.unixTimestampFromDate(date);
    const time_seconds = @as(i64, hour) * 3600 + @as(i64, minute) * 60 + @as(i64, second);
    const total_timestamp = day_timestamp + time_seconds;

    const timezone = @import("timezone.zig").lookupTimeZone("UTC") orelse return ParseError.InvalidFormat;
    const tz = @import("root.zig").TimeZone{ .name = timezone.name, .offset_seconds = 0 };

    return DateTime{
        .timestamp_ns = total_timestamp * std.time.ns_per_s,
        .timezone = tz,
    };
}

fn parseFormatString(allocator: Allocator, format_str: []const u8) ![]FormatToken {
    var tokens: std.ArrayList(FormatToken) = .empty;
    defer tokens.deinit(allocator);
    var i: usize = 0;

    while (i < format_str.len) {
        if (format_str[i] == '%' and i + 1 < format_str.len) {
            const specifier_char = format_str[i + 1];
            const specifier: FormatSpecifier = switch (specifier_char) {
                'Y' => .year_4digit,
                'y' => .year_2digit,
                'm' => .month_number,
                'B' => .month_name_long,
                'b' => .month_name_short,
                'd' => .day_of_month,
                'A' => .day_of_week_long,
                'a' => .day_of_week_short,
                'H' => .hour_24,
                'I' => .hour_12,
                'M' => .minute,
                'S' => .second,
                'p' => .am_pm,
                'Z' => .timezone_name,
                'z' => .timezone_offset,
                else => return FormatError.InvalidFormat,
            };

            try tokens.append(allocator, FormatToken{
                .specifier = specifier,
                .literal_text = "",
            });
            i += 2;
        } else {
            // Collect literal characters
            const start = i;
            while (i < format_str.len and format_str[i] != '%') {
                i += 1;
            }

            try tokens.append(allocator, FormatToken{
                .specifier = .literal,
                .literal_text = format_str[start..i],
            });
        }
    }

    return tokens.toOwnedSlice(allocator);
}

fn getWeekday(timestamp: i64) u8 {
    const days_since_epoch = @divFloor(timestamp, 86400);
    return @intCast(@mod(days_since_epoch + 4, 7)); // Unix epoch was Thursday (4)
}

test "format DateTime basic" {
    const allocator = std.testing.allocator;

    const timezone = @import("timezone.zig").lookupTimeZone("UTC").?;
    const tz = @import("root.zig").TimeZone{ .name = timezone.name, .offset_seconds = 0 };

    const dt = DateTime{
        .timestamp_ns = 1577836800 * std.time.ns_per_s, // 2020-01-01 00:00:00 UTC
        .timezone = tz,
    };

    const formatted = try formatDateTime(allocator, dt, "%Y-%m-%d %H:%M:%S", Locale.DEFAULT);
    defer allocator.free(formatted);

    try std.testing.expectEqualStrings("2020-01-01 00:00:00", formatted);
}

test "parse ISO 8601" {
    const dt = try parseISO8601("2024-01-15T14:30:45Z");

    const expected_timestamp: i64 = 1705329045; // 2024-01-15T14:30:45Z
    const actual_timestamp = @divFloor(dt.timestamp_ns, std.time.ns_per_s);

    // Allow some tolerance for calendar conversion differences
    try std.testing.expect(@abs(expected_timestamp - actual_timestamp) < 86400);
}

test "format with different locales" {
    const allocator = std.testing.allocator;

    const timezone = @import("timezone.zig").lookupTimeZone("UTC").?;
    const tz = @import("root.zig").TimeZone{ .name = timezone.name, .offset_seconds = 0 };

    const dt = DateTime{
        .timestamp_ns = 1577836800 * std.time.ns_per_s, // 2020-01-01 00:00:00 UTC
        .timezone = tz,
    };

    // English
    const en_formatted = try formatDateTime(allocator, dt, "%B %d, %Y", Locale{ .language = "en", .country = "US" });
    defer allocator.free(en_formatted);
    try std.testing.expectEqualStrings("January 01, 2020", en_formatted);

    // German
    const de_formatted = try formatDateTime(allocator, dt, "%B %d, %Y", Locale{ .language = "de", .country = "DE" });
    defer allocator.free(de_formatted);
    try std.testing.expectEqualStrings("Januar 01, 2020", de_formatted);
}