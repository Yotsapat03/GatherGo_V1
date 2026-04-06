/// Image Processor Service
/// Handles image picking and processing for both web and native platforms
/// - Image selection (native: image_picker, web: file picker)
/// - Image display (native: Image.file, web: Image.network from bytes)
/// - Image upload preparation (multipart files)
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:io' as io;

/// Result of image picking operation
class PickedImageResult {
  final String? path; // File path on native
  final XFile? xFile; // XFile from image_picker
  final Uint8List? bytes; // Bytes for web preview
  final String name; // File name
  final String mimeType; // e.g., 'image/jpeg'

  PickedImageResult({
    this.path,
    this.xFile,
    this.bytes,
    required this.name,
    required this.mimeType,
  });

  /// For native File() on non-web
  /// ⚠️ Only use on non-web platforms
  // ignore: avoid_returning_this_if_null
  dynamic get nativeFile {
    if (kIsWeb) return null;
    if (path != null) {
      return io.File(path!);
    }
    return null;
  }

  /// For network image display on web
  Future<Uint8List> getBytes() async {
    if (bytes != null) return bytes!;
    if (xFile != null) return await xFile!.readAsBytes();
    throw Exception('No image data available');
  }
}

class ImageProcessor {
  ImageProcessor._();
  static final _picker = ImagePicker();

  /// Pick a single image from gallery
  /// Returns [PickedImageResult] with cross-platform compatibility
  static Future<PickedImageResult?> pickImageFromGallery({
    int imageQuality = 85,
  }) async {
    try {
      final XFile? xFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: imageQuality,
      );

      if (xFile == null) return null;

      // ✅ Read bytes for web/preview
      final Uint8List bytes = await xFile.readAsBytes();

      return PickedImageResult(
        path: xFile.path,
        xFile: xFile,
        bytes: bytes,
        name: xFile.name,
        mimeType: 'image/${_getMimeType(xFile.name)}',
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Pick multiple images from gallery
  /// Returns list of [PickedImageResult] with cross-platform compatibility
  static Future<List<PickedImageResult>> pickMultipleImages({
    int imageQuality = 85,
    int maxImages = 10,
  }) async {
    try {
      final List<XFile> xFiles = await _picker.pickMultiImage(
        imageQuality: imageQuality,
        limit: maxImages,
      );

      if (xFiles.isEmpty) return [];

      final results = <PickedImageResult>[];
      for (final xFile in xFiles) {
        final bytes = await xFile.readAsBytes();
        results.add(
          PickedImageResult(
            path: xFile.path,
            xFile: xFile,
            bytes: bytes,
            name: xFile.name,
            mimeType: 'image/${_getMimeType(xFile.name)}',
          ),
        );
      }

      return results;
    } catch (e) {
      rethrow;
    }
  }

  /// Take a photo with camera
  /// Returns [PickedImageResult] with cross-platform compatibility
  static Future<PickedImageResult?> takePictureWithCamera({
    int imageQuality = 85,
  }) async {
    try {
      final XFile? xFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: imageQuality,
      );

      if (xFile == null) return null;

      final Uint8List bytes = await xFile.readAsBytes();

      return PickedImageResult(
        path: xFile.path,
        xFile: xFile,
        bytes: bytes,
        name: xFile.name,
        mimeType: 'image/${_getMimeType(xFile.name)}',
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Get MIME type from filename
  static String _getMimeType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'jpeg',
      'png' => 'png',
      'gif' => 'gif',
      'webp' => 'webp',
      _ => 'jpeg',
    };
  }

  /// Check if image processor is available on this platform
  /// Returns false on web (use file pickerwhen available instead)
  static bool get isAvailable => !kIsWeb;
}

// ✅ For web file uploads, consider using cross_file package
// or handling file input via web-specific libraries
