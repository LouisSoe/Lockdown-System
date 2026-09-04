import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lockdown_engine/data/repositories/exam_repository.dart';
import 'package:lockdown_engine/app/routes/app_routes.dart';

class SetupController extends GetxController {
  final urlController = TextEditingController();
  final examRepo = ExamRepository();
  final isLoading = false.obs;
  
  Future<void> startExam() async {
    final url = urlController.text.trim();
    
    if (url.isEmpty) {
      Get.snackbar(
        'Error',
        'Please enter exam URL',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    
    if (!Uri.parse(url).isAbsolute) {
      Get.snackbar(
        'Error',
        'Please enter valid URL',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    
    try {
      isLoading.value = true;
      
      // For now, navigate directly to exam with the URL
      // Later we'll call API to start exam session
      Get.toNamed(
        AppRoutes.EXAM,
        arguments: {
          'exam_url': url,
        },
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to start exam: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isLoading.value = false;
    }
  }
  
  @override
  void onClose() {
    urlController.dispose();
    super.onClose();
  }
}
