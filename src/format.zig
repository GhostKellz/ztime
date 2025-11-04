//! Date/Time formatting and parsing implementation
const std = @import("std");
const Allocator = std.mem.Allocator;
const DateTime = @import("root.zig").DateTime;
const Locale = @import("root.zig").Locale;
const TimeZone = @import("root.zig").TimeZone;
const calendar = @import("calendar.zig");
const timezone = @import("timezone.zig");
const errors = @import("errors.zig");

const ascii = std.ascii;
const math = std.math;

pub const FormatError = errors.FormatError;
pub const ParseError = errors.ParseError;

// Format specifiers similar to strftime
const FormatSpecifier = enum {
    year_4digit, // %Y - 2024
    year_2digit, // %y - 24
    month_number, // %m - 01-12
    month_name_long, // %B - January
    month_name_short, // %b - Jan
    day_of_month, // %d - 01-31
    day_of_week_long, // %A - Monday
    day_of_week_short, // %a - Mon
    hour_24, // %H - 00-23
    hour_12, // %I - 01-12
    minute, // %M - 00-59
    second, // %S - 00-59
    am_pm, // %p - AM/PM
    timezone_name, // %Z - UTC, EST
    timezone_offset, // %z - +0000, -0500
    literal, // Regular characters
    fractional_second, // %f - fractional seconds up to nanoseconds
};

const FormatToken = struct {
    specifier: FormatSpecifier,
    literal_text: []const u8,
};

fn appendPaddedInt(list: *std.ArrayList(u8), allocator: Allocator, value: anytype, width: usize) !void {
    const info = @typeInfo(@TypeOf(value));
    const signed_value: i64 = switch (info) {
        .int => |int_info| blk: {
            if (int_info.signedness == .signed) {
                const maybe_signed = math.cast(i64, value);
                if (maybe_signed) |signed| {
                    break :blk signed;
                } else {
                    std.debug.panic("integer overflow converting to i64", .{});
                }
            }
            const unsigned = blk_unsigned: {
                const maybe_unsigned = math.cast(u64, value);
                if (maybe_unsigned) |u| {
                    break :blk_unsigned u;
                }
                std.debug.panic("integer overflow converting to u64", .{});
            };
            break :blk @as(i64, @intCast(unsigned));
        },
        .comptime_int => blk: {
            const tmp: comptime_int = value;
            break :blk @as(i64, tmp);
        },
        else => @compileError("appendPaddedInt requires an integer value"),
    };

    var magnitude: u64 = if (signed_value >= 0) @as(u64, @intCast(signed_value)) else blk_abs: {
        const shifted = -(signed_value + 1);
        const base = @as(u64, @intCast(shifted));
        break :blk_abs base + 1;
    };
    var buffer: [32]u8 = undefined;
    var index: usize = buffer.len;

    if (magnitude == 0) {
        index -= 1;
        buffer[index] = '0';
    } else {
        while (magnitude > 0) {
            index -= 1;
            const digit: u8 = @intCast(magnitude % 10);
            buffer[index] = '0' + digit;
            magnitude /= 10;
        }
    }

    while (buffer.len - index < width) {
        index -= 1;
        buffer[index] = '0';
    }

    if (signed_value < 0) {
        index -= 1;
        buffer[index] = '-';
    }

    try list.appendSlice(allocator, buffer[index..]);
}

