import 'package:dio/dio.dart';
import 'package:lockdown_engine/core/constants/api_endpoints.dart';
import 'package:lockdown_engine/data/models/activation_model.dart';
import 'package:lockdown_engine/data/providers/api_provider.dart';

class ActivationRepository {
  final ApiProvider _apiProvider = ApiProvider();

  /// Verifikasi token dan nama siswa ke endpoint POST /activation/verify.
  /// Melempar [Exception] dengan pesan spesifik dari server jika gagal.
  Future<ActivationModel> verifyToken(String token, String studentName) async {
    try {
      final response = await _apiProvider.post(
        ApiEndpoints.verifyToken,
        data: {
          'token': token.trim(),
          'student_name': studentName.trim(),
        },
      );
      return ActivationModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      final responseData = e.response?.data;
      if (responseData is Map<String, dynamic>) {
        final errors = responseData['errors'];
        if (errors is Map) {
          if (errors['student_name'] is List && (errors['student_name'] as List).isNotEmpty) {
            throw Exception(errors['student_name'][0].toString());
          }
          if (errors['token'] is List && (errors['token'] as List).isNotEmpty) {
            throw Exception(errors['token'][0].toString());
          }
          for (final value in errors.values) {
            if (value is List && value.isNotEmpty) {
              throw Exception(value[0].toString());
            }
          }
        }
        final message = responseData['message'];
        if (message is String && message.isNotEmpty) {
          throw Exception(message);
        }
      }

      if (e.response?.statusCode == 422) {
        throw Exception('Data verifikasi tidak valid.');
      }
      rethrow;
    }
  }

  /// Menandai sesi ujian siswa selesai ke endpoint POST /activation/complete
  Future<ActivationCompleteModel> completeActivation(int sessionId) async {
    try {
      final response = await _apiProvider.post(
        ApiEndpoints.completeActivation,
        data: {
          'session_id': sessionId,
        },
      );
      return ActivationCompleteModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final responseData = e.response?.data;

      if (responseData is Map<String, dynamic>) {
        final errors = responseData['errors'];
        if (errors is Map && errors['session_id'] is List && (errors['session_id'] as List).isNotEmpty) {
          throw Exception(errors['session_id'][0].toString());
        }

        final message = responseData['message'];
        if (message is String && message.isNotEmpty) {
          if (statusCode == 429) {
            throw Exception('Terlalu banyak permintaan (Too Many Attempts). Silakan coba beberapa saat lagi.');
          }
          throw Exception(message);
        }
      }

      if (statusCode == 429) {
        throw Exception('Terlalu banyak permintaan (Too Many Attempts). Silakan coba beberapa saat lagi.');
      }
      if (statusCode == 422) {
        throw Exception('Data sesi tidak valid.');
      }
      rethrow;
    }
  }
}
