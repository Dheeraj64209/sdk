import 'sdk_event.dart';

class ErrorEvent extends SdkEvent {
  ErrorEvent({
    required this.code,
    required this.message,
    this.cause,
    super.timestamp,
  });

  final String code;
  final String message;
  final Object? cause;
}