const LocaleData = struct {
    month_names_long: [12][]const u8,
    month_names_short: [12][]const u8,
    weekday_names_long: [7][]const u8,
    weekday_names_short: [7][]const u8,
    am_pm: [2][]const u8,

    const EN_US = LocaleData{
        .month_names_long = [_][]const u8{
            "January", "February", "March",     "April",   "May",      "June",
            "July",    "August",   "September", "October", "November", "December",
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
            "Januar", "Februar", "März",     "April",   "Mai",      "Juni",
            "Juli",   "August",  "September", "Oktober", "November", "Dezember",
        },
        .month_names_short = [_][]const u8{
            "Jan", "Feb", "Mär", "Apr", "Mai", "Jun",
            "Jul", "Aug", "Sep",  "Okt", "Nov", "Dez",
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
            "janvier", "février", "mars",      "avril",   "mai",      "juin",
            "juillet", "août",    "septembre", "octobre", "novembre", "décembre",
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
                try appendPaddedInt(&result, allocator, date.year, 4);
            },
            .year_2digit => {
                try appendPaddedInt(&result, allocator, @mod(date.year, 100), 2);
            },
            .month_number => {
                try appendPaddedInt(&result, allocator, date.month, 2);
            },
            .month_name_long => try result.appendSlice(allocator, locale_data.month_names_long[date.month - 1]),
            .month_name_short => try result.appendSlice(allocator, locale_data.month_names_short[date.month - 1]),
            .day_of_month => {
                try appendPaddedInt(&result, allocator, date.day, 2);
            },
            .day_of_week_long => try result.appendSlice(allocator, locale_data.weekday_names_long[weekday]),
            .day_of_week_short => try result.appendSlice(allocator, locale_data.weekday_names_short[weekday]),
            .hour_24 => {
                try appendPaddedInt(&result, allocator, hours, 2);
            },
            .hour_12 => {
                const hour_12 = if (hours == 0) 12 else if (hours > 12) hours - 12 else hours;
                try appendPaddedInt(&result, allocator, hour_12, 2);
            },
            .minute => {
                try appendPaddedInt(&result, allocator, minutes, 2);
            },
            .second => {
                try appendPaddedInt(&result, allocator, seconds, 2);
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
            .fractional_second => {
                var fraction_ns = @mod(dt.timestamp_ns, std.time.ns_per_s);
                if (fraction_ns < 0) {
                    fraction_ns += std.time.ns_per_s;
                }
                const text = try std.fmt.allocPrint(allocator, "{d:0>9}", .{fraction_ns});
                defer allocator.free(text);
                try result.appendSlice(allocator, text);
            },
            .literal => try result.appendSlice(allocator, token.literal_text),
        }
    }

    return result.toOwnedSlice(allocator);
}

pub fn parseDateTime(input: []const u8, format_str: []const u8, allocator: Allocator) !DateTime {
    return parseDateTimeLocale(input, format_str, Locale.DEFAULT, allocator);
}

