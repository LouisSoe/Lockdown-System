import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lockdown_engine/core/utils/device_info_helper.dart';
import 'package:lockdown_engine/core/utils/uppercase_text_formatter.dart';
import 'package:lockdown_engine/data/repositories/activation_repository.dart';
import 'package:lockdown_engine/modules/activation/controllers/activation_controller.dart';
import 'package:lockdown_engine/modules/exam/controllers/exam_controller.dart';

import 'kiosk_controller.dart';

class ExamGate extends StatelessWidget {
  const ExamGate({super.key, required this.kiosk, required this.child});

  final KioskController kiosk;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return child;
    }

    return ListenableBuilder(
      listenable: kiosk,
      builder: (context, _) {
        final s = kiosk.status;
        final open = s.gateOpen;
        // JANGAN blokir tampilan jika sesi ujian native belum aktif dan bukan dalam kondisi lockout / blocked.
        // Biarkan child (WebView dengan loading spinner) merender halaman persiapan secara mulus.
        final shouldBlock = (!open && s.active) || s.isLockedOut || s.isBlocked;

        return Stack(
          fit: StackFit.expand,
          children: [
            Offstage(offstage: shouldBlock, child: child),
            if (shouldBlock) _BlockedView(kiosk: kiosk),
          ],
        );
      },
    );
  }
}

const _labels = <String, String>{
  'guard': 'Layanan Penjaga Ujian mati',
  'overlay': 'Izin tampil di atas aplikasi lain dicabut',
  'battery': 'Optimasi baterai aktif kembali',
  'notif': 'Izin notifikasi dicabut',
  'pinned': 'Penyematan layar (pin) tidak aktif',
  'focus': 'Aplikasi ujian tidak berada di depan',
  'singleWindow': 'Layar terbagi atau jendela mengambang aktif',
  'foreignApp': 'Aplikasi lain terdeteksi di depan',
};

class _BlockedView extends StatefulWidget {
  const _BlockedView({required this.kiosk});
  final KioskController kiosk;

  @override
  State<_BlockedView> createState() => _BlockedViewState();
}

