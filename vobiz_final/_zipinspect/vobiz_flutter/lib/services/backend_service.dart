import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/logger.dart';

class BackendService {
  // Override with:
  // flutter run --dart-define=VOBIZ_BACKEND_URL=http://192.168.1.12:3000
  static const String _configuredBaseUrl = String.fromEnvironment(
    'VOBIZ_BACKEND_URL',
    defaultValue: 'http://192.168.1.12:3000',
  );
  static const Duration timeout = Duration(seconds: 10);

  static String get baseUrl => _configuredBaseUrl.endsWith('/')
      ? _configuredBaseUrl.substring(0, _configuredBaseUrl.length - 1)
      : _configuredBaseUrl;

  static Future<void> makeCall(String phoneNumber) async {
    try {
      final url = Uri.parse('$baseUrl/call');

      Log.info('Backend', 'Initiating call to: $phoneNumber');
      Log.info('Backend', 'URL: $url');

      final response = await http
          .post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"to": phoneNumber}),
      )
          .timeout(timeout, onTimeout: () {
        throw TimeoutException(
          'Backend request timed out after ${timeout.inSeconds}s',
          timeout,
        );
      });

      Log.info('Backend', 'Response status: ${response.statusCode}');
      Log.info('Backend', 'Response body: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception(
          'Backend error: HTTP ${response.statusCode} - ${response.body}',
        );
      }

      Log.info('Backend', 'Call request successful');
    } on TimeoutException catch (e) {
      Log.error('Backend', 'Timeout: ${e.message}');
      rethrow;
    } catch (e) {
      Log.error('Backend', 'Error calling backend: $e');
      if (e.toString().contains('Cleartext HTTP traffic')) {
        throw Exception(
          'Backend HTTP traffic is blocked on this device. '
          'Use HTTPS or enable local cleartext traffic for the app.',
        );
      }
      rethrow;
    }
  }
}
