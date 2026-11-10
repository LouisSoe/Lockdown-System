import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lockdown_engine/app/routes/app_routes.dart';
import 'package:lockdown_engine/kiosk/preflight_page.dart';
import 'package:lockdown_engine/modules/activation/controllers/activation_controller.dart';
import 'package:lockdown_engine/services/lockdown/lockdown_service.dart';

class PreflightView extends StatelessWidget {
  const PreflightView({super.key});

  @override
  Widget build(BuildContext context) {
    final lockdownService = Get.find<LockdownService>();
    final args = Map<String, dynamic>.from(Get.arguments as Map<String, dynamic>? ?? {});

    final examUrl = (args['exam_url'] as String?)?.trim().isNotEmpty == true
        ? (args['exam_url'] as String).trim()
        : (ActivationController.getRedirectUrl()?.trim().isNotEmpty == true
            ? ActivationController.getRedirectUrl()!.trim()
            : null);

    final hasExamUrl = examUrl != null && examUrl.isNotEmpty;

    return PreflightPage(
      kiosk: lockdownService.kioskController,
      buttonText: hasExamUrl ? 'Mulai Ujian' : 'Selesai & Masuk Ujian',
      onReady: () {
        if (hasExamUrl) {
          args['exam_url'] = examUrl;
          args['student_name'] ??= ActivationController.getStudentName();
          args['exam_name'] ??= ActivationController.getExamName();
          args['session_id'] ??= ActivationController.getSessionId();
          args['max_violations'] ??= ActivationController.getMaxViolations();
          args['has_violation_limit'] ??= ActivationController.getHasViolationLimit();

          Get.offNamed(
            AppRoutes.EXAM,
            arguments: args,
          );
        } else {
          Get.back();
          Get.snackbar(
            'Kesiapan Perangkat Selesai',
            'Izin perangkat sudah siap. Silakan masukkan nama dan token aktivasi untuk mulai ujian.',
            snackPosition: SnackPosition.TOP,
            backgroundColor: Colors.blue.shade700,
            colorText: Colors.white,
            icon: const Icon(Icons.check_circle_outline, color: Colors.white),
            duration: const Duration(seconds: 4),
          );
        }
      },
    );
  }
}
