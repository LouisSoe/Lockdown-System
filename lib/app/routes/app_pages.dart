import 'package:get/get.dart';
import 'package:lockdown_engine/modules/splash/views/splash_view.dart';
import 'package:lockdown_engine/modules/splash/controllers/splash_controller.dart';
import 'package:lockdown_engine/modules/setup/views/setup_url_view.dart';
import 'package:lockdown_engine/modules/setup/controllers/setup_controller.dart';
import 'package:lockdown_engine/modules/exam/views/exam_view.dart';
import 'package:lockdown_engine/modules/exam/controllers/exam_controller.dart';
import 'package:lockdown_engine/services/webview/webview_service.dart';
import 'package:lockdown_engine/services/webview/javascript_bridge_service.dart';
import 'package:lockdown_engine/services/lockdown/lockdown_service.dart';
import 'package:lockdown_engine/services/anticheat/anticheat_service.dart';
import 'app_routes.dart';

class AppPages {
  static final pages = [
    GetPage(
      name: AppRoutes.SPLASH,
      page: () => const SplashView(),
      binding: SplashBinding(),
    ),
    GetPage(
      name: AppRoutes.SETUP_URL,
      page: () => const SetupUrlView(),
      binding: SetupBinding(),
    ),
    GetPage(
      name: AppRoutes.EXAM,
      page: () => const ExamView(),
      binding: ExamBinding(),
      transition: Transition.noTransition,
    ),
  ];
}

class SplashBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => SplashController());
  }
}

class SetupBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => SetupController());
  }
}

class ExamBinding extends Bindings {
  @override
  void dependencies() {
    // Initialize all services needed for exam
    Get.put(WebViewService());
    Get.put(JavaScriptBridgeService());
    Get.put(LockdownService());
    Get.put(AntiCheatService());
    
    // Initialize exam controller
    Get.lazyPut(() => ExamController());
  }
}
