import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

class PingResult {
  final bool isSuccess;
  final int latencyMs;
  final String host;
  final String? errorMessage;

  PingResult({
    required this.isSuccess,
    required this.latencyMs,
    required this.host,
    this.errorMessage,
  });
}

class CurrentNetworkInfo {
  final String networkType; // 'Wi-Fi', 'Data Seluler', 'Ethernet', 'Tidak Terhubung'
  final String? ssid;
  final bool isConnected;

  CurrentNetworkInfo({
    required this.networkType,
    this.ssid,
    required this.isConnected,
  });

  String get displayName {
    if (ssid != null && ssid!.isNotEmpty && ssid != '<None>') {
      return 'Wi-Fi: $ssid';
    }
    if (networkType == 'Wi-Fi') {
      return 'Wi-Fi: Terhubung';
    }
    if (networkType == 'Data Seluler') {
      return 'Data Seluler: Terhubung';
    }
    if (networkType == 'Ethernet') {
      return 'Ethernet: Terhubung';
    }
    if (isConnected) {
      return 'Jaringan: Terhubung (Online)';
    }
    return 'Jaringan: Tidak Terhubung';
  }
}

class WifiConnectResult {
  final bool isSuccess;
  final String message;
  final PingResult? pingResult;

  WifiConnectResult({
    required this.isSuccess,
    required this.message,
    this.pingResult,
  });
}

class NetworkService {
  static const String defaultPingHost = '8.8.8.8';

  /// Tes ping ke host (default 8.8.8.8 atau google.com).
  static Future<PingResult> ping({
    String host = defaultPingHost,
    int timeoutMs = 3000,
  }) async {
    final sw = Stopwatch()..start();

    try {
      // 1. Coba ICMP ping lewat Process.run jika di Windows/Linux/Mac
      if (Platform.isWindows) {
        final result = await Process.run(
          'ping',
          ['-n', '1', '-w', '$timeoutMs', host],
          runInShell: true,
        );
        sw.stop();
        final output = result.stdout.toString();
        if (result.exitCode == 0 && output.contains('Reply from')) {
          final match = RegExp(r'time[=<](\d+)\s*ms', caseSensitive: false).firstMatch(output);
          final ms = match != null
              ? int.tryParse(match.group(1)!) ?? sw.elapsedMilliseconds
              : sw.elapsedMilliseconds;
          return PingResult(isSuccess: true, latencyMs: ms, host: host);
        }
      } else if (Platform.isLinux || Platform.isMacOS || Platform.isAndroid) {
        final result = await Process.run(
          'ping',
          ['-c', '1', '-W', '${(timeoutMs / 1000).ceil()}', host],
          runInShell: true,
        );
        sw.stop();
        if (result.exitCode == 0) {
          return PingResult(isSuccess: true, latencyMs: sw.elapsedMilliseconds, host: host);
        }
      }

      // 2. Direct socket probe (port 53 DNS untuk 8.8.8.8, port 80/443 untuk domain)
      final port = (host == '8.8.8.8' || host == '1.1.1.1') ? 53 : 80;
      final socket = await Socket.connect(
        host,
        port,
        timeout: Duration(milliseconds: timeoutMs),
      );
      sw.stop();
      await socket.close();
      return PingResult(isSuccess: true, latencyMs: sw.elapsedMilliseconds, host: host);
    } catch (e) {
      sw.stop();
      return PingResult(
        isSuccess: false,
        latencyMs: sw.elapsedMilliseconds,
        host: host,
        errorMessage: e.toString(),
      );
    }
  }

