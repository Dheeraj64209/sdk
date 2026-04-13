abstract class SdkEvent {
  SdkEvent({DateTime? timestamp}) : timestamp = timestamp ?? DateTime.now();

  final DateTime timestamp;
}
