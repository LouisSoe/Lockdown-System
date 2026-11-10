import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:lockdown_engine/core/utils/device_info_helper.dart';
import 'package:lockdown_engine/core/utils/uppercase_text_formatter.dart';
import 'package:lockdown_engine/services/webview/webview_service.dart';
import 'package:lockdown_engine/services/webview/javascript_bridge_service.dart';
import 'package:lockdown_engine/services/lockdown/lockdown_service.dart';
import 'package:lockdown_engine/services/anticheat/anticheat_service.dart';
import 'package:lockdown_engine/data/repositories/exam_repository.dart';
import 'package:lockdown_engine/data/models/exam_session_model.dart';
import 'package:lockdown_engine/data/repositories/activation_repository.dart';
import 'package:lockdown_engine/modules/activation/controllers/activation_controller.dart';
import 'package:lockdown_engine/app/routes/app_routes.dart';
import 'package:lockdown_engine/core/config/app_config.dart';

class ExamController extends GetxController {
  late String examUrl;
  ExamSessionModel? session;

  late WebViewService webViewService;
  late JavaScriptBridgeService jsBridge;
  late LockdownService lockdownService;
  late AntiCheatService antiCheatService;
  final examRepo = ExamRepository();
  final _activationRepo = ActivationRepository();

  final remainingTime = '00:00:00'.obs;
  final isExamActive = true.obs;
  Timer? _timer;
  DateTime? _endTime;

  // Strict CBT Policy (Mode Ujian Ketat)
  final isStrictPolicyEnabled = true.obs;
  final isLockedOut = false.obs;
  final isBlocked = false.obs; // true jika pelanggaran melebihi batas maksimal guru
  final showWarningModal = false.obs;
  final violationCount = 0.obs;
  final maxViolations = 2.obs; // Batas pelanggaran dari guru: 1, 2, atau 3 (dinamis)
  final hasViolationLimit = true.obs; // true: batas aktif; false: batas dinonaktifkan
  final pinController = TextEditingController();
  final isUnlocking = false.obs;

  void dismissWarningModal() {
    showWarningModal.value = false;
  }