pub fn parseDateTimeLocale(input: []const u8, format_str: []const u8, locale: Locale, allocator: Allocator) !DateTime {
    const tokens = try parseFormatString(allocator, format_str);
    defer allocator.free(tokens);

    const locale_data = getLocaleData(locale);

    var index: usize = 0;
    var components = Components{};

    for (tokens) |token| {
        switch (token.specifier) {
            .literal => {
                const literal = token.literal_text;
                if (literal.len == 0) continue;
                if (index + literal.len > input.len) return ParseError.UnexpectedCharacter;
                if (!std.mem.eql(u8, input[index .. index + literal.len], literal)) {
                    return ParseError.UnexpectedCharacter;
                }
                index += literal.len;
            },
            .year_4digit => {
                if (components.year != null) return ParseError.InvalidFormat;
                components.year = try parseExactDigits(i32, input, &index, 4);
            },
            .year_2digit => {
                if (components.year != null) return ParseError.InvalidFormat;
                const value = try parseExactDigits(i32, input, &index, 2);
                components.year = 2000 + value;
            },
            .month_number => {
                if (components.month != null) return ParseError.InvalidFormat;
                const value = try parseExactDigits(u8, input, &index, 2);
                if (value < 1 or value > 12) return ParseError.InvalidDate;
                components.month = value;
            },
            .month_name_long => {
                if (components.month != null) return ParseError.InvalidFormat;
                components.month = try parseMonthName(locale_data.month_names_long[0..], input, &index);
            },
            .month_name_short => {
                if (components.month != null) return ParseError.InvalidFormat;
                components.month = try parseMonthName(locale_data.month_names_short[0..], input, &index);
            },
            .day_of_month => {
                if (components.day != null) return ParseError.InvalidFormat;
                const value = try parseExactDigits(u8, input, &index, 2);
                if (value < 1 or value > 31) return ParseError.InvalidDate;
                components.day = value;
            },
            .day_of_week_long => try consumeWeekday(locale_data.weekday_names_long[0..], input, &index),
            .day_of_week_short => try consumeWeekday(locale_data.weekday_names_short[0..], input, &index),
            .hour_24 => {
                if (components.hour24 != null or components.hour12 != null) return ParseError.InvalidFormat;
                const value = try parseExactDigits(u8, input, &index, 2);
                if (value > 23) return ParseError.InvalidDate;
                components.hour24 = value;
            },
            .hour_12 => {
                if (components.hour24 != null or components.hour12 != null) return ParseError.InvalidFormat;
                const value = try parseExactDigits(u8, input, &index, 2);
                if (value == 0 or value > 12) return ParseError.InvalidDate;
                components.hour12 = value;
            },
            .minute => {
                if (components.minute != null) return ParseError.InvalidFormat;
                const value = try parseExactDigits(u8, input, &index, 2);
                if (value > 59) return ParseError.InvalidDate;
                components.minute = value;
            },
            .second => {
                if (components.second != null) return ParseError.InvalidFormat;
                const value = try parseExactDigits(u8, input, &index, 2);
                if (value > 59) return ParseError.InvalidDate;
                components.second = value;
            },
            .am_pm => {
                if (components.meridiem != null) return ParseError.InvalidFormat;
                components.meridiem = try parseMeridiemValue(locale_data.am_pm[0..], input, &index);
            },
            .timezone_name => {
                if (components.tz_name != null) return ParseError.InvalidFormat;
                components.tz_name = try parseTimeZoneName(input, &index);
            },
            .timezone_offset => {
                if (components.tz_offset_seconds != null) return ParseError.InvalidFormat;
                components.tz_offset_seconds = try parseTimezoneOffset(input, &index);
            },
            .fractional_second => {
                if (components.fractional_ns != 0) return ParseError.InvalidFormat;
                components.fractional_ns = try parseFractionalSeconds(input, &index);
            },
        }
    }

    if (index != input.len) return ParseError.UnexpectedCharacter;

    const year = components.year orelse return ParseError.MissingComponent;
    const month = components.month orelse return ParseError.MissingComponent;
    const day = components.day orelse return ParseError.MissingComponent;

    const date = calendar.Date{ .year = year, .month = month, .day = day };
    if (!date.isValid()) return ParseError.InvalidDate;

    const hour = try components.resolveHour();
    const minute = components.minute orelse 0;
    const second = components.second orelse 0;
    const fractional_ns = components.fractional_ns;

    const cal = calendar.Calendar.init(.gregorian);
    const day_timestamp = cal.unixTimestampFromDate(date);
    const total_seconds: i64 = day_timestamp + @as(i64, hour) * 3600 + @as(i64, minute) * 60 + @as(i64, second);

    var tz_offset_seconds = components.tz_offset_seconds orelse 0;
    var resolved_timezone = TimeZone{ .name = "UTC", .offset_seconds = tz_offset_seconds };

    if (components.tz_name) |tz_name| {
        if (timezone.lookupTimeZone(tz_name)) |tz_data| {
            if (components.tz_offset_seconds == null) {
                var guess = timezone.getOffsetSeconds(tz_data, total_seconds);
                var i: usize = 0;
                while (i < 3) : (i += 1) {
                    const utc_candidate = total_seconds - guess;
                    const computed = timezone.getOffsetSeconds(tz_data, utc_candidate);
                    if (computed == guess) break;
                    guess = computed;
                }
                tz_offset_seconds = guess;
            }
            resolved_timezone = TimeZone{ .name = tz_data.name, .offset_seconds = tz_offset_seconds };
        } else {
            if (components.tz_offset_seconds == null) {
                return ParseError.UnknownTimeZone;
            }
            resolved_timezone = TimeZone{ .name = timezone.FIXED_OFFSET_NAME, .offset_seconds = tz_offset_seconds };
        }
    } else if (components.tz_offset_seconds != null) {
        const name = if (tz_offset_seconds == 0) "UTC" else timezone.FIXED_OFFSET_NAME;
        resolved_timezone = TimeZone{ .name = name, .offset_seconds = tz_offset_seconds };
    }

    const timestamp_seconds = total_seconds - @as(i64, tz_offset_seconds);
    const timestamp_ns = timestamp_seconds * std.time.ns_per_s + @as(i64, fractional_ns);

    return DateTime{
        .timestamp_ns = timestamp_ns,
        .timezone = resolved_timezone,
    };
}

