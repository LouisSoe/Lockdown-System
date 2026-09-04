import 'package:lockdown_engine/data/providers/api_provider.dart';
import 'package:lockdown_engine/data/models/security_event_model.dart';
import 'package:lockdown_engine/core/constants/api_endpoints.dart';

class MonitoringRepository {
  final ApiProvider _apiProvider = ApiProvider();
  
  Future<void> uploadEvents(
    String sessionId,
    List<SecurityEventModel> events,
  ) async {
    await _apiProvider.post(
      ApiEndpoints.uploadEvents,
      data: {
        'session_id': sessionId,
        'events': events.map((e) => e.toJson()).toList(),
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }
  
  Future<void> uploadScreenshot(
    String sessionId,
    String eventId,
    String base64Image,
  ) async {
    await _apiProvider.post(
      ApiEndpoints.uploadScreenshot,
      data: {
        'session_id': sessionId,
        'event_id': eventId,
        'screenshot': base64Image,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }
}
