//! Centralized error sets for ztime modules

pub const FormatError = error{
    InvalidFormat,
    UnsupportedSpecifier,
    InvalidDate,
    UnexpectedCharacter,
    NumberOverflow,
    MissingComponent,
    InvalidOffset,
    UnknownLocale,
};

pub const ParseError = error{
    InvalidFormat,
    InvalidDate,
    UnexpectedCharacter,
    NumberOverflow,
    MissingComponent,
    InvalidOffset,
    UnknownTimeZone,
    UnknownLocale,
};

pub const TimeZoneError = error{
    UnknownTimeZone,
    InvalidRuleData,
};

pub const CalendarError = error{
    InvalidDate,
    UnsupportedConversion,
};

pub const BusinessError = error{
    UnknownHoliday,
    InvalidCalendar,
};

pub const AstronomyError = error{
    InvalidCoordinate,
};
