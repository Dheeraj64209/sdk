import '../state/connection_state.dart';
import '../state/registration_state.dart';
import 'sdk_event.dart';

class ConnectionEvent extends SdkEvent {
  ConnectionEvent({
    required this.connectionState,
    required this.registrationState,
    this.message,
    super.timestamp,
  });

  final ConnectionStateStatus connectionState;
  final RegistrationState registrationState;
  final String? message;
}
