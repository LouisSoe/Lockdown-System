import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:lockdown_engine/services/webview/webview_service.dart';
import 'package:lockdown_engine/services/webview/javascript_bridge_service.dart';
import 'package:lockdown_engine/services/lockdown/lockdown_service.dart';
import 'package:lockdown_engine/services/anticheat/anticheat_service.dart';
import 'package:lockdown_engine/services/screen_share/screen_share_service.dart';
import 'package:lockdown_engine/core/utils/device_info_helper.dart';
import 'package:lockdown_engine/data/repositories/exam_repository.dart';
import 'package:lockdown_engine/data/models/exam_session_model.dart';
import 'package:lockdown_engine/data/repositories/activation_repository.dart';
import 'package:lockdown_engine/modules/activation/controllers/activation_controller.dart';
import 'package:lockdown_engine/app/routes/app_routes.dart';

class ExamController extends GetxController {
  late String examUrl;
  ExamSessionModel? session;

  late WebViewService webViewService;
  late JavaScriptBridgeService jsBridge;
  late LockdownService lockdownService;
  late AntiCheatService antiCheatService;
  late ScreenShareService screenShareService;
  final examRepo = ExamRepository();

  final remainingTime = '00:00:00'.obs;
  final isExamActive = true.obs;
  Timer? _timer;
  DateTime? _endTime;

  @override
  void onInit() {
    super.onInit();

    final args = Get.arguments as Map<String, dynamic>?;
    examUrl = args?['exam_url'] ?? 'https://example.com';
    session = args?['session'];

    // Initialize services
    webViewService = Get.find<WebViewService>();
    jsBridge = Get.find<JavaScriptBridgeService>();
    lockdownService = Get.find<LockdownService>();
    antiCheatService = Get.find<AntiCheatService>();
    screenShareService = Get.find<ScreenShareService>();

    // Register JavaScript handlers
    _registerJavaScriptHandlers();

    // Enable lockdown and start monitoring
    _initializeLockdown();

    // Start timer using activation token expiration or session duration
    _startTimer();
  }

  Future<void> _initializeLockdown() async {
    try {
      // Enable lockdown mode
      await lockdownService.enableLockdown();

      // Start anti-cheat monitoring
      if (session != null) {
        await antiCheatService.startMonitoring(session!.sessionId);
      }

      // Start screen share
      await _startScreenShare();

      print('✓ Lockdown, monitoring, and screen share initialized');
    } catch (e) {
      print('✗ Lockdown initialization error: $e');
      Get.snackbar(
        'Warning',
        'Some security features may not be active',
        snackPosition: SnackPosition.TOP,
      );
    }
  }

  Future<void> _startScreenShare() async {
    try {
      final sessionId = session?.sessionId ?? 'no-session';
      final deviceId = await DeviceInfoHelper.getDeviceId();
      await screenShareService.startSharing(
        sessionId: sessionId,
        deviceId: deviceId,
      );
    } catch (e) {
      // Screen share gagal tidak boleh block exam — log saja
      print('[ExamController] Screen share start error: $e');
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Masukkan password pengawas untuk mengakhiri ujian:',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password Pengawas',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                  isDense: true,
                ),
                onSubmitted: (value) => _validatePassword(value),
              ),
            ],
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
            child: const Text('Keluar'),
          ),
        ],
      ),
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 150),
      transitionCurve: Curves.easeOutCubic,
    );
    passwordController.dispose();
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
      await screenShareService.stopSharing();
      await antiCheatService.stopMonitoring();
      await lockdownService.disableLockdown();
    } catch (_) {}
    exit(0);
  }

  Future<void> _validatePassword(String password) async {
    if (password.isEmpty) {
      Get.snackbar('Error', 'Please enter password');
      return;
    }

    try {
      // Master dummy password for debugging/testing
      if (password == '123456') {
        Get.back();
        finishExam('forced_exit');
        return;
      }

      if (session != null) {
        final result = await examRepo.validateExitPassword(
          session!.sessionId,
          password,
        );

        if (result.isValid) {
          Get.back();
          finishExam('forced_exit');
        } else {
          Get.snackbar('Error', 'Invalid password');
        }
      } else {
        // Testing mode without session
        if (password == 'admin') {
          Get.back();
          finishExam('forced_exit');
        } else {
          Get.snackbar('Error', 'Invalid password');
        }
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to validate password: $e');
    }
  }

  Future<void> finishExam(String reason) async {
    if (!isExamActive.value) return;

    isExamActive.value = false;
    _timer?.cancel();

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
        await screenShareService.stopSharing();
      } catch (_) {}
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
    super.onClose();
  }
}
