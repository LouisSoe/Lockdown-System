import 'package:lockdown_engine/data/providers/api_provider.dart';
import 'package:lockdown_engine/data/models/exam_session_model.dart';
import 'package:lockdown_engine/data/models/exit_password_model.dart';
import 'package:lockdown_engine/core/constants/api_endpoints.dart';
import 'package:lockdown_engine/core/utils/device_info_helper.dart';

class ExamRepository {
  final ApiProvider _apiProvider = ApiProvider();
  
  Future<ExamSessionModel> startExam(String examUrl) async {
    final response = await _apiProvider.post(
      ApiEndpoints.startExam,
      data: {
        'exam_url': examUrl,
        'device_id': await DeviceInfoHelper.getDeviceId(),
        'device_info': await DeviceInfoHelper.getDeviceInfo(),
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    
    return ExamSessionModel.fromJson(response.data);
  }
  
  Future<ExitPasswordModel> validateExitPassword(
    String sessionId,
    String password,
  ) async {
    final response = await _apiProvider.post(
      ApiEndpoints.validatePassword,
      data: {
        'session_id': sessionId,
        'password': password,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    
    return ExitPasswordModel.fromJson(response.data);
  }
  
  Future<void> finishExam(String sessionId, String reason) async {
    await _apiProvider.post(
      ApiEndpoints.finishExam,
      data: {
        'session_id': sessionId,
        'reason': reason,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }
  
  Future<Map<String, dynamic>> getExamConfig() async {
    final response = await _apiProvider.get(ApiEndpoints.getConfig);
    return response.data;
  }
}
