import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:lockdown_engine/data/repositories/activation_repository.dart';

class ActivationController extends GetxController {
  final studentNameController = TextEditingController();
  final tokenController = TextEditingController();
  final isLoading = false.obs;
  final errorMessage = ''.obs;

  final _repo = ActivationRepository();
  final _storage = GetStorage();

  static const String _keyToken = 'activation_token';
  static const String _keyExpiresAt = 'token_expires_at';
  static const String _keyStudentName = 'student_name';
  static const String _keyExamName = 'exam_name';
  static const String _keyRedirectUrl = 'redirect_url';
  static const String _keySessionId = 'activation_session_id';
  static const String _keyMaxViolations = 'activation_max_violations';
  static const String _keyHasViolationLimit = 'activation_has_violation_limit';

  @override
  void onInit() {
    super.onInit();
    final savedStudentName = getStudentName();
    if (savedStudentName != null && savedStudentName.isNotEmpty) {
      studentNameController.text = savedStudentName;
    }
  }

  /// Cek apakah token tersimpan di local storage masih valid (belum expired).
  static bool isTokenValid() {
    final storage = GetStorage();
    final token = storage.read<String>(_keyToken);
    final expiresAt = storage.read<String>(_keyExpiresAt);
    if (token == null || expiresAt == null) return false;
    try {
      final expiry = DateTime.parse(expiresAt);
      return DateTime.now().isBefore(expiry);
    } catch (_) {
      return false;
    }
  }

  /// Ambil token dari storage (null jika tidak ada).
  static String? getSavedToken() {
    return GetStorage().read<String>(_keyToken);
  }

  /// Ambil nama siswa dari storage (null jika tidak ada).
  static String? getStudentName() {
    return GetStorage().read<String>(_keyStudentName);
  }

  /// Ambil nama ujian dari storage (null jika tidak ada).
  static String? getExamName() {
    return GetStorage().read<String>(_keyExamName);
  }

  /// Ambil redirect URL dari storage (null jika tidak ada).
  static String? getRedirectUrl() {
    return GetStorage().read<String>(_keyRedirectUrl);
  }

  /// Ambil session ID dari storage (null jika tidak ada).
  static int? getSessionId() {
    return GetStorage().read<int>(_keySessionId);
  }

  /// Ambil waktu expired token (DateTime) dari storage (null jika tidak ada).
  static DateTime? getExpiresAt() {
    final expiresAt = GetStorage().read<String>(_keyExpiresAt);
    if (expiresAt == null) return null;
    try {
      return DateTime.parse(expiresAt);
    } catch (_) {
      return null;
    }
  }

  /// Ambil batas pelanggaran maksimal dari storage (null jika guru menonaktifkan batasan).
  static int? getMaxViolations() {
    return GetStorage().read<int>(_keyMaxViolations);
  }

  /// Cek apakah pembatasan pelanggaran aktif (true: aktif, false: dinonaktifkan guru).
  static bool getHasViolationLimit() {
    return GetStorage().read<bool>(_keyHasViolationLimit) ?? true;
  }

  Future<void> verify({VoidCallback? onSuccess}) async {
    final studentName = studentNameController.text.trim();
    final token = tokenController.text.trim();

    if (studentName.isEmpty) {
      errorMessage.value = 'Nama siswa tidak boleh kosong.';
      return;
    }

    if (token.isEmpty) {
      errorMessage.value = 'Token tidak boleh kosong.';
      return;
    }

    isLoading.value = true;
    errorMessage.value = '';

    try {
      final result = await _repo.verifyToken(token, studentName);

      if (result.valid) {
        // Simpan token, waktu expired, dan detail ujian ke GetStorage
        await _storage.write(_keyToken, token);
        await _storage.write(_keyExpiresAt, result.expiresAt);
        await _storage.write(_keyStudentName, result.studentName ?? studentName);
        if (result.examName != null) {
          await _storage.write(_keyExamName, result.examName);
        }
        if (result.redirectUrl != null) {
          await _storage.write(_keyRedirectUrl, result.redirectUrl);
        }
        if (result.sessionId != null) {
          await _storage.write(_keySessionId, result.sessionId);
        }
        await _storage.write(_keyMaxViolations, result.maxViolations);
        await _storage.write(_keyHasViolationLimit, result.hasViolationLimit);

        Get.back(); // tutup dialog
        onSuccess?.call();
      } else {
        errorMessage.value = result.message;
      }
    } catch (e) {
      // Hapus prefix "Exception: " jika ada
      final msg = e.toString().replaceFirst('Exception: ', '');
      errorMessage.value = msg;
    } finally {
      isLoading.value = false;
    }
  }

  /// Hapus data token & aktivasi dari storage (dipakai saat expired / reset).
  static Future<void> clearToken() async {
    final storage = GetStorage();
    await storage.remove(_keyToken);
    await storage.remove(_keyExpiresAt);
    await storage.remove(_keyStudentName);
    await storage.remove(_keyExamName);
    await storage.remove(_keyRedirectUrl);
    await storage.remove(_keySessionId);
    await storage.remove(_keyMaxViolations);
    await storage.remove(_keyHasViolationLimit);
  }

  /// Hapus hanya session ID saat sesi selesai, tanpa menghapus nama & token
  static Future<void> clearSessionId() async {
    final storage = GetStorage();
    await storage.remove(_keySessionId);
  }

  @override
  void onClose() {
    studentNameController.dispose();
    tokenController.dispose();
    super.onClose();
  }
}