const Meridiem = enum { am, pm };

const Components = struct {
    year: ?i32 = null,
    month: ?u8 = null,
    day: ?u8 = null,
    hour24: ?u8 = null,
    hour12: ?u8 = null,
    minute: ?u8 = null,
    second: ?u8 = null,
    fractional_ns: u32 = 0,
    tz_offset_seconds: ?i32 = null,
    tz_name: ?[]const u8 = null,
    meridiem: ?Meridiem = null,

    fn resolveHour(self: Components) ParseError!u8 {
        if (self.hour24) |value| {
            if (self.hour12 != null or self.meridiem != null) return ParseError.InvalidFormat;
            return value;
        }
        if (self.hour12) |value| {
            if (self.meridiem) |indicator| {
                var base: u8 = value;
                if (value == 12) base = 0;
                return switch (indicator) {
                    .am => base,
                    .pm => base + 12,
                };
            }
            return ParseError.MissingComponent;
        }
        if (self.meridiem != null) return ParseError.InvalidFormat;
        return 0;
    }
};

fn parseExactDigits(comptime T: type, input: []const u8, index: *usize, digits: usize) ParseError!T {
    if (index.* + digits > input.len) return ParseError.MissingComponent;
    var value: usize = 0;
    var i: usize = 0;
    while (i < digits) : (i += 1) {
        const c = input[index.* + i];
        if (!ascii.isDigit(c)) return ParseError.UnexpectedCharacter;
        value = value * 10 + (c - '0');
    }
    index.* += digits;
    const casted: T = @intCast(value);
    return casted;
}

fn parseMonthName(names: []const []const u8, input: []const u8, index: *usize) ParseError!u8 {
    var best_match: ?u8 = null;
    var best_len: usize = 0;
    for (names, 0..) |name, idx| {
        if (input.len >= index.* + name.len and std.mem.eql(u8, input[index.* .. index.* + name.len], name)) {
            if (name.len > best_len) {
                best_match = @as(u8, @intCast(idx + 1));
                best_len = name.len;
            }
        }
    }
    if (best_match == null) return ParseError.InvalidDate;
    index.* += best_len;
    return best_match.?;
}

fn consumeWeekday(names: []const []const u8, input: []const u8, index: *usize) ParseError!void {
    _ = try parseMonthName(names, input, index);
}

fn parseMeridiemValue(am_pm: []const []const u8, input: []const u8, index: *usize) ParseError!Meridiem {
    if (am_pm.len != 2) return ParseError.UnknownLocale;
    if (startsWithCaseInsensitive(input[index.*..], am_pm[0])) {
        index.* += am_pm[0].len;
        return .am;
    }
    if (startsWithCaseInsensitive(input[index.*..], am_pm[1])) {
        index.* += am_pm[1].len;
        return .pm;
    }
    return ParseError.InvalidFormat;
}

fn parseFractionalSeconds(input: []const u8, index: *usize) ParseError!u32 {
    if (index.* >= input.len or !ascii.isDigit(input[index.*])) return ParseError.MissingComponent;
    var value: u32 = 0;
    var count: usize = 0;
    while (index.* < input.len and ascii.isDigit(input[index.*]) and count < 9) : (count += 1) {
        value = value * 10 + (input[index.*] - '0');
        index.* += 1;
    }
    if (count == 0) return ParseError.MissingComponent;
    if (index.* < input.len and ascii.isDigit(input[index.*])) return ParseError.NumberOverflow;
    var scaled = value;
    var fill: usize = count;
    while (fill < 9) : (fill += 1) {
        scaled *= 10;
    }
    return scaled;
}

