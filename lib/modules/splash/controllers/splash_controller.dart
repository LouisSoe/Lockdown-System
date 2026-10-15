import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:lockdown_engine/app/routes/app_routes.dart';
import 'package:lockdown_engine/modules/activation/controllers/activation_controller.dart';

class SplashController extends GetxController {
  @override
  void onReady() {
    super.onReady();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      print('[SplashController] Starting initialization...');

      // Delay 1.5 detik untuk branding
      await Future.delayed(const Duration(milliseconds: 1500));

      // Cek token di local storage
      final tokenValid = ActivationController.isTokenValid();
      print('[SplashController] Token valid: $tokenValid');

      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.offAllNamed(AppRoutes.SETUP_URL);
      });
    } catch (e, stack) {
      print('[SplashController] ERROR during initialization: $e');
      print('[SplashController] Stack: $stack');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.offAllNamed(AppRoutes.SETUP_URL);
      });
    }
  }
}
