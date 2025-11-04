//! Astronomical calculations for sunrise, sunset, lunar phases
const std = @import("std");
const math = std.math;
const DateTime = @import("root.zig").DateTime;
const Duration = @import("root.zig").Duration;

pub const Coordinates = struct {
    latitude: f64,  // Degrees, positive for North
    longitude: f64, // Degrees, positive for East
};

pub const SolarEvent = struct {
    sunrise: DateTime,
    sunset: DateTime,
    solar_noon: DateTime,
    day_length: Duration,
};

pub const LunarPhase = enum {
    new_moon,
    waxing_crescent,
    first_quarter,
    waxing_gibbous,
    full_moon,
    waning_gibbous,
    last_quarter,
    waning_crescent,
};

pub const MoonPhaseInfo = struct {
    phase: LunarPhase,
    illumination: f64, // Percentage illuminated (0.0 to 1.0)
    age_days: f64,     // Days since new moon
};

// Calculate sunrise and sunset for a given date and location
pub fn calculateSolarEvents(date: DateTime, coords: Coordinates) SolarEvent {
    const julian_day = toJulianDay(date);
    const sunrise_jd = calculateSunrise(julian_day, coords.latitude, coords.longitude);
    const sunset_jd = calculateSunset(julian_day, coords.latitude, coords.longitude);
    const solar_noon_jd = calculateSolarNoon(julian_day, coords.longitude);

    const sunrise_dt = fromJulianDay(sunrise_jd, date.timezone);
    const sunset_dt = fromJulianDay(sunset_jd, date.timezone);
    const solar_noon_dt = fromJulianDay(solar_noon_jd, date.timezone);

    const day_length = Duration{
        .nanoseconds = sunset_dt.timestamp_ns - sunrise_dt.timestamp_ns,
    };

    return SolarEvent{
        .sunrise = sunrise_dt,
        .sunset = sunset_dt,
        .solar_noon = solar_noon_dt,
        .day_length = day_length,
    };
}

// Calculate lunar phase for a given date
pub fn calculateLunarPhase(date: DateTime) MoonPhaseInfo {
    const julian_day = toJulianDay(date);

    // Calculate lunar age (days since new moon)
    const lunar_cycle_days = 29.530588853; // Average lunar cycle length
    const known_new_moon_jd = 2451549.5; // New moon on January 6, 2000

    const cycles_since_reference = (julian_day - known_new_moon_jd) / lunar_cycle_days;
    const age_days = @mod(cycles_since_reference, 1.0) * lunar_cycle_days;

    // Calculate illumination
    const phase_angle = (age_days / lunar_cycle_days) * 2.0 * math.pi;
    const illumination = (1.0 - math.cos(phase_angle)) / 2.0;

    // Determine phase
    const phase: LunarPhase = if (age_days < 1.84566)
        .new_moon
    else if (age_days < 5.53699)
        .waxing_crescent
    else if (age_days < 9.22831)
        .first_quarter
    else if (age_days < 12.91963)
        .waxing_gibbous
    else if (age_days < 16.61096)
        .full_moon
    else if (age_days < 20.30228)
        .waning_gibbous
    else if (age_days < 23.99361)
        .last_quarter
    else
        .waning_crescent;

    return MoonPhaseInfo{
        .phase = phase,
        .illumination = illumination,
        .age_days = age_days,
    };
}

// Calculate solar elevation angle
pub fn calculateSolarElevation(date: DateTime, coords: Coordinates) f64 {
    const julian_day = toJulianDay(date);
    const solar_declination = calculateSolarDeclination(julian_day);
    const hour_angle = calculateHourAngle(date, coords.longitude);

    const lat_rad = math.degreesToRadians(coords.latitude);
    const dec_rad = math.degreesToRadians(solar_declination);
    const hour_rad = math.degreesToRadians(hour_angle);

    const elevation_rad = math.asin(
        math.sin(lat_rad) * math.sin(dec_rad) +
            math.cos(lat_rad) * math.cos(dec_rad) * math.cos(hour_rad),
    );

    return math.radiansToDegrees( elevation_rad);
}

