import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:lockdown_engine/app/routes/app_routes.dart';
import 'package:lockdown_engine/data/repositories/activation_repository.dart';
import 'package:lockdown_engine/modules/activation/controllers/activation_controller.dart';

class SetupController extends GetxController {
  final studentNameController = TextEditingController();
  final tokenController = TextEditingController();

  final isLoading = false.obs;
  final errorMessage = ''.obs;

  final _repo = ActivationRepository();
  final _storage = GetStorage();

  @override
  void onInit() {
    super.onInit();
    loadSession();
  }

  void loadSession() {
    final savedName = ActivationController.getStudentName() ?? '';
    final savedToken = ActivationController.getSavedToken() ?? '';

    if (savedName.isNotEmpty) {
      studentNameController.text = savedName;
    }
    if (savedToken.isNotEmpty) {
      tokenController.text = savedToken;
    }
  }

  /// Reset form jika ingin mengganti akun / token siswa
  Future<void> resetSession() async {
    await ActivationController.clearToken();
    studentNameController.clear();
    tokenController.clear();
    errorMessage.value = '';
  }

  /// Verifikasi token & nama siswa ke backend, lalu langsung mulai ujian
  Future<void> verifyAndStartExam() async {
    final studentName = studentNameController.text.trim();
    final token = tokenController.text.trim();

    if (studentName.isEmpty) {
      errorMessage.value = 'Nama siswa wajib diisi.';
      return;
    }

    if (token.isEmpty) {
      errorMessage.value = 'Token aktivasi wajib diisi.';
      return;
    }

    isLoading.value = true;
    errorMessage.value = '';

    try {
      final result = await _repo.verifyToken(token, studentName);

      if (result.valid) {
        // Simpan data aktivasi ke GetStorage
        await _storage.write('activation_token', token);
        await _storage.write('token_expires_at', result.expiresAt);
        await _storage.write('student_name', result.studentName ?? studentName);
        if (result.examName != null) {
          await _storage.write('exam_name', result.examName);
        }
        if (result.redirectUrl != null) {
          await _storage.write('redirect_url', result.redirectUrl);
        }
        if (result.sessionId != null) {
          await _storage.write('activation_session_id', result.sessionId);
        }

        final examUrl = result.redirectUrl;
        if (examUrl == null || examUrl.isEmpty) {
          errorMessage.value = 'Guru belum mengatur URL ujian. Silakan hubungi guru Anda.';
          return;
        }

        // Langsung masuk ke halaman ujian
        _navigateToExam(examUrl);
      } else {
        errorMessage.value = result.message;
      }
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      errorMessage.value = msg;
    } finally {
      isLoading.value = false;
    }
  }

  void _navigateToExam(String url) {
    try {
      isLoading.value = true;
      Get.toNamed(
        AppRoutes.EXAM,
        arguments: {
          'exam_url': url,
          'student_name': ActivationController.getStudentName(),
          'exam_name': ActivationController.getExamName(),
          'session_id': ActivationController.getSessionId(),
        },
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Gagal memulai ujian: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isLoading.value = false;
    }
  }

  @override
  void onClose() {
    studentNameController.dispose();
    tokenController.dispose();
    super.onClose();
  }
}