  /// Deteksi konektivitas jaringan lengkap (Wi-Fi, Data Seluler, Ethernet, SSID).
  static Future<CurrentNetworkInfo> getCurrentNetworkInfo() async {
    String type = 'Tidak Terhubung';
    bool hasConnection = false;

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.wifi)) {
        type = 'Wi-Fi';
        hasConnection = true;
      } else if (connectivityResult.contains(ConnectivityResult.mobile)) {
        type = 'Data Seluler';
        hasConnection = true;
      } else if (connectivityResult.contains(ConnectivityResult.ethernet)) {
        type = 'Ethernet';
        hasConnection = true;
      } else if (connectivityResult.contains(ConnectivityResult.vpn)) {
        type = 'VPN';
        hasConnection = true;
      }
    } catch (_) {}

    String? ssid;
    if (Platform.isWindows) {
      ssid = await getCurrentSsid();
      if (ssid != null && ssid.isNotEmpty) {
        hasConnection = true;
        type = 'Wi-Fi';
      }
    }

    return CurrentNetworkInfo(
      networkType: type,
      ssid: ssid,
      isConnected: hasConnection,
    );
  }

  /// Ambil info Wi-Fi saat ini (SSID yang terhubung).
  static Future<String?> getCurrentSsid() async {
    if (!Platform.isWindows) return null;
    try {
      final res = await Process.run('netsh', ['wlan', 'show', 'interfaces'], runInShell: true);
      final output = res.stdout.toString();
      final match = RegExp(r'^\s*SSID\s*:\s*(.+)$', multiLine: true).firstMatch(output);
      if (match != null) {
        final ssid = match.group(1)?.trim();
        if (ssid != null && ssid.isNotEmpty && ssid != '<None>') {
          return ssid;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Pindai (scan) daftar Wi-Fi yang terlihat di sekitar.
  static Future<List<String>> scanWifiNetworks() async {
    final ssids = <String>{};

    if (Platform.isWindows) {
      try {
        final res = await Process.run('netsh', ['wlan', 'show', 'networks'], runInShell: true);
        final lines = res.stdout.toString().split('\n');
        for (final line in lines) {
          final match = RegExp(r'SSID\s+\d+\s*:\s*(.+)$', caseSensitive: false).firstMatch(line.trim());
          if (match != null) {
            final name = match.group(1)?.trim() ?? '';
            if (name.isNotEmpty && !name.contains('SSID')) {
              ssids.add(name);
            }
          }
        }
      } catch (_) {}

      // Tambahkan profil tersimpan jika belum ada di list
      try {
        final resProf = await Process.run('netsh', ['wlan', 'show', 'profile'], runInShell: true);
        final linesProf = resProf.stdout.toString().split('\n');
        for (final line in linesProf) {
          final match = RegExp(r'All User Profile\s*:\s*(.+)$', caseSensitive: false).firstMatch(line.trim());
          if (match != null) {
            final name = match.group(1)?.trim() ?? '';
            if (name.isNotEmpty) {
              ssids.add(name);
            }
          }
        }
      } catch (_) {}
    }

    return ssids.toList();
  }

  /// Sambungkan ke Wi-Fi dengan SSID & Password, lalu uji ping ke 8.8.8.8.
  static Future<WifiConnectResult> connectToWifi({
    required String ssid,
    String? password,
  }) async {
    if (ssid.trim().isEmpty) {
      return WifiConnectResult(
        isSuccess: false,
        message: 'Nama SSID Wi-Fi tidak boleh kosong.',
      );
    }

    if (!Platform.isWindows) {
      return WifiConnectResult(
        isSuccess: false,
        message: 'Penggantian Wi-Fi langsung hanya didukung pada desktop Windows.',
      );
    }

    try {
      final cleanSsid = ssid.trim();
      final cleanPass = password?.trim() ?? '';

      // 1. Buat profil XML jika password diberikan
      if (cleanPass.isNotEmpty) {
        final xml = '''<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$cleanSsid</name>
    <SSIDConfig>
        <SSID>
            <name>$cleanSsid</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>WPA2PSK</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$cleanPass</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>''';

        final tempFile = File('${Directory.systemTemp.path}/wifi_${DateTime.now().millisecondsSinceEpoch}.xml');
        await tempFile.writeAsString(xml);

        try {
          await Process.run('netsh', ['wlan', 'add', 'profile', 'filename=${tempFile.path}', 'user=all'], runInShell: true);
        } finally {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        }
      }

      // 2. Kirim perintah connect
      await Process.run('netsh', ['wlan', 'connect', 'name=$cleanSsid'], runInShell: true);

      // 3. Beri jeda 3 detik agar adapter mendapatkan IP
      await Future.delayed(const Duration(milliseconds: 3000));

      // 4. Lakukan tes ping ke 8.8.8.8
      final pingResult = await ping(host: '8.8.8.8');
      if (pingResult.isSuccess) {
        return WifiConnectResult(
          isSuccess: true,
          message: 'Berhasil terhubung ke "$cleanSsid". Response Time: ${pingResult.latencyMs} ms.',
          pingResult: pingResult,
        );
      } else {
        // Coba ping fallback ke google.com
        final googlePing = await ping(host: 'google.com');
        if (googlePing.isSuccess) {
          return WifiConnectResult(
            isSuccess: true,
            message: 'Berhasil terhubung ke "$cleanSsid". Response Time: ${googlePing.latencyMs} ms.',
            pingResult: googlePing,
          );
        }

        return WifiConnectResult(
          isSuccess: false,
          message: 'Tersambung ke Wi-Fi "$cleanSsid", tetapi koneksi internet gagal (RTO).',
          pingResult: pingResult,
        );
      }
    } catch (e) {
      return WifiConnectResult(
        isSuccess: false,
        message: 'Gagal menghubungkan ke Wi-Fi: $e',
      );
    }
  }
}