// Calculate solar azimuth angle
pub fn calculateSolarAzimuth(date: DateTime, coords: Coordinates) f64 {
    const julian_day = toJulianDay(date);
    const solar_declination = calculateSolarDeclination(julian_day);
    const hour_angle = calculateHourAngle(date, coords.longitude);
    const elevation = calculateSolarElevation(date, coords);

    const lat_rad = math.degreesToRadians(coords.latitude);
    const dec_rad = math.degreesToRadians(solar_declination);
    const hour_rad = math.degreesToRadians(hour_angle);
    _ = elevation;

    const azimuth_rad = math.atan2(
        math.sin(hour_rad),
        math.cos(hour_rad) * math.sin(lat_rad) - math.tan(dec_rad) * math.cos(lat_rad),
    );

    var azimuth = math.radiansToDegrees( azimuth_rad);
    if (azimuth < 0) azimuth += 360.0;

    return azimuth;
}

// Helper functions

fn toJulianDay(date: DateTime) f64 {
    const unix_timestamp = @divFloor(date.timestamp_ns, std.time.ns_per_s);
    const julian_day = @as(f64, @floatFromInt(unix_timestamp)) / 86400.0 + 2440587.5;
    return julian_day;
}

fn fromJulianDay(julian_day: f64, timezone: @import("root.zig").TimeZone) DateTime {
    const unix_timestamp = @as(i64, @intFromFloat((julian_day - 2440587.5) * 86400.0));
    return DateTime{
        .timestamp_ns = unix_timestamp * std.time.ns_per_s,
        .timezone = timezone,
    };
}

fn calculateSolarDeclination(julian_day: f64) f64 {
    const n = julian_day - 2451545.0; // Days since J2000.0
    const L = @mod(280.460 + 0.9856474 * n, 360.0); // Mean longitude of Sun
    const g = math.degreesToRadians( @mod(357.528 + 0.9856003 * n, 360.0)); // Mean anomaly
    const lambda = math.degreesToRadians( L + 1.915 * math.sin(g) + 0.020 * math.sin(2.0 * g)); // True longitude

    const declination = math.asin(math.sin(math.degreesToRadians( 23.439)) * math.sin(lambda));
    return math.radiansToDegrees( declination);
}

fn calculateEquationOfTime(julian_day: f64) f64 {
    const n = julian_day - 2451545.0;
    const L = @mod(280.460 + 0.9856474 * n, 360.0);
    const g = math.degreesToRadians( @mod(357.528 + 0.9856003 * n, 360.0));
    const lambda = math.degreesToRadians( L + 1.915 * math.sin(g) + 0.020 * math.sin(2.0 * g));

    const alpha = math.atan2(math.cos(math.degreesToRadians( 23.439)) * math.sin(lambda), math.cos(lambda));
    const equation_of_time = 4.0 * (L - math.radiansToDegrees( alpha));

    return equation_of_time;
}

fn calculateHourAngle(date: DateTime, longitude: f64) f64 {
    const unix_timestamp = @divFloor(date.timestamp_ns, std.time.ns_per_s);
    const seconds_since_midnight = @mod(unix_timestamp, 86400);
    const hours_since_midnight = @as(f64, @floatFromInt(seconds_since_midnight)) / 3600.0;

    const solar_time = hours_since_midnight + longitude / 15.0;
    const hour_angle = 15.0 * (solar_time - 12.0);

    return hour_angle;
}

fn calculateSunrise(julian_day: f64, latitude: f64, longitude: f64) f64 {
    const solar_declination = calculateSolarDeclination(julian_day);
    const equation_of_time = calculateEquationOfTime(julian_day);

    const lat_rad = math.degreesToRadians( latitude);
    const dec_rad = math.degreesToRadians( solar_declination);

    // Hour angle for sunrise (with atmospheric refraction correction)
    const sunrise_angle = -0.833; // Standard atmospheric refraction
    const cos_hour_angle = (math.sin(math.degreesToRadians( sunrise_angle)) - math.sin(lat_rad) * math.sin(dec_rad)) / (math.cos(lat_rad) * math.cos(dec_rad));

    if (cos_hour_angle > 1.0) return julian_day; // Polar night
    if (cos_hour_angle < -1.0) return julian_day; // Polar day

    const hour_angle = math.radiansToDegrees( math.acos(cos_hour_angle));
    const sunrise_time = 12.0 - hour_angle / 15.0 - longitude / 15.0 + equation_of_time / 60.0;

    return julian_day - 0.5 + sunrise_time / 24.0;
}

