import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lockdown_engine/core/config/app_config.dart';

class AdminBaseUrlDialog extends StatefulWidget {
  const AdminBaseUrlDialog({super.key});

  static Future<void> show() async {
    await Get.dialog(
      const AdminBaseUrlDialog(),
      barrierDismissible: false,
    );
  }

  @override
  State<AdminBaseUrlDialog> createState() => _AdminBaseUrlDialogState();
}

class _AdminBaseUrlDialogState extends State<AdminBaseUrlDialog> {
  // Step: 0 = Input PIN Admin, 1 = Pengaturan Base URL Server
  int _currentStep = 0;

  // Controller PIN
  final _pinController = TextEditingController();
  bool _obscurePin = true;
  String? _pinErrorMessage;

  // Controller Base URL
  final _urlController = TextEditingController();
  bool _isTestingConnection = false;
  String? _testResult;
  bool? _isTestSuccess;

  // Ubah PIN section
  bool _showChangePin = false;
  final _newPinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _urlController.text = AppConfig.baseUrl;
  }

  @override
  void dispose() {
    _pinController.dispose();
    _urlController.dispose();
    _newPinController.dispose();
    super.dispose();
  }

  void _verifyPin() {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      setState(() => _pinErrorMessage = 'PIN Administrator tidak boleh kosong');
      return;
    }

    if (AppConfig.verifyAdminPin(pin)) {
      setState(() {
        _currentStep = 1;
        _pinErrorMessage = null;
        _urlController.text = AppConfig.baseUrl;
      });
    } else {
      setState(() {
        _pinErrorMessage = 'PIN salah. Akses ditolak.';
      });
    }
  }

  Future<void> _testConnection() async {
    final rawUrl = _urlController.text.trim();
    if (rawUrl.isEmpty) {
      setState(() {
        _isTestSuccess = false;
        _testResult = 'URL server tidak boleh kosong.';
      });
      return;
    }

    setState(() {
      _isTestingConnection = true;
      _testResult = null;
      _isTestSuccess = null;
    });

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        validateStatus: (_) => true, // Terima status apa pun (200, 404, 401, dll) asalkan terhubung
      ));

      final res = await dio.get(rawUrl);
      setState(() {
        _isTestingConnection = false;
        _isTestSuccess = true;
        _testResult = '✓ Server terhubung! (Kode HTTP: ${res.statusCode})';
      });
    } catch (e) {
      setState(() {
        _isTestingConnection = false;
        _isTestSuccess = false;
        _testResult = '✗ Gagal terhubung ke server. Periksa jaringan / URL.';
      });
    }
  }

  Future<void> _saveBaseUrl() async {
    final inputUrl = _urlController.text.trim();
    if (inputUrl.isEmpty) {
      await AppConfig.resetBaseUrlToDefault();
      Get.back();
      Get.snackbar(
        'Base URL Direset',
        'Menggunakan Base URL bawaan .env:\n${AppConfig.defaultBaseUrl}',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.blueGrey.shade800,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
      return;
    }

    if (!inputUrl.startsWith('http://') && !inputUrl.startsWith('https://')) {
      Get.snackbar(
        'Format URL Tidak Valid',
        'URL harus diawali dengan http:// atau https://',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
      );
      return;
    }

    await AppConfig.setCustomBaseUrl(inputUrl);

    // Simpan PIN baru jika diisi
    if (_showChangePin && _newPinController.text.trim().isNotEmpty) {
      await AppConfig.setAdminPin(_newPinController.text.trim());
    }

    Get.back();

    Get.snackbar(
      'Base URL Berhasil Disimpan',
      'Base URL aktif:\n${AppConfig.baseUrl}',
      snackPosition: SnackPosition.TOP,
      backgroundColor: Colors.green.shade800,
      colorText: Colors.white,
      icon: const Icon(Icons.check_circle_rounded, color: Colors.white),
      duration: const Duration(seconds: 4),
    );
  }

  Future<void> _resetToDefault() async {
    await AppConfig.resetBaseUrlToDefault();
    setState(() {
      _urlController.text = AppConfig.defaultBaseUrl;
      _testResult = null;
      _isTestSuccess = null;
    });

    Get.snackbar(
      'Reset Default',
      'Nilai form dikembalikan ke default .env',
      snackPosition: SnackPosition.TOP,
      backgroundColor: Colors.blueGrey.shade800,
      colorText: Colors.white,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 10,
      backgroundColor: Colors.white,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(22),
        child: SingleChildScrollView(
          child: _currentStep == 0 ? _buildPinStep() : _buildConfigStep(),
        ),
      ),
    );
  }

  /// Tampilan Langkah 1: Input PIN Administrator
  Widget _buildPinStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.admin_panel_settings_rounded, color: Colors.indigo.shade700, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Akses Administrator',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  Text(
                    'Konfigurasi Khusus Server CBT',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: 20, color: Colors.amber.shade900),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Halaman ini khusus pengawas/admin untuk mengatur alamat server (Base URL).',
                  style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _pinController,
          obscureText: _obscurePin,
          autofocus: true,
          keyboardType: TextInputType.text,
          decoration: InputDecoration(
            labelText: 'PIN / Sandi Administrator',
            hintText: 'Masukkan PIN admin...',
            prefixIcon: const Icon(Icons.password_rounded),
            border: const OutlineInputBorder(),
            errorText: _pinErrorMessage,
            suffixIcon: IconButton(
              icon: Icon(_obscurePin ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscurePin = !_obscurePin),
            ),
          ),
          onSubmitted: (_) => _verifyPin(),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Get.back(),
              child: const Text('Batal', style: TextStyle(color: Colors.grey)),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _verifyPin,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Masuk', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ],
    );
  }

  /// Tampilan Langkah 2: Editor Base URL Server
  Widget _buildConfigStep() {
    final isCustom = AppConfig.isUsingCustomBaseUrl;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isCustom ? Colors.orange.shade50 : Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.dns_rounded,
                color: isCustom ? Colors.orange.shade800 : Colors.blue.shade800,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Konfigurasi Base URL',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Pilih server API backend ujian',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isCustom ? Colors.orange.shade100 : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isCustom ? 'KUSTOM' : 'DEFAULT .ENV',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isCustom ? Colors.orange.shade900 : Colors.grey.shade800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Info Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Base URL Bawaan (.env):',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 2),
              SelectableText(
                AppConfig.defaultBaseUrl,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.black87),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Input Textfield Base URL
        TextField(
          controller: _urlController,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          decoration: InputDecoration(
            labelText: 'Base URL Aktif',
            hintText: 'http://192.168.1.100:8000/api',
            prefixIcon: const Icon(Icons.link_rounded),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear_rounded),
              tooltip: 'Kosongkan',
              onPressed: () => _urlController.clear(),
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Tombol Tes Koneksi & Status Hasil
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _isTestingConnection ? null : _testConnection,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              icon: _isTestingConnection
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.network_check_rounded, size: 18),
              label: Text(_isTestingConnection ? 'Menguji...' : 'Tes Ping Server'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _resetToDefault,
              icon: const Icon(Icons.restore_rounded, size: 18, color: Colors.blueGrey),
              label: const Text('Reset Bawaan', style: TextStyle(color: Colors.blueGrey, fontSize: 13)),
            ),
          ],
        ),

        if (_testResult != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: (_isTestSuccess ?? false) ? Colors.green.shade50 : Colors.red.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: (_isTestSuccess ?? false) ? Colors.green.shade300 : Colors.red.shade300,
              ),
            ),
            child: Text(
              _testResult!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: (_isTestSuccess ?? false) ? Colors.green.shade900 : Colors.red.shade900,
              ),
            ),
          ),
        ],

        const SizedBox(height: 12),

        // Ubah PIN (Opsional)
        InkWell(
          onTap: () => setState(() => _showChangePin = !_showChangePin),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Row(
              children: [
                Icon(
                  _showChangePin ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: Colors.indigo,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Ubah PIN Administrator (Opsional)',
                  style: TextStyle(fontSize: 12, color: Colors.indigo, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),

        if (_showChangePin) ...[
          const SizedBox(height: 6),
          TextField(
            controller: _newPinController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'PIN Baru',
              hintText: 'Biarkan kosong jika tidak ingin mengubah PIN',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],

        const SizedBox(height: 20),

        // Action Buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Get.back(),
              child: const Text('Tutup', style: TextStyle(color: Colors.grey)),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _saveBaseUrl,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Simpan & Terapkan', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ],
    );
  }
}
