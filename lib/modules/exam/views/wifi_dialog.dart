import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lockdown_engine/services/network/network_service.dart';

class WifiDialog extends StatefulWidget {
  final VoidCallback? onConnected;

  const WifiDialog({super.key, this.onConnected});

  static Future<void> show({VoidCallback? onConnected}) {
    return Get.dialog(
      WifiDialog(onConnected: onConnected),
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 150),
      transitionCurve: Curves.easeOutCubic,
    );
  }

  @override
  State<WifiDialog> createState() => _WifiDialogState();
}

class _WifiDialogState extends State<WifiDialog> {
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isPinging = false;
  bool _isScanning = false;

  String? _currentSsid;
  CurrentNetworkInfo? _networkInfo;
  PingResult? _pingResult;
  String? _statusMessage;
  bool _statusIsSuccess = false;

  List<String> _scannedSsids = [];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    await _checkCurrentConnection();
    await _scanNetworks();
  }

  Future<void> _checkCurrentConnection() async {
    setState(() => _isPinging = true);
    final netInfo = await NetworkService.getCurrentNetworkInfo();
    final pingRes = await NetworkService.ping(host: '8.8.8.8');
    if (!mounted) return;
    setState(() {
      _networkInfo = netInfo;
      _currentSsid = netInfo.ssid;
      _pingResult = pingRes;
      _isPinging = false;
    });
  }

  Future<void> _scanNetworks() async {
    setState(() => _isScanning = true);
    final networks = await NetworkService.scanWifiNetworks();
    if (!mounted) return;
    setState(() {
      _scannedSsids = networks;
      _isScanning = false;
    });
  }

  String _getNetworkDisplayTitle() {
    if (_currentSsid != null && _currentSsid!.isNotEmpty && _currentSsid != '<None>') {
      return 'Wi-Fi: $_currentSsid';
    }
    if (_networkInfo != null) {
      if (_networkInfo!.networkType == 'Wi-Fi') {
        return 'Wi-Fi: Terhubung';
      }
      if (_networkInfo!.networkType == 'Data Seluler') {
        return 'Data Seluler: Terhubung';
      }
      if (_networkInfo!.networkType == 'Ethernet') {
        return 'Ethernet: Terhubung';
      }
    }
    // Fallback jika ping berhasil, koneksi internet aktif
    if (_pingResult?.isSuccess == true) {
      return 'Jaringan: Terhubung (Online)';
    }
    return 'Jaringan: Tidak Terhubung';
  }

  Future<void> _handleConnect() async {
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text.trim();

    if (ssid.isEmpty) {
      setState(() {
        _statusMessage = 'Nama SSID Wi-Fi wajib diisi.';
        _statusIsSuccess = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Menghubungkan ke "$ssid" dan menguji koneksi...';
      _statusIsSuccess = false;
    });

    final result = await NetworkService.connectToWifi(
      ssid: ssid,
      password: password.isNotEmpty ? password : null,
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _statusMessage = result.message;
      _statusIsSuccess = result.isSuccess;
      _pingResult = result.pingResult;
    });

    if (result.isSuccess) {
      Get.snackbar(
        'Wi-Fi Terhubung',
        result.message,
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.green.shade700,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );

      // Beri jeda 1 detik lalu tutup dialog dan panggil callback reload
      await Future.delayed(const Duration(milliseconds: 1000));
      if (mounted) {
        Get.back();
        widget.onConnected?.call();
      }
    }
  }

  Future<void> _handleTestPing() async {
    setState(() {
      _isPinging = true;
      _statusMessage = 'Menguji response time jaringan...';
      _statusIsSuccess = false;
    });

    final res = await NetworkService.ping(host: '8.8.8.8');
    final netInfo = await NetworkService.getCurrentNetworkInfo();
    if (!mounted) return;

    setState(() {
      _isPinging = false;
      _pingResult = res;
      _networkInfo = netInfo;
      _currentSsid = netInfo.ssid;
      if (res.isSuccess) {
        _statusMessage = 'Koneksi Normal (Response Time: ${res.latencyMs} ms)';
        _statusIsSuccess = true;
      } else {
        _statusMessage = 'Koneksi Gagal / RTO (Tidak ada internet)';
        _statusIsSuccess = false;
      }
    });
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.wifi_find_rounded, color: Colors.blue.shade700, size: 22),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Ganti Jaringan Wi-Fi',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_isScanning)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: 'Pindai Ulang Wi-Fi',
              onPressed: _isLoading ? null : _scanNetworks,
            ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kartu Status Koneksi Saat Ini (Responsive & No Overflow)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _pingResult?.isSuccess == true
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _pingResult?.isSuccess == true
                      ? Colors.green.shade300
                      : Colors.orange.shade300,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Baris Header Status & Tombol Tes Respon
                  Row(
                    children: [
                      Icon(
                        _pingResult?.isSuccess == true
                            ? Icons.check_circle_rounded
                            : Icons.warning_amber_rounded,
                        size: 18,
                        color: _pingResult?.isSuccess == true
                            ? Colors.green.shade700
                            : Colors.orange.shade800,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Status Jaringan',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: _pingResult?.isSuccess == true
                                ? Colors.green.shade900
                                : Colors.orange.shade900,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: _isPinging ? null : _handleTestPing,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isPinging)
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(strokeWidth: 1.5),
                                )
                              else
                                Icon(Icons.refresh_rounded, size: 14, color: Colors.blue.shade800),
                              const SizedBox(width: 4),
                              Text(
                                'Tes Respon',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Label Jaringan Terhubung (deteksi Wi-Fi / Data Seluler akurat)
                  Row(
                    children: [
                      Icon(
                        (_networkInfo?.networkType == 'Wi-Fi' || _currentSsid != null)
                            ? Icons.wifi
                            : (_networkInfo?.networkType == 'Data Seluler'
                                ? Icons.signal_cellular_alt_rounded
                                : Icons.lan_outlined),
                        size: 14,
                        color: Colors.grey.shade700,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _getNetworkDisplayTitle(),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // Response Time
                  Row(
                    children: [
                      Icon(
                        Icons.speed_rounded,
                        size: 14,
                        color: _pingResult?.isSuccess == true
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _pingResult != null
                              ? (_pingResult!.isSuccess
                                  ? 'Response Time: ${_pingResult!.latencyMs} ms (Normal)'
                                  : 'Response Time: RTO / Terputus')
                              : 'Memeriksa response time...',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _pingResult?.isSuccess == true
                                ? Colors.green.shade800
                                : Colors.red.shade700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Pilihan Wi-Fi dari Scan
            if (_scannedSsids.isNotEmpty) ...[
              const Text(
                'Pilih dari Wi-Fi Terdeteksi:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
              ),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 110),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: _scannedSsids.length,
                  separatorBuilder: (ctx, i) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final ssid = _scannedSsids[index];
                    final isSelected = _ssidController.text == ssid;
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      leading: const Icon(Icons.wifi, size: 16),
                      title: Text(
                        ssid,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check, size: 16, color: Colors.blue.shade700)
                          : null,
                      selected: isSelected,
                      onTap: () {
                        setState(() {
                          _ssidController.text = ssid;
                        });
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Input SSID
            TextField(
              controller: _ssidController,
              enabled: !_isLoading,
              decoration: const InputDecoration(
                labelText: 'Nama Wi-Fi (SSID)',
                hintText: 'Contoh: Hub / Hotspot HP',
                prefixIcon: Icon(Icons.wifi),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),

            const SizedBox(height: 12),

            // Input Password
            TextField(
              controller: _passwordController,
              enabled: !_isLoading,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password Wi-Fi',
                hintText: 'Kosongkan jika Wi-Fi tanpa sandi',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              onSubmitted: (_) => _handleConnect(),
            ),

            // Status Banner jika ada pesan
            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _statusIsSuccess ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _statusIsSuccess ? Colors.green.shade300 : Colors.red.shade300,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _statusIsSuccess ? Icons.check_circle : Icons.info_outline,
                      size: 18,
                      color: _statusIsSuccess ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          fontSize: 12,
                          color: _statusIsSuccess ? Colors.green.shade900 : Colors.red.shade900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Get.back(),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _isLoading ? null : _handleConnect,
          child: _isLoading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_protected_setup_rounded, size: 16),
                    SizedBox(width: 6),
                    Text('Sambungkan'),
                  ],
                ),
        ),
      ],
    );
  }
}
