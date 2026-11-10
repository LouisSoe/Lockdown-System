import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:lockdown_engine/app/routes/app_routes.dart';
import 'package:lockdown_engine/data/repositories/activation_repository.dart';
import 'package:lockdown_engine/modules/activation/controllers/activation_controller.dart';
import 'package:lockdown_engine/modules/setup/views/admin_base_url_dialog.dart';
import 'package:lockdown_engine/services/lockdown/lockdown_service.dart';

class SetupController extends GetxController {
  final studentNameController = TextEditingController();
  final tokenController = TextEditingController();

  final isLoading = false.obs;
  final errorMessage = ''.obs;

  final _repo = ActivationRepository();
  final _storage = GetStorage();

  // Mode Ujian Ketat (Strict CBT Policy) — selalu aktif otomatis via Kiosk & Lockdown
  final isStrictPolicyEnabled = true.obs;

  int _shieldTapCount = 0;
  DateTime? _lastShieldTapTime;

  /// Trigger ketukan rahasia pada logo Shield (5x ketuk cepat untuk menu admin)
  void onShieldTapped() {
    final now = DateTime.now();
    if (_lastShieldTapTime == null || now.difference(_lastShieldTapTime!).inMilliseconds > 2500) {
      _shieldTapCount = 1;
    } else {
      _shieldTapCount++;
    }
    _lastShieldTapTime = now;

    if (_shieldTapCount == 3) {
      Get.snackbar(
        'Akses Admin',
        '2 ketukan lagi untuk membuka Pengaturan Server',
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.blueGrey.shade900,
        colorText: Colors.white,
      );
    } else if (_shieldTapCount == 4) {
      Get.snackbar(
        'Akses Admin',
        '1 ketukan lagi untuk membuka Pengaturan Server',
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.blueGrey.shade900,
        colorText: Colors.white,
      );
    } else if (_shieldTapCount >= 5) {
      _shieldTapCount = 0;
      openAdminMenu();
    }
  }

  void openAdminMenu() {
    AdminBaseUrlDialog.show();
  }

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
        await _storage.write('activation_max_violations', result.maxViolations);
        await _storage.write('activation_has_violation_limit', result.hasViolationLimit);

        final examUrl = result.redirectUrl;
        if (examUrl == null || examUrl.isEmpty) {
          errorMessage.value = 'Guru belum mengatur URL ujian. Silakan hubungi guru Anda.';
          return;
        }

        // Minta izin DND (Notification Policy) agar notifikasi pesan tidak muncul
        await _requestNotificationPolicyIfNeeded();

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
      final examArgs = {
        'exam_url': url,
        'student_name': ActivationController.getStudentName(),
        'exam_name': ActivationController.getExamName(),
        'session_id': ActivationController.getSessionId(),
        'strict_policy': isStrictPolicyEnabled.value,
        'max_violations': ActivationController.getMaxViolations(),
        'has_violation_limit': ActivationController.getHasViolationLimit(),
      };

      if (Platform.isAndroid) {
        final lockdown = Get.find<LockdownService>();
        if (!lockdown.kioskController.status.prereqOk) {
          Get.offNamed(AppRoutes.PREFLIGHT, arguments: examArgs);
          return;
        }
      }

      Get.offNamed(
        AppRoutes.EXAM,
        arguments: examArgs,
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


  /// Cek izin Notification Policy (DND).
  /// Jika belum diberikan, tampilkan dialog penjelasan + tombol buka pengaturan.
  /// Kembalikan true jika sudah bisa lanjut (izin sudah diberikan).
  Future<bool> _requestNotificationPolicyIfNeeded() async {
    try {
      final lockdown = Get.find<LockdownService>();
      final granted = await lockdown.isNotificationPolicyGranted();
      if (granted) return true;

      // Tampilkan dialog permintaan izin
      await Get.dialog<bool>(
        AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.notifications_off_rounded, color: Colors.orange.shade700, size: 22),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Izin Diperlukan',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Aplikasi memerlukan izin "Akses Jangan Ganggu" agar notifikasi dari aplikasi lain tidak muncul selama ujian berlangsung.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Setelah halaman pengaturan terbuka, izinkan "Lockdown CBT" untuk mengakses fitur Jangan Ganggu.',
                          style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('Lewati'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.settings_rounded, size: 16),
              label: const Text('Buka Pengaturan'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                await lockdown.openNotificationPolicySettings();
                Get.back(result: true);
              },
            ),
          ],
        ),
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 150),
        transitionCurve: Curves.easeOutCubic,
      );

      // Jika user menekan "Lewati", tetap lanjutkan ujian (tanpa blokir notifikasi)
      return true;
    } catch (e) {
      print('✗ _requestNotificationPolicyIfNeeded error: $e');
      return true; // Jangan block ujian karena gagal cek izin
    }
  }

  @override
  void onClose() {
    studentNameController.dispose();
    tokenController.dispose();
    super.onClose();
  }
}