fn calculateSunset(julian_day: f64, latitude: f64, longitude: f64) f64 {
    const solar_declination = calculateSolarDeclination(julian_day);
    const equation_of_time = calculateEquationOfTime(julian_day);

    const lat_rad = math.degreesToRadians( latitude);
    const dec_rad = math.degreesToRadians( solar_declination);

    const sunset_angle = -0.833;
    const cos_hour_angle = (math.sin(math.degreesToRadians( sunset_angle)) - math.sin(lat_rad) * math.sin(dec_rad)) / (math.cos(lat_rad) * math.cos(dec_rad));

    if (cos_hour_angle > 1.0) return julian_day; // Polar night
    if (cos_hour_angle < -1.0) return julian_day; // Polar day

    const hour_angle = math.radiansToDegrees( math.acos(cos_hour_angle));
    const sunset_time = 12.0 + hour_angle / 15.0 - longitude / 15.0 + equation_of_time / 60.0;

    return julian_day - 0.5 + sunset_time / 24.0;
}

fn calculateSolarNoon(julian_day: f64, longitude: f64) f64 {
    const equation_of_time = calculateEquationOfTime(julian_day);
    const solar_noon_time = 12.0 - longitude / 15.0 + equation_of_time / 60.0;

    return julian_day - 0.5 + solar_noon_time / 24.0;
}

test "solar calculations" {
    const timezone = @import("timezone.zig").lookupTimeZone("UTC").?;
    const tz = @import("root.zig").TimeZone{ .name = timezone.name, .offset_seconds = 0 };

    // Test for New York City on summer solstice 2024
    const date = DateTime{
        .timestamp_ns = 1718841600 * std.time.ns_per_s, // 2024-06-20 00:00:00 UTC
        .timezone = tz,
    };

    const nyc_coords = Coordinates{
        .latitude = 40.7128,  // New York City
        .longitude = -74.0060,
    };

    const solar_events = calculateSolarEvents(date, nyc_coords);

    // Sunrise should occur during daylight hours (before noon)
    const ns_per_day: i64 = @intCast(std.time.ns_per_s * 60 * 60 * 24);
    const ns_per_36h: i64 = @intCast(std.time.ns_per_s * 60 * 60 * 36);

    const sunrise_delta = solar_events.sunrise.timestamp_ns - date.timestamp_ns;
    try std.testing.expect(@abs(sunrise_delta) <= ns_per_day);

    // Sunset should happen after sunrise and within a reasonable window
    const sunset_delta = solar_events.sunset.timestamp_ns - date.timestamp_ns;
    try std.testing.expect(sunset_delta > sunrise_delta);
    try std.testing.expect(sunset_delta <= ns_per_36h);

    // Daylight span should be positive
    try std.testing.expect(solar_events.day_length.nanoseconds > 0);
}

test "lunar phase calculations" {
    const timezone = @import("timezone.zig").lookupTimeZone("UTC").?;
    const tz = @import("root.zig").TimeZone{ .name = timezone.name, .offset_seconds = 0 };

    const date = DateTime{
        .timestamp_ns = 1609459200 * std.time.ns_per_s, // 2021-01-01 00:00:00 UTC
        .timezone = tz,
    };

    const phase_info = calculateLunarPhase(date);

    // Age should be between 0 and ~29.5 days
    try std.testing.expect(phase_info.age_days >= 0.0 and phase_info.age_days <= 30.0);

    // Illumination should be between 0 and 1
    try std.testing.expect(phase_info.illumination >= 0.0 and phase_info.illumination <= 1.0);
}

test "solar elevation and azimuth" {
    const timezone = @import("timezone.zig").lookupTimeZone("UTC").?;
    const tz = @import("root.zig").TimeZone{ .name = timezone.name, .offset_seconds = 0 };

    // Noon on summer solstice
    const date = DateTime{
        .timestamp_ns = (1718841600 + 12 * 3600) * std.time.ns_per_s, // 2024-06-20 12:00:00 UTC
        .timezone = tz,
    };

    const coords = Coordinates{
        .latitude = 40.7128,
        .longitude = -74.0060,
    };

    const elevation = calculateSolarElevation(date, coords);
    const azimuth = calculateSolarAzimuth(date, coords);

    // At summer solstice noon, sun should be above the horizon
    try std.testing.expect(elevation > 20.0 and elevation <= 90.0);

    // Azimuth should be within the valid 0-360° range
    try std.testing.expect(azimuth >= 0.0 and azimuth <= 360.0);
}