fn parseTimezoneOffset(input: []const u8, index: *usize) ParseError!i32 {
    if (index.* >= input.len) return ParseError.MissingComponent;
    const first = input[index.*];
    if (first == 'Z' or first == 'z') {
        index.* += 1;
        return 0;
    }
    if (first != '+' and first != '-') return ParseError.UnexpectedCharacter;
    const sign: i32 = if (first == '+') 1 else -1;
    index.* += 1;
    const hours = try parseExactDigits(i32, input, index, 2);
    var minutes: i32 = 0;
    if (index.* < input.len and input[index.*] == ':') {
        index.* += 1;
        minutes = try parseExactDigits(i32, input, index, 2);
    } else {
        minutes = try parseExactDigits(i32, input, index, 2);
    }
    if (hours > 23 or minutes > 59) return ParseError.InvalidOffset;
    return sign * (hours * 3600 + minutes * 60);
}

fn parseTimeZoneName(input: []const u8, index: *usize) ParseError![]const u8 {
    const start = index.*;
    while (index.* < input.len and isTzNameChar(input[index.*])) : (index.* += 1) {}
    if (index.* == start) return ParseError.MissingComponent;
    return input[start..index.*];
}

fn isTzNameChar(c: u8) bool {
    return ascii.isAlphabetic(c) or ascii.isDigit(c) or c == '/' or c == '_' or c == '-' or c == '+';
}

fn startsWithCaseInsensitive(haystack: []const u8, needle: []const u8) bool {
    if (haystack.len < needle.len) return false;
    var i: usize = 0;
    while (i < needle.len) : (i += 1) {
        if (ascii.toLower(haystack[i]) != ascii.toLower(needle[i])) return false;
    }
    return true;
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
                'f' => .fractional_second,
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

    const tz_info = timezone.lookupTimeZone("UTC").?;
    const tz = TimeZone{ .name = tz_info.name, .offset_seconds = 0 };

    const dt = DateTime{
        .timestamp_ns = 1577836800 * std.time.ns_per_s, // 2020-01-01 00:00:00 UTC
        .timezone = tz,
    };

    const formatted = try formatDateTime(allocator, dt, "%Y-%m-%d %H:%M:%S", Locale.DEFAULT);
    defer allocator.free(formatted);

    try std.testing.expectEqualStrings("2020-01-01 00:00:00", formatted);
}

test "parse ISO 8601" {
    const allocator = std.testing.allocator;
    const dt = try parseDateTime("2024-01-15T14:30:45Z", "%Y-%m-%dT%H:%M:%S%z", allocator);

    const expected_timestamp: i64 = 1705329045; // 2024-01-15T14:30:45Z
    try std.testing.expectEqual(expected_timestamp, @divFloor(dt.timestamp_ns, std.time.ns_per_s));
    try std.testing.expectEqualStrings("UTC", dt.timezone.name);
}

test "parse fractional seconds and offset" {
    const allocator = std.testing.allocator;
    const dt = try parseDateTime("2024-01-15T09:30:45.123456789-0500", "%Y-%m-%dT%H:%M:%S.%f%z", allocator);

    const expected_timestamp: i64 = 1705329045; // Converted to UTC
    try std.testing.expectEqual(expected_timestamp, @divFloor(dt.timestamp_ns, std.time.ns_per_s));
    try std.testing.expectEqual(@as(i32, -5 * 3600), dt.timezone.offset_seconds);
    try std.testing.expectEqual(@as(i64, 123_456_789), @mod(dt.timestamp_ns, std.time.ns_per_s));
}

test "format with different locales" {
    const allocator = std.testing.allocator;

    const tz_info = timezone.lookupTimeZone("UTC").?;
    const tz = TimeZone{ .name = tz_info.name, .offset_seconds = 0 };

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
