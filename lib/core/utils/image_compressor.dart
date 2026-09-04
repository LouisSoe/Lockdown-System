import 'dart:typed_data';
import 'package:image/image.dart' as img;

class ImageCompressor {
  static Future<Uint8List> compress(
    Uint8List imageBytes, {
    int quality = 80,
    int maxWidth = 1920,
    int maxHeight = 1080,
  }) async {
    try {
      // Decode image
      img.Image? image = img.decodeImage(imageBytes);
      if (image == null) return imageBytes;
      
      // Resize if needed
      if (image.width > maxWidth || image.height > maxHeight) {
        image = img.copyResize(
          image,
          width: image.width > maxWidth ? maxWidth : null,
          height: image.height > maxHeight ? maxHeight : null,
        );
      }
      
      // Encode as JPEG with quality
      final compressed = img.encodeJpg(image, quality: quality);
      
      return Uint8List.fromList(compressed);
    } catch (e) {
      print('Image compression error: $e');
      return imageBytes;
    }
  }
}
