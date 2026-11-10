import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:lockdown_engine/core/utils/uppercase_text_formatter.dart';
import 'package:lockdown_engine/kiosk/exam_gate.dart';
import 'package:lockdown_engine/modules/exam/controllers/exam_controller.dart';
import 'package:lockdown_engine/modules/exam/views/wifi_dialog.dart';

class ExamView extends GetView<ExamController> {
  const ExamView({super.key});

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyX, control: true): () {
          controller.showForceCloseConfirmationDialog();
        },
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              controller.showExitDialog();
            }
          },
          child: ExamGate(
            kiosk: controller.lockdownService.kioskController,
            child: Scaffold(
              resizeToAvoidBottomInset: true,
              body: Column(
                children: [
                  _buildStatusBar(context),
                Expanded(
                  child: Stack(
                    children: [
                        InAppWebView(
                          initialUrlRequest: URLRequest(
                            url: WebUri(controller.examUrl),
                          ),
                          initialSettings:
                              controller.webViewService.getSettings(),
                          onWebViewCreated: controller.onWebViewCreated,
                          onLoadStart:
                              controller.webViewService.handleLoadStart,
                          onLoadStop: controller.webViewService.handleLoadStop,
                          onProgressChanged:
                              controller.webViewService.handleProgressChanged,
                          onLoadError: controller.webViewService.handleLoadError,
                          shouldOverrideUrlLoading:
                              (ctrl, navigationAction) async {
                            return controller.webViewService
                                .shouldOverrideUrlLoading(navigationAction);
                          },
                          onDownloadStartRequest: (ctrl, request) {
                            controller.webViewService
                                .handleDownloadStart(request);
                          },
                          onCreateWindow: (ctrl, createWindowAction) async {
                            return controller.webViewService
                                .handleCreateWindow(createWindowAction);
                          },
                          onConsoleMessage: (ctrl, consoleMessage) {
                            controller.webViewService
                                .handleConsoleMessage(consoleMessage);
                          },
                        ),
                        Obx(() => controller.webViewService.isLoading.value
                            ? Container(
                                color: Colors.white,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const CircularProgressIndicator(),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Loading exam...',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge,
                                      ),
                                      const SizedBox(height: 8),
                                      Obx(() => LinearProgressIndicator(
                                            value: controller.webViewService
                                                .loadProgress.value,
                                          )),
                                    ],
                                  ),
                                ),
                              )
                            : const SizedBox.shrink()),
                        // Overlay saat gagal memuat halaman / offline
                        Obx(() {
                          if (!controller.webViewService.hasLoadError.value) {
                            return const SizedBox.shrink();
                          }
                          return Container(
                            color: Colors.white,
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 480),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(18),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.red.shade200, width: 2),
                                      ),
                                      child: Icon(Icons.wifi_off_rounded, size: 52, color: Colors.red.shade600),
                                    ),
                                    const SizedBox(height: 18),
                                    const Text(
                                      'Tidak Dapat Memuat Halaman Ujian',
                                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Koneksi internet terputus atau tidak stabil.\nSilakan ganti jaringan Wi-Fi atau muat ulang halaman setelah internet normal.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
                                    ),
                                    const SizedBox(height: 22),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 12,
                                      alignment: WrapAlignment.center,
                                      children: [
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.wifi_find_rounded, size: 18),
                                          label: const Text('Ganti Jaringan Wi-Fi', style: TextStyle(fontWeight: FontWeight.bold)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.blue.shade700,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          onPressed: () {
                                            WifiDialog.show(onConnected: () {
                                              controller.webViewService.reload();
                                            });
                                          },
                                        ),
                                        OutlinedButton.icon(
                                          icon: const Icon(Icons.refresh, size: 18),
                                          label: const Text('Coba Muat Ulang'),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          onPressed: () => controller.webViewService.reload(),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                        // Overlay Peringatan Pelanggaran Toleransi (Strict CBT Policy)
                        Obx(() {
                          if (!controller.showWarningModal.value ||
                              controller.isLockedOut.value ||
                              controller.isBlocked.value) {
                            return const SizedBox.shrink();
                          }
                          return _buildViolationWarningOverlay(context);
                        }),
                        // Lockout / Blocked Overlay untuk Strict CBT Policy
                        Obx(() {
                          if (!controller.isLockedOut.value && !controller.isBlocked.value) {
                            return const SizedBox.shrink();
                          }
                          return _buildLockoutOverlay(context);
                        }),
                      ],
                    ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }

  Widget _buildStatusBar(BuildContext context) {
    return Container(
      height: 48,
      color: Colors.blue.shade800,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Icon gembok dengan Tooltip & info saat diklik
          Tooltip(
            message: 'Mode Lockdown Aktif: Navigasi dan aplikasi lain dibatasi selama ujian.',
            triggerMode: TooltipTriggerMode.tap,
            preferBelow: true,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.lock_rounded, color: Colors.white, size: 20),
              tooltip: 'Mode Lockdown Aktif',
              onPressed: () {
                Get.snackbar(
                  'Mode Lockdown Aktif',
                  'Navigasi dan aplikasi luar dibatasi selama ujian berlangsung.',
                  snackPosition: SnackPosition.TOP,
                  backgroundColor: Colors.black87,
                  colorText: Colors.white,
                  duration: const Duration(seconds: 2),
                  margin: const EdgeInsets.all(12),
                  borderRadius: 8,
                  icon: const Icon(Icons.shield_rounded, color: Colors.blueAccent),
                );
              },
            ),
          ),
          const SizedBox(width: 4),

          // Waktu tersisa di sebelah kunci
          const Icon(Icons.timer_outlined, color: Colors.white70, size: 16),
          const SizedBox(width: 4),
          Obx(() => Text(
                controller.remainingTime.value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              )),

          const Spacer(),

          // Aksi sebelah kanan: Ubah Wi-Fi, Reload, Exit
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(Icons.wifi, color: Colors.white, size: 20),
            onPressed: () {
              WifiDialog.show(onConnected: () {
                controller.webViewService.reload();
              });
            },
            tooltip: 'Ganti Wi-Fi / Cek Jaringan',
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
            onPressed: () => controller.webViewService.reload(),
            tooltip: 'Muat Ulang Halaman (Reload)',
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(Icons.exit_to_app_rounded, color: Colors.white, size: 20),
            onPressed: controller.showExitDialog,
            tooltip: 'Keluar Ujian',
          ),
        ],
      ),
    );
  }

  Widget _buildLockoutOverlay(BuildContext context) {
    return Obx(() {
      final isBlocked = controller.isBlocked.value;
      final violationCount = controller.violationCount.value;
      final maxViolations = controller.maxViolations.value;
      final remaining = maxViolations - violationCount;

      return Scaffold(
        backgroundColor: Colors.black.withValues(alpha: 0.95),
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                color: const Color(0xFF1E1E2C),
                elevation: 16,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: Colors.red.shade700, width: 2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Icon Lockout / Blocked
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade900.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.red.shade600, width: 2),
                        ),
                        child: Icon(
                          isBlocked ? Icons.block_rounded : Icons.lock_person_rounded,
                          size: 56,
                          color: Colors.red.shade400,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Title
                      Text(
                        isBlocked ? 'UJIAN DIBLOKIR' : 'UJIAN TERKUNCI',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Badge Pelanggaran
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.red.shade900.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.red.shade500),
                        ),
                        child: Text(
                          isBlocked
                              ? 'Batas Pelanggaran Terlampaui: $violationCount/$maxViolations kali'
                              : 'Pelanggaran Terdeteksi: Ke-$violationCount dari $maxViolations kali',
                          style: TextStyle(
                            color: Colors.red.shade200,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (isBlocked) ...[
                        // Pesan Ujian Diblokir Permanen
                        Text(
                          'Anda telah melakukan pelanggaran ke-$violationCount kali, yang melebihi batas toleransi maksimal ($maxViolations kali) yang ditentukan oleh guru.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade300,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Sesuai ketentuan, sesi ujian Anda telah DIBLOKIR secara permanen dan Anda tidak dapat melanjutkan ujian ini.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade300,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Silakan hubungi guru / pengawas ujian untuk keluar dari sesi ujian.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade400,
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.exit_to_app_rounded, size: 18),
                            label: const Text(
                              'Keluar Ujian',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade800,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () => controller.showExitDialog(),
                          ),
                        ),
                      ] else ...[
                        // Pesan Terkunci Menunggu Token Pelanggaran
                        Text(
                          'Sistem mendeteksi bahwa Anda telah keluar dari aplikasi atau memindahkan fokus layar ujian.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade300,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Setiap pelanggaran mewajibkan Anda memasukkan Token Pelanggaran dari guru untuk membuka kunci lembar ujian.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.amber.shade300,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            remaining > 0
                                ? 'SISA KESEMPATAN BUKA KUNCI: $remaining KALI LAGI'
                                : 'PERINGATAN TERAKHIR: Pelanggaran ke-${violationCount + 1} akan LANGSUNG MEMBLOKIR UJIAN!',
                            style: TextStyle(
                              color: remaining > 0 ? Colors.amber.shade300 : Colors.redAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Form Token Pelanggaran
                        TextField(
                          controller: controller.pinController,
                          textCapitalization: TextCapitalization.characters,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.text,
                          scrollPadding: const EdgeInsets.only(bottom: 120.0, top: 20.0),
                          inputFormatters: [
                            UpperCaseTextFormatter(),
                          ],
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Token Pelanggaran (Violation Token)',
                            labelStyle: TextStyle(color: Colors.grey.shade400),
                            hintText: 'Masukkan token 6 digit dari guru...',
                            hintStyle: TextStyle(color: Colors.grey.shade600),
                            prefixIcon: const Icon(Icons.vpn_key_rounded, color: Colors.amber),
                            filled: true,
                            fillColor: Colors.black26,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.grey.shade700),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.grey.shade700),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.red.shade400),
                            ),
                          ),
                          onSubmitted: (val) => controller.unlockBySupervisor(val),
                        ),
                        const SizedBox(height: 16),

                        // Tombol Buka Kunci
                        Obx(() => SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: controller.isUnlocking.value
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.key_rounded, size: 18),
                                label: Text(
                                  controller.isUnlocking.value ? 'Memverifikasi...' : 'Buka Kunci Ujian',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade700,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  elevation: 4,
                                ),
                                onPressed: controller.isUnlocking.value
                                    ? null
                                    : () => controller.unlockBySupervisor(controller.pinController.text),
                              ),
                            )),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    });
  }

  Widget _buildViolationWarningOverlay(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              color: const Color(0xFF1E1E2C),
              elevation: 20,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.amber.shade600, width: 2),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Warning Icon
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade900.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.amber.shade600, width: 2),
                      ),
                      child: Icon(
                        Icons.warning_amber_rounded,
                        size: 48,
                        color: Colors.amber.shade400,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Title
                    const Text(
                      'PERINGATAN PELANGGARAN!',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Description text
                    Text(
                      'Anda terdeteksi keluar dari aplikasi ujian atau membuka bilah notifikasi.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade300,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Status Toleransi Card
                    Obx(() {
                      final count = controller.violationCount.value;
                      final max = controller.maxViolations.value;
                      final hasLimit = controller.hasViolationLimit.value;
                      final remaining = max - count;
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.red.shade900.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade500.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.shield_outlined, color: Colors.amber.shade400, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  hasLimit
                                      ? 'Peringatan ke-$count dari $max'
                                      : 'Peringatan Pelanggaran ke-$count',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              hasLimit
                                  ? (remaining > 0
                                      ? 'Sisa toleransi: $remaining kali lagi sebelum ujian terkunci otomatis.'
                                      : 'Batas toleransi telah terlampaui.')
                                  : 'Batas pelanggaran dinonaktifkan oleh guru. Harap tetap fokus dan tertib pada lembar ujian.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.red.shade200,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 20),

                    // Button Saya Mengerti & Lanjutkan
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text(
                          'Saya Mengerti & Lanjutkan',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 4,
                        ),
                        onPressed: () => controller.dismissWarningModal(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
