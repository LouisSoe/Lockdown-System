import 'dart:async';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'frame_capture_service.dart';

enum ScreenShareState { idle, connecting, connected, disconnected, error }

/// Service untuk stream frame layar peserta ke server via WebSocket.
/// Desain ringan: 1fps, skip identical frame, adaptive jika koneksi lambat.
class ScreenShareService extends GetxService {
  // Observable state
  final state = ScreenShareState.idle.obs;
  final isActive = false.obs;
  final framesSent = 0.obs;
  final framesSkipped = 0.obs;

  // Dependensi
  late FrameCaptureService _captureService;

  // WebSocket
  WebSocketChannel? _channel;
  StreamSubscription? _wsSubscription;

  // Timer loop capture
  Timer? _captureTimer;

  // Config
  static const Duration _captureInterval = Duration(milliseconds: 1000); // 1fps
  static const int _targetWidth = 960;
  static const int _targetHeight = 540;
  static const int _jpegQuality = 50;

  // Session info
  String? _sessionId;
  String? _deviceId;

  // Skip identical frame — simpan hash frame sebelumnya
  int? _lastFrameHash;

  // Flag reconnect
  bool _intentionalDisconnect = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;

  // Flag fitur — set false untuk nonaktifkan tanpa hapus kode
  static const bool _enabled = true;

  @override
  void onInit() {
    super.onInit();
    _captureService = Get.find<FrameCaptureService>();
  }

  /// Mulai screen share saat exam dimulai.
  Future<void> startSharing({
    required String sessionId,
    required String deviceId,
  }) async {
    if (!_enabled) {
      print('[ScreenShareService] Feature disabled');
      return;
    }

    if (isActive.value) {
      print('[ScreenShareService] Already active');
      return;
    }

    _sessionId = sessionId;
    _deviceId = deviceId;
    _intentionalDisconnect = false;
    _reconnectAttempts = 0;

    await _connect();
  }

  /// Stop screen share saat exam selesai.
  Future<void> stopSharing() async {
    if (!_enabled) return;

    _intentionalDisconnect = true;
    _stopCaptureLoop();
    await _disconnect();

    isActive.value = false;
    state.value = ScreenShareState.idle;
    _lastFrameHash = null;
    _reconnectAttempts = 0;
    print('[ScreenShareService] Sharing stopped');
  }

  // ─── WebSocket ────────────────────────────────────────────────────────────

  Future<void> _connect() async {
    state.value = ScreenShareState.connecting;

    final wsUrl = dotenv.env['WS_URL'] ?? '';
    if (wsUrl.isEmpty) {
      print('[ScreenShareService] WS_URL not set in .env');
      state.value = ScreenShareState.error;
      return;
    }

    try {
      final uri = Uri.parse('$wsUrl?session_id=$_sessionId&device_id=$_deviceId');
      _channel = WebSocketChannel.connect(uri);

      // Tunggu koneksi ready dengan timeout 5 detik
      await _channel!.ready.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('WebSocket connection timeout'),
      );

      state.value = ScreenShareState.connected;
      isActive.value = true;
      print('[ScreenShareService] Connected to $wsUrl');

      // Kirim event join
      _sendEvent('screen.join', {
        'session_id': _sessionId,
        'device_id': _deviceId,
      });

      // Listen untuk pesan dari server (ack, ping, dll)
      _wsSubscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      // Mulai capture loop
      _startCaptureLoop();
    } catch (e) {
      print('[ScreenShareService] Connection error: $e');
      state.value = ScreenShareState.error;
      _scheduleReconnect();
    }
  }

  Future<void> _disconnect() async {
    _wsSubscription?.cancel();
    _wsSubscription = null;

    if (_channel != null) {
      try {
        _sendEvent('screen.leave', {'session_id': _sessionId});
        await _channel!.sink.close(ws_status.goingAway)
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
      _channel = null;
    }

    state.value = ScreenShareState.disconnected;
  }

  void _onMessage(dynamic message) {
    // Server bisa kirim ping atau instruksi — untuk sekarang log saja
    print('[ScreenShareService] Server message: $message');
  }

  void _onError(dynamic error) {
    print('[ScreenShareService] WebSocket error: $error');
    state.value = ScreenShareState.error;
    if (!_intentionalDisconnect) {
      _scheduleReconnect();
    }
  }

  void _onDone() {
    print('[ScreenShareService] WebSocket closed');
    isActive.value = false;
    _stopCaptureLoop();
    if (!_intentionalDisconnect) {
      state.value = ScreenShareState.disconnected;
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_intentionalDisconnect) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('[ScreenShareService] Max reconnect attempts reached');
      state.value = ScreenShareState.error;
      return;
    }

    _reconnectAttempts++;
    final delay = Duration(seconds: _reconnectAttempts * 2); // backoff: 2s, 4s, 6s...
    print('[ScreenShareService] Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)');

    Future.delayed(delay, () {
      if (!_intentionalDisconnect) _connect();
    });
  }

  // ─── Capture Loop ─────────────────────────────────────────────────────────

  void _startCaptureLoop() {
    _captureTimer?.cancel();
    _captureTimer = Timer.periodic(_captureInterval, (_) => _captureAndSend());
    print('[ScreenShareService] Capture loop started (${_captureInterval.inMilliseconds}ms interval)');
  }

  void _stopCaptureLoop() {
    _captureTimer?.cancel();
    _captureTimer = null;
  }

  Future<void> _captureAndSend() async {
    // Jika WebSocket tidak connected atau ada dialog yang terbuka, skip capture
    if (state.value != ScreenShareState.connected || _channel == null || Get.isDialogOpen == true) {
      framesSkipped.value++;
      return;
    }

    final frameBytes = await _captureService.captureFrame(
      targetWidth: _targetWidth,
      targetHeight: _targetHeight,
      jpegQuality: _jpegQuality,
    );

    if (frameBytes == null) {
      framesSkipped.value++;
      return;
    }

    // Skip identical frame — hemat bandwidth saat layar diam
    final frameHash = frameBytes.length ^ frameBytes[0] ^ frameBytes[frameBytes.length - 1];
    if (frameHash == _lastFrameHash) {
      framesSkipped.value++;
      return;
    }
    _lastFrameHash = frameHash;

    // Encode ke base64 dan kirim
    try {
      final base64Frame = base64Encode(frameBytes);
      _sendEvent('screen.frame', {
        'session_id': _sessionId,
        'frame': base64Frame,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'size': frameBytes.length,
      });
      framesSent.value++;
    } catch (e) {
      print('[ScreenShareService] Send frame error: $e');
      framesSkipped.value++;
    }
  }

  // ─── Helper ───────────────────────────────────────────────────────────────

  void _sendEvent(String event, Map<String, dynamic> data) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode({
        'event': event,
        'data': data,
      }));
    } catch (e) {
      print('[ScreenShareService] Send event error: $e');
    }
  }

  @override
  void onClose() {
    stopSharing();
    super.onClose();
  }
}
