import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:screenshot/screenshot.dart';
import 'package:lockdown_engine/core/utils/image_compressor.dart';
import 'package:lockdown_engine/data/repositories/monitoring_repository.dart';

/// Legacy screenshot service — dinonaktifkan, digantikan oleh ScreenShareService.
/// Set [_enabled = true] untuk mengaktifkan kembali.
class ScreenshotService extends GetxService {
  // ─── FEATURE FLAG ─────────────────────────────────────────────────────────
  static const bool _enabled = false;
  // ──────────────────────────────────────────────────────────────────────────

  final MonitoringRepository _monitoringRepo = MonitoringRepository();
  final ScreenshotController _screenshotController = ScreenshotController();

  String? _currentSessionId;
  bool _isCapturing = false;

  void setSessionId(String sessionId) {
    _currentSessionId = sessionId;
  }

  ScreenshotController get controller => _screenshotController;

  Future<String?> captureAndCompress() async {
    if (!_enabled) {
      print('[ScreenshotService] Feature disabled');
      return null;
    }

    if (_isCapturing) {
      print('⚠ Screenshot capture already in progress');
      return null;
    }

    _isCapturing = true;

    try {
      final imageBytes = await _screenshotController.capture();
      if (imageBytes == null) {
        print('✗ Screenshot capture failed: null bytes');
        return null;
      }

      final compressed = await ImageCompressor.compress(
        imageBytes,
        quality: 80,
        maxWidth: 1920,
        maxHeight: 1080,
      );

      final base64Image = base64Encode(compressed);
      print('✓ Screenshot captured (${compressed.length} bytes)');
      return base64Image;
    } catch (e) {
      print('✗ Screenshot error: $e');
      return null;
    } finally {
      _isCapturing = false;
    }
  }

  Future<void> captureAndUpload(String eventId) async {
    if (!_enabled) {
      print('[ScreenshotService] Feature disabled');
      return;
    }

    if (_currentSessionId == null) {
      print('⚠ Cannot upload screenshot: No session ID');
      return;
    }

    final base64Image = await captureAndCompress();
    if (base64Image == null) return;

    try {
      await _monitoringRepo.uploadScreenshot(
        _currentSessionId!,
        eventId,
        base64Image,
      );
      print('✓ Screenshot uploaded for event: $eventId');
    } catch (e) {
      print('✗ Upload screenshot error: $e');
    }
  }

  /// Wrap widget dengan Screenshot controller.
  /// Tidak aktif selama [_enabled = false].
  Widget wrapWithScreenshot(Widget child) {
    if (!_enabled) return child;
    return Screenshot(
      controller: _screenshotController,
      child: child,
    );
  }
}