class _BlockedViewState extends State<_BlockedView> {
  final _pinController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Hanya auto-pin saat inisialisasi awal (jika belum ada pelanggaran sama sekali).
    // Jika sudah ada pelanggaran (violations > 0), JANGAN panggil requestPin otomatis!
    // Siswa HARUS melihat kartu peringatan pelanggaran dan menekan tombol 'Saya Mengerti, Pasang Pin Kembali'.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.kiosk.status.pinned &&
          !widget.kiosk.status.isLockedOut &&
          !widget.kiosk.status.isBlocked &&
          widget.kiosk.status.violations == 0) {
        widget.kiosk.requestPin();
      }
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _handleUnlock() async {
    final code = _pinController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorMessage = 'Harap masukkan Token Pelanggaran dari guru.');
      Get.snackbar(
        'Input Kosong',
        'Harap masukkan Token Pelanggaran dari guru',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.orange.shade800,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        borderRadius: 8,
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.white),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      bool isValid = false;
      final cleanCode = code.toUpperCase();
      String? failureMessage;

      // Validasi via endpoint POST /tokens/validate (type: "violation")
      try {
        final repo = ActivationRepository();
        final studentName = ActivationController.getStudentName();
        final deviceId = await DeviceInfoHelper.getDeviceId();

        final result = await repo.validateToken(
          token: cleanCode,
          type: 'violation',
          studentName: studentName,
          deviceId: deviceId,
        );
        isValid = result.success && (result.data?.valid ?? false);
        if (!isValid) {
          failureMessage = result.message.isNotEmpty
              ? result.message
              : 'Token pelanggaran tidak valid atau tidak ditemukan.';
        }
      } catch (e) {
        failureMessage = e.toString().replaceFirst('Exception: ', '');
      }

      if (isValid) {
        final success = await widget.kiosk.unlockExam(cleanCode);
        if (success) {
          _pinController.clear();
          if (Get.isRegistered<ExamController>()) {
            final examCtrl = Get.find<ExamController>();
            examCtrl.antiCheatService.focusMonitor.extendGracePeriod(seconds: 8);
            examCtrl.isLockedOut.value = false;
            examCtrl.showWarningModal.value = false;
            examCtrl.pinController.clear();
          }
          await widget.kiosk.requestPin();
          Get.snackbar(
            'Ujian Dibuka Kembali',
            'Token valid. Kunci lembar ujian telah dibuka.',
            backgroundColor: Colors.green.shade700,
            colorText: Colors.white,
            snackPosition: SnackPosition.TOP,
            margin: const EdgeInsets.all(12),
            borderRadius: 8,
            icon: const Icon(Icons.check_circle_outline, color: Colors.white),
            duration: const Duration(seconds: 4),
          );
          return;
        }
      }

      final displayMsg = failureMessage ?? 'Token pelanggaran tidak valid atau sudah kedaluwarsa.';
      if (mounted) {
        setState(() {
          _errorMessage = displayMsg;
        });
      }

      Get.snackbar(
        'Token Salah',
        displayMsg,
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP,
        margin: const EdgeInsets.all(12),
        borderRadius: 8,
        icon: const Icon(Icons.error_outline, color: Colors.white),
        duration: const Duration(seconds: 4),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.kiosk.status;
    final isBlocked = s.isBlocked;
    final isLockedOut = s.isLockedOut && s.hasViolationLimit && !isBlocked;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    isBlocked
                        ? Icons.block_rounded
                        : (isLockedOut
                            ? Icons.lock_person_rounded
                            : (s.violations > 0 ? Icons.warning_amber_rounded : Icons.lock)),
                    color: isBlocked
                        ? Colors.redAccent
                        : (isLockedOut
                            ? Colors.redAccent
                            : (s.violations > 0 ? Colors.orangeAccent : Colors.amber)),
                    size: 56,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isBlocked
                        ? 'UJIAN DIBLOKIR'
                        : (isLockedOut
                            ? 'UJIAN TERKUNCI'
                            : (s.violations > 0 ? 'PERINGATAN PELANGGARAN!' : 'Ujian Dijeda')),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: (isBlocked || isLockedOut)
                          ? Colors.redAccent
                          : (s.violations > 0 ? Colors.orangeAccent : Colors.white),
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (isBlocked) ...[
                    // Tampilan ketika siswa melanggar melebihi batas maksimal (LANGSUNG DIBLOCK)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade700, width: 2),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.gpp_bad_rounded, color: Colors.red.shade300, size: 24),
                              const SizedBox(width: 8),
                              const Text(
                                'AKSES UJIAN DIHENTIKAN',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Anda telah melakukan pelanggaran ke-${s.violations} yang melebihi batas maksimal ${s.maxViolations} kali toleransi ujian.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Sesuai ketentuan ujian, sesi Anda telah DIBLOKIR secara permanen dan Anda tidak dapat melanjutkan ujian ini.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Silakan panggil guru / pengawas ujian untuk mengakhiri sesi pengerjaan ini.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () {
                        if (Get.isRegistered<ExamController>()) {
                          Get.find<ExamController>().finishExam('blocked_max_violations');
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade800,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.exit_to_app_rounded, size: 20),
                      label: const Text(
                        'Keluar Ujian',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () {
                        if (Get.isRegistered<ExamController>()) {
                          Get.find<ExamController>().showForceCloseConfirmationDialog();
                        }
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white54,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      icon: const Icon(Icons.power_settings_new_rounded, size: 16),
                      label: const Text(
                        'Keluar Paksa Aplikasi (Force Close)',
                        style: TextStyle(fontSize: 12, decoration: TextDecoration.underline),
                      ),
                    ),
                  ] else if (isLockedOut) ...[
                    // Tampilan ketika terjadi pelanggaran (WAJIB ISI TOKEN PELANGGARAN)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade700),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Pelanggaran ke-${s.violations} dari batas ${s.maxViolations} kali toleransi.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Layar terkunci otomatis. Setiap pelanggaran mewajibkan Anda memasukkan Token Pelanggaran dari guru untuk membuka kunci lembar ujian.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              (s.maxViolations - s.violations > 0)
                                  ? 'SISA KESEMPATAN BUKA KUNCI: ${s.maxViolations - s.violations} KALI LAGI'
                                  : 'PERINGATAN TERAKHIR: Pelanggaran ke-${s.violations + 1} akan LANGSUNG MEMBLOKIR UJIAN!',
                              style: TextStyle(
                                color: (s.maxViolations - s.violations > 0)
                                    ? Colors.amber.shade300
                                    : Colors.redAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _pinController,
                      textCapitalization: TextCapitalization.characters,
                      obscureText: false,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.text,
                      scrollPadding: const EdgeInsets.only(bottom: 120.0, top: 20.0),
                      inputFormatters: [
                        UpperCaseTextFormatter(),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Token Pelanggaran (Violation Token)',
                        labelStyle: const TextStyle(color: Colors.white70),
                        hintText: 'Masukkan token dari guru (contoh: AB23CD)...',
                        hintStyle: TextStyle(color: Colors.grey.shade600),
                        prefixIcon: const Icon(Icons.password_rounded, color: Colors.amber),
                        filled: true,
                        fillColor: Colors.grey.shade900,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade700),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.redAccent),
                        ),
                      ),
                      onSubmitted: (_) => _handleUnlock(),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _isLoading ? null : _handleUnlock,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.key_rounded),
                      label: Text(
                        _isLoading ? 'Memverifikasi...' : 'Buka Kunci Lembar Ujian',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        if (Get.isRegistered<ExamController>()) {
                          Get.find<ExamController>().showExitDialog();
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade300,
                        side: BorderSide(color: Colors.red.shade700),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.exit_to_app_rounded, size: 18),
                      label: const Text(
                        'Keluar Ujian (Minta Izin Guru)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () {
                        if (Get.isRegistered<ExamController>()) {
                          Get.find<ExamController>().showForceCloseConfirmationDialog();
                        }
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white54,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      icon: const Icon(Icons.power_settings_new_rounded, size: 16),
                      label: const Text(
                        'Keluar Paksa Aplikasi (Force Close)',
                        style: TextStyle(fontSize: 12, decoration: TextDecoration.underline),
                      ),
                    ),
                  ] else if (s.violations > 0) ...[
                    // Tampilan ketika guru mematikan batasan pelanggaran (hasViolationLimit == false)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade900.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade500, width: 2),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade300, size: 26),
                              const SizedBox(width: 8),
                              Text(
                                'PERINGATAN PELANGGARAN KE-${s.violations}!',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Anda terdeteksi melepas pin layar atau mencoba keluar dari aplikasi ujian.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.orange.shade100, fontSize: 13, height: 1.3),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Batas pelanggaran dinonaktifkan oleh guru. Harap tetap fokus dan tertib pada lembar ujian.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () async {
                        await widget.kiosk.requestPin();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.orange.shade800,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                      label: const Text(
                        'Saya Mengerti, Lanjutkan Ujian',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ] else ...[
                    // Tampilan Ujian Dijeda Normal (Persiapan Awal)
                    for (final k in s.missing)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Text(
                          _labels[k] ?? k,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ),
                    const SizedBox(height: 12),

                    if (!s.pinned) ...[
                      Center(
                        child: FilledButton.icon(
                          onPressed: widget.kiosk.requestPin,
                          icon: const Icon(Icons.pin_outlined),
                          label: const Text(
                            'Aktifkan Pin Layar',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (s.missing.contains('guard')) ...[
                      Center(
                        child: FilledButton.tonalIcon(
                          onPressed: () => widget.kiosk.openSetting(KioskSetting.guard),
                          icon: const Icon(Icons.accessibility_new_rounded),
                          label: const Text('Buka Pengaturan Penjaga Ujian'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    if (s.missing.contains('overlay')) ...[
                      Center(
                        child: FilledButton.tonalIcon(
                          onPressed: () => widget.kiosk.openSetting(KioskSetting.overlay),
                          icon: const Icon(Icons.layers_rounded),
                          label: const Text('Buka Pengaturan Tampil di Atas'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    Center(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await widget.kiosk.refresh();
                          if (!widget.kiosk.status.pinned) {
                            await widget.kiosk.requestPin();
                          }
                        },
                        icon: const Icon(Icons.refresh, color: Colors.white70, size: 18),
                        label: const Text('Muat Ulang / Periksa Status', style: TextStyle(color: Colors.white70)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white30),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  const Text(
                    'Waktu ujian tetap berjalan. Hubungi pengawas bila masalah berlanjut.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 60),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
