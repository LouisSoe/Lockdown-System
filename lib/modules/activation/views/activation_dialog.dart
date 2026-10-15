import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lockdown_engine/modules/activation/controllers/activation_controller.dart';

class ActivationDialog extends StatelessWidget {
  final VoidCallback? onSuccess;
  final bool allowCancel;

  const ActivationDialog({Key? key, this.onSuccess, this.allowCancel = false}) : super(key: key);

  /// Tampilkan dialog aktivasi. Tidak bisa di-dismiss tanpa token valid.
  static Future<void> show({VoidCallback? onSuccess, bool allowCancel = false}) {
    Get.put(ActivationController());
    return Get.dialog(
      ActivationDialog(onSuccess: onSuccess, allowCancel: allowCancel),
      barrierDismissible: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ActivationController>();

    return PopScope(
      canPop: allowCancel,
      onPopInvoked: (didPop) {
        if (didPop) Get.back();
      },
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(Icons.vpn_key_rounded, color: Colors.blue.shade700, size: 24),
            const SizedBox(width: 8),
            const Text(
              'Aktivasi Token',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Masukkan nama lengkap dan token aktivasi yang diberikan oleh guru untuk mengakses ujian.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              // Input Nama Siswa
              Obx(() => TextField(
                    controller: controller.studentNameController,
                    enabled: !controller.isLoading.value,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nama Siswa',
                      hintText: 'Contoh: Ahmad Fauzi',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                  )),
              const SizedBox(height: 12),
              // Input Token
              Obx(() => TextField(
                    controller: controller.tokenController,
                    enabled: !controller.isLoading.value,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Token Aktivasi',
                      hintText: 'Contoh: AK3QH9J2M8VX4Y7BR5C6D1E0F...',
                      prefixIcon: Icon(Icons.vpn_key_outlined),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => controller.verify(onSuccess: onSuccess),
                  )),
              // Error Message Container
              Obx(() {
                if (controller.errorMessage.value.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, size: 18, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          controller.errorMessage.value,
                          style: TextStyle(fontSize: 12, color: Colors.red.shade900, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 12),
              // Info box
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
                        'Pastikan nama Anda sesuai dan guru telah mengaktifkan link ujian di portal web.',
                        style: TextStyle(fontSize: 11, color: Colors.blue.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (allowCancel)
            Obx(() => SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: controller.isLoading.value ? null : () => Get.back(),
                    child: const Text('Batal'),
                  ),
                )),
          Obx(() => SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: controller.isLoading.value
                      ? null
                      : () => controller.verify(onSuccess: onSuccess),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: controller.isLoading.value
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Verifikasi Token',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                ),
              )),
        ],
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }
}
