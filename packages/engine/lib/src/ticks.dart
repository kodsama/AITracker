/// Conversions between Dart [DateTime] and the .NET tick timestamps used by the
/// WorkingHours and Diarium SQLite stores.
///
/// Both apps are .NET, and both store local wall-clock time as `DateTime.Ticks`:
/// 100-nanosecond units since 0001-01-01 with no timezone attached. Reading a
/// row back on a machine in another zone therefore shows the same clock face,
/// which is what a timesheet wants.
library;

final DateTime _dotNetEpoch = DateTime.utc(1, 1, 1);

/// Ticks for the wall-clock reading of [time] in the local zone.
int toTicks(DateTime time) {
  final local = time.toLocal();
  final wallClock = DateTime.utc(
    local.year,
    local.month,
    local.day,
    local.hour,
    local.minute,
    local.second,
    local.millisecond,
    local.microsecond,
  );
  return wallClock.difference(_dotNetEpoch).inMicroseconds * 10;
}

/// The local [DateTime] whose wall-clock reading is [ticks].
DateTime fromTicks(int ticks) {
  final wallClock = _dotNetEpoch.add(Duration(microseconds: ticks ~/ 10));
  return DateTime(
    wallClock.year,
    wallClock.month,
    wallClock.day,
    wallClock.hour,
    wallClock.minute,
    wallClock.second,
    wallClock.millisecond,
    wallClock.microsecond,
  );
}
