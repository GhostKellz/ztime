# ztime

<div align="center">
  <img src="assets/icons/ztime.png" alt="ztime logo" width="200" height="200"/>

  [![Built with Zig](https://img.shields.io/badge/Built%20with-Zig-yellow?logo=zig&logoColor=f7a41d)](https://ziglang.org/)
  [![Zig Development](https://img.shields.io/badge/Zig-0.16.0--dev-orange?logo=zig&logoColor=white)](https://ziglang.org/)
  [![Multi-Calendar Support](https://img.shields.io/badge/Calendars-5%20Systems-blue?logo=calendar&logoColor=white)](https://github.com/your-username/ztime)
  [![Astronomical Features](https://img.shields.io/badge/Astronomy-Solar%20%26%20Lunar-purple?logo=moon&logoColor=white)](https://github.com/your-username/ztime)
</div>

**ztime** is an advanced date and time library for Zig, providing comprehensive timezone handling, multiple calendar systems, astronomical calculations, and business day logic for high-precision timing applications.

## ✨ Features

### 🌍 **Timezone Handling**
- IANA timezone database with automatic updates
- Daylight Saving Time (DST) calculations
- Multiple timezone conversions
- High-precision offset calculations

### 📅 **Calendar Systems**
- **Gregorian** - Standard international calendar
- **Julian** - Historical calendar system
- **Islamic (Hijri)** - Lunar-based calendar
- **Hebrew** - Traditional Jewish calendar
- **Chinese** - Lunisolar calendar system

### 🌐 **Locale-Aware Formatting**
- Multiple language support (English, German, French)
- Customizable date/time formats
- Cultural-specific formatting rules
- strftime-compatible format specifiers

### 📊 **Business Day Logic**
- US Federal holiday calendar
- NYSE trading day calculations
- Custom business calendar support
- Holiday detection and business day arithmetic

### 🌙 **Astronomical Calculations**
- Solar events (sunrise, sunset, solar noon)
- Lunar phase calculations
- Solar elevation and azimuth
- Astronomical coordinate transformations
- High-precision timing for scientific applications

### ⏱️ **Duration & Arithmetic**
- Nanosecond precision timing
- Duration calculations between dates
- Business day arithmetic
- Time zone-aware calculations

## 🚀 Quick Start

### Integration

```bash
zig fetch --save https://github.com/ghostkellz/ztime/archive/refs/heads/main.tar.gz

```

### Basic Usage

```zig
const std = @import("std");
const ztime = @import("ztime");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get current time in different timezones
    const utc_now = ztime.utcNow();
    const ny_tz = try ztime.TimeZone.fromName("America/New_York");
    const ny_time = utc_now.toTimeZone(ny_tz);

    // Format dates in different locales
    const formatted = try ny_time.format("%A, %B %d, %Y at %H:%M",
        ztime.Locale.EN_US, allocator);
    defer allocator.free(formatted);

    std.debug.print("New York time: {s}\n", .{formatted});
}
```

## 📖 Core API

### DateTime Operations

```zig
// Create DateTime instances
const dt = ztime.DateTime.now(timezone);
const dt_from_timestamp = ztime.DateTime.fromUnixTimestamp(timestamp, timezone);
const dt_from_date = ztime.DateTime.fromDate(date, timezone);

// Parse and format
const parsed = try ztime.DateTime.parse("2024-01-15T14:30:45Z", "%Y-%m-%dT%H:%M:%SZ", allocator);
const formatted = try dt.format("%Y-%m-%d %H:%M:%S %Z", locale, allocator);

// Arithmetic operations
const future = dt.addDuration(ztime.Duration.fromDays(7));
const business_day = dt.addBusinessDays(5);
const duration_between = future.durationBetween(dt);
```

### Timezone Handling

```zig
// IANA timezone support
const ny_tz = try ztime.TimeZone.fromName("America/New_York");
const tokyo_tz = try ztime.TimeZone.fromName("Asia/Tokyo");
const utc_tz = try ztime.TimeZone.fromName("UTC");

// Get timezone information
const offset = ny_tz.getOffset(dt);
const is_dst = ny_tz.isDST(dt);

// Convert between timezones
const tokyo_time = ny_time.toTimeZone(tokyo_tz);
```

### Calendar Conversions

```zig
// Convert to different calendar systems
const gregorian = dt.toDate(.gregorian);
const islamic = dt.toDate(.islamic);
const hebrew = dt.toDate(.hebrew);
const chinese = dt.toDate(.chinese);

// Create from calendar dates
const date = ztime.calendar.Date{ .year = 2024, .month = 12, .day = 25 };
const christmas = ztime.DateTime.fromDate(date, utc_tz);
```

### Business Day Calculations

```zig
// Check business days and holidays
const is_business_day = dt.isBusinessDay();
const holiday_name = dt.isHoliday(); // Returns holiday name or null

// Business day arithmetic
const next_business_day = dt.addBusinessDays(1);
const prev_business_day = dt.addBusinessDays(-1);

// Custom business calendars
const nyse_cal = ztime.business.BusinessCalendar.NYSE;
const next_trading_day = nyse_cal.addBusinessDays(dt, 1);
```

### Astronomical Calculations

```zig
// Location coordinates
const coords = ztime.astronomy.Coordinates{
    .latitude = 40.7128,   // New York City
    .longitude = -74.0060,
};

// Solar calculations
const solar_events = dt.getSolarEvents(coords);
const sunrise = solar_events.sunrise;
const sunset = solar_events.sunset;
const day_length = solar_events.day_length;

// Solar position
const elevation = dt.getSolarElevation(coords);
const azimuth = dt.getSolarAzimuth(coords);

// Lunar calculations
const moon_phase = dt.getLunarPhase();
const phase_name = moon_phase.phase; // .new_moon, .full_moon, etc.
const illumination = moon_phase.illumination; // 0.0 to 1.0
```

## 🏗️ Building

### Prerequisites
- Zig 0.16.0-dev or later

### Build Commands

```bash
# Build the library and example
zig build

# Run tests
zig build test

# Run the demo application
zig build run

# Install (optional)
zig build install
```

## 🌟 Use Cases

### Financial Applications
- Trading day calculations
- Settlement date computations
- Market hour determinations
- Multi-timezone trading analysis

### Scientific Computing
- Astronomical event predictions
- Solar panel optimization
- Agricultural planning
- Research data timestamping

### International Applications
- Multi-timezone scheduling
- Cultural calendar integration
- Localized date formatting
- Holiday-aware systems

### Business Systems
- Payroll calculations
- Project timeline management
- SLA compliance tracking
- Global team coordination

## 🎯 Technical Requirements

As specified in the original design:

```zig
pub const DateTime = struct {
    pub fn now(timezone: TimeZone) DateTime;
    pub fn parse(input: []const u8, format: []const u8) !DateTime;
    pub fn format(self: DateTime, format: []const u8, locale: Locale) ![]u8;
    pub fn addBusinessDays(self: DateTime, days: i32) DateTime;
};

pub const TimeZone = struct {
    pub fn fromName(name: []const u8) !TimeZone;
    pub fn getOffset(self: TimeZone, when: DateTime) Duration;
};
```

## 🔧 Advanced Features

- **High-precision timing**: Nanosecond-level accuracy for financial and scientific applications
- **Memory efficient**: Minimal allocations with optional arena allocator support
- **Thread-safe**: Immutable data structures for concurrent applications
- **Extensible**: Plugin architecture for custom calendar and business day rules
- **Zero-copy parsing**: Efficient string processing for high-throughput systems

## 📚 Examples

Check out the comprehensive demo in `src/main.zig` which showcases:
- Multi-timezone operations
- Calendar system conversions
- Business day calculations
- Astronomical computations
- Multilingual formatting
- Duration arithmetic

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