  @override
  void onInit() {
    super.onInit();

    final args = Get.arguments as Map<String, dynamic>?;
    final urlArg = args?['exam_url'] as String?;
    final savedUrl = ActivationController.getRedirectUrl();
    final effectiveUrl = (urlArg != null && urlArg.trim().isNotEmpty)
        ? urlArg.trim()
        : (savedUrl != null && savedUrl.trim().isNotEmpty ? savedUrl.trim() : '');

    if (effectiveUrl.isEmpty || !effectiveUrl.startsWith('http')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.offAllNamed(AppRoutes.SETUP_URL);
        Get.snackbar(
          'Gagal Membuka Ujian',
          'URL ujian tidak ditemukan atau token belum diverifikasi. Silakan masukkan token aktivasi terlebih dahulu.',
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.red.shade700,
          colorText: Colors.white,
          duration: const Duration(seconds: 5),
        );
      });
      return;
    }

    examUrl = effectiveUrl;
    session = args?['session'];
    isStrictPolicyEnabled.value = args?['strict_policy'] ?? true;

    final dynamicMax = args?['max_violations'] ?? ActivationController.getMaxViolations();
    if (dynamicMax is int) {
      maxViolations.value = dynamicMax;
    }
    final dynamicHasLimit = args?['has_violation_limit'] ?? ActivationController.getHasViolationLimit();
    if (dynamicHasLimit is bool) {
      hasViolationLimit.value = dynamicHasLimit;
    }

    // Initialize services
    webViewService = Get.find<WebViewService>();
    jsBridge = Get.find<JavaScriptBridgeService>();
    lockdownService = Get.find<LockdownService>();
    antiCheatService = Get.find<AntiCheatService>();

    // Batasi navigasi WebView hanya ke URL / host ujian yang diset guru
    webViewService.setAllowedUrl(examUrl);

    // Register JavaScript handlers
    _registerJavaScriptHandlers();

    // Enable lockdown and start monitoring
    _initializeLockdown();

    // Start timer using activation token expiration or session duration
    _startTimer();
  }

  Future<void> _initializeLockdown() async {
    // 1. Selalu jalankan Anti-Cheat monitoring & listener Strict CBT Policy
    try {
      final effectiveSessionId = session?.sessionId ??
          (Get.arguments as Map<String, dynamic>?)?['session_id'] ??
          ActivationController.getSessionId() ??
          'exam-session';
      await antiCheatService.startMonitoring(effectiveSessionId);
      _setupStrictPolicyListener();
      print('✓ Anti-cheat monitoring and Strict CBT Policy active');
    } catch (e) {
      print('✗ Anti-cheat monitoring error: $e');
    }

    // 2. Jalankan Native Lockdown (Fullscreen, Kiosk/LockTask, dsb)
    try {
      final effectiveSessionId = session?.sessionId ??
          (Get.arguments as Map<String, dynamic>?)?['session_id']?.toString() ??
          ActivationController.getSessionId()?.toString() ??
          'exam-session';
      final studentName = (Get.arguments as Map<String, dynamic>?)?['student_name']?.toString() ??
          ActivationController.getStudentName() ??
          'STD-001';
      final token = ActivationController.getSavedToken() ?? '';

      await lockdownService.enableLockdown(
        apiBase: AppConfig.baseUrl,
        token: token,
        examId: effectiveSessionId,
        studentId: studentName,
        maxViolations: maxViolations.value,
        hasViolationLimit: hasViolationLimit.value,
      );
      print('✓ Native lockdown initialized');
    } catch (e) {
      print('✗ Lockdown initialization error: $e');
    }
  }

  void _setupStrictPolicyListener() {
    if (!isStrictPolicyEnabled.value) return;

    final focusMonitor = antiCheatService.focusMonitor;

    // 1. Trigger dari siklus hidup Flutter (WidgetsBindingObserver)
    focusMonitor.onFocusRegained = (count) {
      _handleViolation(count);
    };

    // 2. Trigger langsung dari Native Android (Status bar swipe / Home button / Recent apps)
    lockdownService.onSecurityViolation = (reason) {
      if (!isStrictPolicyEnabled.value || !isExamActive.value) return;
      focusMonitor.recordViolation(reason: reason);
      _handleViolation(focusMonitor.focusLossCount);
    };

    // 3. Sinkronisasi langsung dua arah dari KioskController (Native Kotlin)
    final kiosk = lockdownService.kioskController;
    kiosk.addListener(() {
      if (!isExamActive.value) return;
      final s = kiosk.status;
      if (s.violations != violationCount.value) {
        antiCheatService.focusMonitor.setFocusLossCount(s.violations);
        _handleViolation(s.violations);
      }
      if (hasViolationLimit.value) {
        if (s.isBlocked && !isBlocked.value) {
          showWarningModal.value = false;
          isLockedOut.value = true;
          isBlocked.value = true;
        } else if (s.isLockedOut && !isLockedOut.value && !isBlocked.value) {
          showWarningModal.value = false;
          isLockedOut.value = true;
        } else if (!s.isLockedOut && !s.isBlocked && isLockedOut.value) {
          showWarningModal.value = false;
          isLockedOut.value = false;
        }
      }
    });
  }

  void _handleViolation(int count) {
    if (!isStrictPolicyEnabled.value || !isExamActive.value) return;
    if (isBlocked.value) return;

    violationCount.value = count;

    if (hasViolationLimit.value) {
      if (count > maxViolations.value) {
        // Pelanggaran melebihi batas maksimal -> LANGSUNG DIBLOCK / TIDAK BISA MELANJUTKAN UJIAN
        showWarningModal.value = false;
        isLockedOut.value = true;
        isBlocked.value = true;
      } else {
        // Setiap kali pelanggaran (1, 2, dst <= max) -> WAJIB ISI TOKEN PELANGGARAN
        showWarningModal.value = false;
        isLockedOut.value = true;
      }
    } else {
      // Guru menonaktifkan pembatasan -> hanya peringatan biasa tanpa kunci token
      showWarningModal.value = true;
    }
  }

  /// Verifikasi Token Pelanggaran (Violation Token) ke endpoint POST /tokens/validate
  Future<bool> verifyViolationUnlockCode(String code) async {
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode.isEmpty) return false;

    // Validasi via endpoint POST /tokens/validate (type: "violation")
    try {
      final studentName = ActivationController.getStudentName();
      final deviceId = await DeviceInfoHelper.getDeviceId();

      final result = await _activationRepo.validateToken(
        token: cleanCode,
        type: 'violation',
        studentName: studentName,
        deviceId: deviceId,
      );

      final isValid = result.success && (result.data?.valid ?? false);
      if (!isValid) {
        final message = result.message.isNotEmpty
            ? result.message
            : 'Token pelanggaran tidak valid atau sudah kedaluwarsa.';
        Get.snackbar(
          'Token Salah',
          message,
          backgroundColor: Colors.red.shade700,
          colorText: Colors.white,
          snackPosition: SnackPosition.TOP,
          margin: const EdgeInsets.all(12),
          borderRadius: 8,
          icon: const Icon(Icons.error_outline, color: Colors.white),
          duration: const Duration(seconds: 4),
        );
      }
      return isValid;
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      Get.snackbar(
        'Token Salah',
        msg,
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP,
        margin: const EdgeInsets.all(12),
        borderRadius: 8,
        icon: const Icon(Icons.error_outline, color: Colors.white),
        duration: const Duration(seconds: 4),
      );
      return false;
    }
  }

  /// Buka kunci ujian setelah terkunci (memerlukan Token Pelanggaran dari guru)
  Future<bool> unlockBySupervisor(String pin) async {
    if (isBlocked.value) {
      Get.snackbar(
        'Ujian Diblokir',
        'Ujian telah diblokir permanen karena melebihi batas toleransi pelanggaran. Anda tidak dapat melanjutkan ujian.',
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP,
        margin: const EdgeInsets.all(12),
        borderRadius: 8,
        icon: const Icon(Icons.block_rounded, color: Colors.white),
      );
      return false;
    }

    final cleanPin = pin.trim().toUpperCase();
    if (cleanPin.isEmpty) {
      Get.snackbar(
        'Input Kosong',
        'Harap masukkan Token Pelanggaran dari guru',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.orange.shade800,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        borderRadius: 8,
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.white),
      );
      return false;
    }

    isUnlocking.value = true;
    try {
      final isValid = await verifyViolationUnlockCode(cleanPin);

      if (isValid) {
        // Berikan masa tenggang di focus monitor agar dialog sematkan layar dari sistem Android tidak memicu pelanggaran baru
        antiCheatService.focusMonitor.extendGracePeriod(seconds: 8);

        // Buka kunci di sisi native Kotlin & sinkronkan status
        await lockdownService.kioskController.unlockExam(cleanPin);

        isLockedOut.value = false;
        showWarningModal.value = false;
        pinController.clear();

        // PENTING: Nilai violationCount tetap dipertahankan kumulatif
        // agar pelanggaran berikutnya dihitung secara benar.

        // Minta sematkan layar kembali
        await lockdownService.kioskController.requestPin();

        Get.snackbar(
          'Ujian Dibuka Kembali',
          'Token valid. Kunci lembar ujian telah dibuka. Silakan lanjutkan pengerjaan.',
          backgroundColor: Colors.green.shade700,
          colorText: Colors.white,
          snackPosition: SnackPosition.TOP,
          margin: const EdgeInsets.all(12),
          borderRadius: 8,
          icon: const Icon(Icons.check_circle_outline, color: Colors.white),
          duration: const Duration(seconds: 4),
        );
        return true;
      } else {
        if (!Get.isSnackbarOpen) {
          Get.snackbar(
            'Token Salah',
            'Token Pelanggaran yang Anda masukkan tidak valid atau sudah kedaluwarsa.',
            backgroundColor: Colors.red.shade700,
            colorText: Colors.white,
            snackPosition: SnackPosition.TOP,
            margin: const EdgeInsets.all(12),
            borderRadius: 8,
            icon: const Icon(Icons.error_outline, color: Colors.white),
            duration: const Duration(seconds: 4),
          );
        }
        return false;
      }
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      Get.snackbar(
        'Token Salah',
        'Gagal memverifikasi token pelanggaran: $msg',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        borderRadius: 8,
        icon: const Icon(Icons.error_outline, color: Colors.white),
      );
      return false;
    } finally {
      isUnlocking.value = false;
    }
  }

  void _registerJavaScriptHandlers() {
    jsBridge.registerHandler('finishExam', (args) {
      finishExam('completed');
    });

    jsBridge.registerHandler('timeUp', (args) {
      finishExam('timeout');
    });

    jsBridge.registerHandler('message', (args) {
      print('Message from exam: $args');
    });

    jsBridge.registerHandler('ready', (args) async {
      await webViewService.injectJavaScriptBridge();
    });
  }

  void _startTimer() {
    // Prioritas 1: Ambil waktu expired dari token aktivasi yang tersimpan
    final tokenExpiresAt = ActivationController.getExpiresAt();

    if (tokenExpiresAt != null) {
      _endTime = tokenExpiresAt;
    } else if (session != null) {
      // Prioritas 2: Fallback ke session duration
      _endTime = session!.startTime.add(
        Duration(minutes: session!.duration),
      );
    } else {
      // Tidak ada token expiration & session
      remainingTime.value = '--:--:--';
      return;
    }

    _updateRemainingTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemainingTime();
    });
  }

  void _updateRemainingTime() {
    if (_endTime == null) return;

    final now = DateTime.now();
    final remaining = _endTime!.difference(now);

    if (remaining.isNegative) {
      _timer?.cancel();
      remainingTime.value = '00:00:00';
      finishExam('timeout');
    } else {
      final hours = remaining.inHours.toString().padLeft(2, '0');
      final minutes = (remaining.inMinutes % 60).toString().padLeft(2, '0');
      final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');
      remainingTime.value = '$hours:$minutes:$seconds';
    }
  }

  void onWebViewCreated(InAppWebViewController controller) {
    webViewService.webViewController = controller;
    jsBridge.setController(controller);
  }

  Future<void> showExitDialog() async {
    final passwordController = TextEditingController();

    await Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.exit_to_app_rounded, color: Colors.red.shade700, size: 22),
            ),
            const SizedBox(width: 10),
            const Text(
              'Keluar Ujian',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Masukkan Token Keluar (Exit Token) 6 digit dari guru untuk mengakhiri ujian:',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  textCapitalization: TextCapitalization.characters,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.text,
                  scrollPadding: const EdgeInsets.only(bottom: 80.0, top: 20.0),
                  inputFormatters: [
                    UpperCaseTextFormatter(),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Token Keluar (Exit Token)',
                    hintText: 'Contoh: XY89ZW',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.vpn_key_rounded),
                    isDense: true,
                  ),
                  onSubmitted: (value) => _validatePassword(value),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => _validatePassword(passwordController.text),
            child: const Text('Buka Kunci & Keluar'),
          ),
        ],
      ),
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 150),
      transitionCurve: Curves.easeOutCubic,
    );

    // Beri jeda aman sebelum dispose controller agar animasi dialog selesai seutuhnya
    Future.delayed(const Duration(milliseconds: 300), () {
      try {
        passwordController.dispose();
      } catch (_) {}
    });
  }

  Future<void> showForceCloseConfirmationDialog() async {
    await Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Konfirmasi Keluar Aplikasi'),
          ],
        ),
        content: const Text(
          'Apakah Anda yakin ingin keluar dan menutup aplikasi secara paksa (Force Close)?\n'
          'Sesi ujian Anda akan dihentikan.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Get.back();
              await forceCloseApp();
            },
            child: const Text('Tutup Aplikasi'),
          ),
        ],
      ),
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 150),
      transitionCurve: Curves.easeOutCubic,
    );
  }

  Future<void> forceCloseApp() async {
    try {
      await webViewService.disposeWebView();
      await antiCheatService.stopMonitoring();
      await lockdownService.disableLockdown();
    } catch (_) {}
    exit(0);
  }

  Future<void> _validatePassword(String password) async {
    final cleanToken = password.trim().toUpperCase();
    if (cleanToken.isEmpty) {
      Get.snackbar(
        'Input Kosong',
        'Harap masukkan Token Keluar dari guru',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.orange.shade800,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        borderRadius: 8,
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.white),
      );
      return;
    }

    try {
      final studentName = ActivationController.getStudentName();
      final deviceId = await DeviceInfoHelper.getDeviceId();

      final result = await _activationRepo.validateToken(
        token: cleanToken,
        type: 'exit',
        studentName: studentName,
        deviceId: deviceId,
      );
      final isValid = result.success && (result.data?.valid ?? false);

      if (isValid) {
        // Tutup keyboard dan tunggu animasi dialog selesai agar tidak memicu assertion '_dependents.isEmpty'
        FocusManager.instance.primaryFocus?.unfocus();
        if (Get.isDialogOpen ?? false) {
          Get.back();
        }
        await Future.delayed(const Duration(milliseconds: 150));
        await finishExam('exit_token');
      } else {
        final message = result.message.isNotEmpty
            ? result.message
            : 'Token keluar tidak valid atau tidak ditemukan.';
        Get.snackbar(
          'Token Salah',
          message,
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.red.shade700,
          colorText: Colors.white,
          margin: const EdgeInsets.all(12),
          borderRadius: 8,
          icon: const Icon(Icons.error_outline, color: Colors.white),
          duration: const Duration(seconds: 4),
        );
      }
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      Get.snackbar(
        'Token Salah',
        msg,
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        borderRadius: 8,
        icon: const Icon(Icons.error_outline, color: Colors.white),
        duration: const Duration(seconds: 4),
      );
    }
  }

  Future<void> finishExam(String reason) async {
    if (!isExamActive.value) return;

    isExamActive.value = false;
    _timer?.cancel();

    // Pastikan keyboard dan dialog apa pun sudah tertutup dengan aman
    FocusManager.instance.primaryFocus?.unfocus();
    if (Get.isDialogOpen ?? false) {
      Get.back();
      await Future.delayed(const Duration(milliseconds: 150));
    }

    try {
      // 1. Selesaikan semua request network & data terlebih dahulu selagi layar aktif
      if (session != null) {
        try {
          await examRepo.finishExam(session!.sessionId, reason);
        } catch (e) {
          print('[ExamController] finishExam error: $e');
        }
      }

      final activationSessionId = ActivationController.getSessionId();
      if (activationSessionId != null) {
        try {
          final result = await ActivationRepository().completeActivation(activationSessionId);
          print('[ExamController] Sesi $activationSessionId berhasil diselesaikan: status=${result.status}, durasi=${result.durationSeconds} detik');
        } catch (e) {
          print('[ExamController] completeActivation info/error: $e');
        }
        try {
          await ActivationController.clearSessionId();
        } catch (_) {}
      }

      // 2. Hentikan background monitoring & release WebView
      try {
        await antiCheatService.stopMonitoring();
      } catch (_) {}
      try {
        await webViewService.disposeWebView();
      } catch (_) {}

      // 3. Pindah rute ke SETUP_URL terlebih dahulu secara bersih
      // agar rendering tree sudah berada di halaman awal sebelum layar dikunci oleh OS
      Get.offAllNamed(AppRoutes.SETUP_URL);

      // 4. Setelah halaman SETUP_URL terpasang di frame, baru unpin & lepaskan lockdown
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future.delayed(const Duration(milliseconds: 300));
        await lockdownService.disableLockdown();
      });
    } catch (e) {
      print('Finish exam error: $e');
      Get.offAllNamed(AppRoutes.SETUP_URL);
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future.delayed(const Duration(milliseconds: 300));
        await lockdownService.disableLockdown();
      });
    }
  }

  @override
  void onClose() {
    _timer?.cancel();
    try {
      pinController.dispose();
    } catch (_) {}
    try {
      lockdownService.onSecurityViolation = null;
    } catch (_) {}
    super.onClose();
  }
}
