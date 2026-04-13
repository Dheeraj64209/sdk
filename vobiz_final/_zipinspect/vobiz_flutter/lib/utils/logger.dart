import 'dart:developer' as developer;

// lib/utils/logger.dart
//
// Lightweight logger for development and debugging.
// All errors and events route through here so they appear in one place.

class Log {
  static void info(String tag, String msg)  => developer.log(msg, name: tag);
  static void warn(String tag, String msg)  => developer.log('WARN  $msg', name: tag);
  static void error(String tag, String msg) => developer.log('ERROR $msg', name: tag);
}
