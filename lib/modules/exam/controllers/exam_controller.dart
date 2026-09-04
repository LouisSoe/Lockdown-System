import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:lockdown_engine/services/webview/webview_service.dart';
import 'package:lockdown_engine/services/webview/javascript_bridge_service.dart';
import 'package:lockdown_engine/services/lockdown/lockdown_service.dart';
import 'package:lockdown_engine/services/anticheat/anticheat_service.dart';
import 'package:lockdown_engine/data/repositories/exam_repository.dart';
import 'package:lockdown_engine/data/models/exam_session_model.dart';
import 'package:lockdown_engine/app/routes/app_routes.dart';

class ExamController extends GetxController {
  late String examUrl;
  ExamSessionModel? session;
  
  late WebViewService webViewService;
  late JavaScriptBridgeService jsBridge;
  late LockdownService lockdownService;
  late AntiCheatService antiCheatService;
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
    
    // Register JavaScript handlers
    _registerJavaScriptHandlers();
    
    // Enable lockdown and start monitoring
    _initializeLockdown();
    
    // Start timer if session has duration
    if (session != null) {
      _startTimer();
    }
  }
  
  Future<void> _initializeLockdown() async {
    try {
      // Enable lockdown mode
      await lockdownService.enableLockdown();
      
      // Start anti-cheat monitoring
      if (session != null) {
        await antiCheatService.startMonitoring(session!.sessionId);
      }
      
      print('✓ Lockdown and monitoring initialized');
    } catch (e) {
      print('✗ Lockdown initialization error: $e');
      Get.snackbar(
        'Warning',
        'Some security features may not be active',
        snackPosition: SnackPosition.TOP,
      );
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
    if (session == null) return;
    
    _endTime = session!.startTime.add(
      Duration(minutes: session!.duration),
    );
    
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_endTime == null) return;
      
      final now = DateTime.now();
      final remaining = _endTime!.difference(now);
      
      if (remaining.isNegative) {
        finishExam('timeout');
      } else {
        final hours = remaining.inHours.toString().padLeft(2, '0');
        final minutes = (remaining.inMinutes % 60).toString().padLeft(2, '0');
        final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');
        remainingTime.value = '$hours:$minutes:$seconds';
      }
    });
  }
  
  void onWebViewCreated(InAppWebViewController controller) {
    webViewService.webViewController = controller;
    jsBridge.setController(controller);
  }
  
  Future<void> showExitDialog() async {
    final passwordController = TextEditingController();
    
    await Get.dialog(
      AlertDialog(
        title: const Text('Exit Exam'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter administrator password to exit:'),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
              onSubmitted: (value) => _validatePassword(value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => _validatePassword(passwordController.text),
            child: const Text('Exit'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }
  
  Future<void> _validatePassword(String password) async {
    if (password.isEmpty) {
      Get.snackbar('Error', 'Please enter password');
      return;
    }
    
    try {
      // For now, allow any password for testing
      // Later integrate with server validation
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
        if (password == 'admin' || password == '123456') {
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
      // Stop monitoring and disable lockdown
      await antiCheatService.stopMonitoring();
      await lockdownService.disableLockdown();
      
      if (session != null) {
        await examRepo.finishExam(session!.sessionId, reason);
      }
      
      // Show completion message
      String message = '';
      switch (reason) {
        case 'completed':
          message = 'Exam completed successfully!';
          break;
        case 'timeout':
          message = 'Time is up!';
          break;
        case 'forced_exit':
          message = 'Exam exited by administrator';
          break;
      }
      
      Get.snackbar('Exam Finished', message);
      
      // Navigate back to setup
      await Future.delayed(const Duration(seconds: 2));
      Get.offAllNamed(AppRoutes.SETUP_URL);
    } catch (e) {
      print('Finish exam error: $e');
      Get.offAllNamed(AppRoutes.SETUP_URL);
    }
  }
  
  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }
}
