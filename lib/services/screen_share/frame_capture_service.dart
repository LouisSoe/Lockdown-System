import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;

/// Service untuk capture layar dan compress menjadi JPEG bytes.
/// Berjalan di Isolate terpisah agar UI exam tidak terpengaruh.
class FrameCaptureService extends GetxService {
  // Key global untuk RepaintBoundary yang membungkus konten exam
  final GlobalKey captureKey = GlobalKey();

  // Flag untuk mencegah concurrent capture
  bool _isCapturing = false;

  /// Capture frame dari widget tree dan compress ke JPEG.
  /// Return null jika capture gagal atau sedang dalam proses.
  Future<Uint8List?> captureFrame({
    int targetWidth = 960,
    int targetHeight = 540,
    int jpegQuality = 50,
  }) async {
    // Jangan capture saat dialog terbuka agar animasi dialog tidak ngeframe/lag
    if (_isCapturing || Get.isDialogOpen == true) return null;
    _isCapturing = true;

    try {
      final context = captureKey.currentContext;
      if (context == null) {
        print('[FrameCaptureService] captureKey context is null — widget not mounted');
        return null;
      }

      final renderObject = context.findRenderObject();
      if (renderObject == null || renderObject is! RenderRepaintBoundary) {
        print('[FrameCaptureService] RenderRepaintBoundary not found');
        return null;
      }

      // Capture sebagai ui.Image dengan pixel ratio 1.0 untuk ukuran lebih kecil
      final ui.Image image = await renderObject.toImage(pixelRatio: 1.0);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();

      if (byteData == null) return null;

      // Compress di isolate agar tidak block main thread
      final compressed = await _compressInIsolate(
        byteData.buffer.asUint8List(),
        image.width,
        image.height,
        targetWidth,
        targetHeight,
        jpegQuality,
      );

      return compressed;
    } catch (e) {
      print('[FrameCaptureService] Capture error: $e');
      return null;
    } finally {
      _isCapturing = false;
    }
  }

  /// Jalankan resize + JPEG encode di isolate terpisah.
  static Future<Uint8List?> _compressInIsolate(
    Uint8List rgba,
    int srcWidth,
    int srcHeight,
    int targetWidth,
    int targetHeight,
    int quality,
  ) async {
    final receivePort = ReceivePort();
    await Isolate.spawn(
      _isolateCompress,
      _CompressParams(
        rgba: rgba,
        srcWidth: srcWidth,
        srcHeight: srcHeight,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
        quality: quality,
        sendPort: receivePort.sendPort,
      ),
    );
    final result = await receivePort.first;
    if (result is Uint8List) return result;
    return null;
  }

  /// Entry point untuk isolate compress.
  static void _isolateCompress(_CompressParams params) {
    try {
      final image = img.Image.fromBytes(
        width: params.srcWidth,
        height: params.srcHeight,
        bytes: params.rgba.buffer,
        format: img.Format.uint8,
        numChannels: 4,
      );

      // Resize ke target resolution
      final resized = img.copyResize(
        image,
        width: params.targetWidth,
        height: params.targetHeight,
        interpolation: img.Interpolation.linear,
      );

      // Encode ke JPEG
      final jpeg = img.encodeJpg(resized, quality: params.quality);
      params.sendPort.send(Uint8List.fromList(jpeg));
    } catch (e) {
      params.sendPort.send(null);
    }
  }

  /// Wrap widget exam dengan RepaintBoundary untuk capture.
  Widget wrapWithCapture(Widget child) {
    return RepaintBoundary(
      key: captureKey,
      child: child,
    );
  }
}

/// Parameter untuk dikirim ke isolate.
class _CompressParams {
  final Uint8List rgba;
  final int srcWidth;
  final int srcHeight;
  final int targetWidth;
  final int targetHeight;
  final int quality;
  final SendPort sendPort;

  _CompressParams({
    required this.rgba,
    required this.srcWidth,
    required this.srcHeight,
    required this.targetWidth,
    required this.targetHeight,
    required this.quality,
    required this.sendPort,
  });
}
