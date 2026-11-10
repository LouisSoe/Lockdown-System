import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lockdown_engine/app/routes/app_routes.dart';
import 'package:lockdown_engine/core/utils/uppercase_text_formatter.dart';
import 'package:lockdown_engine/modules/setup/controllers/setup_controller.dart';
import 'package:lockdown_engine/modules/exam/views/wifi_dialog.dart';

class SetupUrlView extends GetView<SetupController> {
  const SetupUrlView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: () => controller.openAdminMenu(),
          child: const Text('Lockdown CBT'),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.checklist_rounded),
            tooltip: 'Kesiapan Perangkat (Preflight)',
            onPressed: () => Get.toNamed(AppRoutes.PREFLIGHT),
          ),
          IconButton(
            icon: const Icon(Icons.wifi),
            tooltip: 'Ganti Wi-Fi / Cek Jaringan',
            onPressed: () => WifiDialog.show(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Branding
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () => controller.onShieldTapped(),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.blue.shade200, width: 2),
                        ),
                        child: Icon(
                          Icons.shield_rounded,
                          size: 48,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Masuk Ujian CBT',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Masukkan nama lengkap dan token aktivasi dari guru Anda.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Form Input Nama & Token
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                    // Input Nama Siswa
                    Obx(() => TextField(
                          controller: controller.studentNameController,
                          enabled: !controller.isLoading.value,
                          autocorrect: false,
                          enableSuggestions: false,
                          textCapitalization: TextCapitalization.words,
                          keyboardType: TextInputType.name,
                          textInputAction: TextInputAction.next,
                          scrollPadding: const EdgeInsets.only(bottom: 120.0, top: 20.0),
                          decoration: const InputDecoration(
                            labelText: 'Nama Lengkap Siswa',
                            hintText: 'Contoh: Ahmad Fauzi',
                            prefixIcon: Icon(Icons.person_outline),
                            border: OutlineInputBorder(),
                          ),
                        )),

                    const SizedBox(height: 16),

                    // Input Token
                    Obx(() => TextField(
                          controller: controller.tokenController,
                          enabled: !controller.isLoading.value,
                          autocorrect: false,
                          enableSuggestions: false,
                          textCapitalization: TextCapitalization.characters,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.done,
                          scrollPadding: const EdgeInsets.only(bottom: 120.0, top: 20.0),
                          inputFormatters: [
                            UpperCaseTextFormatter(),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Token Aktivasi',
                            hintText: 'Contoh: AK3QH9J2M8VX4Y7BR5C6D1E0F...',
                            prefixIcon: Icon(Icons.vpn_key_outlined),
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => controller.verifyAndStartExam(),
                        )),

                    // Box Pesan Error
                    Obx(() {
                      if (controller.errorMessage.value.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Container(
                        margin: const EdgeInsets.only(top: 14),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.error_outline, size: 20, color: Colors.red.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                controller.errorMessage.value,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.red.shade900,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                    const SizedBox(height: 18),

                    // Tombol Mulai Ujian
                    Obx(() => ElevatedButton(
                          onPressed: controller.isLoading.value ? null : controller.verifyAndStartExam,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.blue.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: controller.isLoading.value
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text(
                                  'Mulai Ujian',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                        )),
                  ],
                ),

              const SizedBox(height: 24),

              // Card Informasi Keamanan Lockdown
              Card(
                elevation: 0,
                color: Colors.grey.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Proteksi Ujian Aktif',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      _buildFeatureItem(Icons.fullscreen, 'Layar Penuh Otomatis'),
                      _buildFeatureItem(Icons.block, 'Blokir Pindah Aplikasi (App Pinning)'),
                      _buildFeatureItem(Icons.keyboard_hide, 'Blokir Pintasan Tombol Navigasi'),
                      _buildFeatureItem(Icons.content_paste_off, 'Blokir Copy / Paste'),
                      _buildFeatureItem(Icons.security, 'Kiosk Security Mode'),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Peringatan Keamanan
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 20, color: Colors.amber.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Setelah ujian dimulai, perangkat akan terkunci dalam mode ujian. Anda tidak dapat keluar tanpa password dari guru/pengawas.',
                        style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.green.shade700, size: 16),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
