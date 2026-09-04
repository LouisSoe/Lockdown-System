import 'package:get/get.dart';
import 'package:lockdown_engine/app/routes/app_routes.dart';

class SplashController extends GetxController {
  @override
  void onInit() {
    super.onInit();
    _initialize();
  }
  
  Future<void> _initialize() async {
    await Future.delayed(const Duration(seconds: 2));
    
    // Navigate to setup
    Get.offNamed(AppRoutes.SETUP_URL);
  }
}
