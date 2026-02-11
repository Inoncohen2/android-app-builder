import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraBridge {
  final WebViewController controller;
  final BuildContext context;
  final ImagePicker _picker = ImagePicker();

  CameraBridge(this.controller, this.context);

  /// Handle incoming camera commands
  Future<Map<String, dynamic>> handleCommand(String command, Map<String, dynamic> params) async {
    try {
      switch (command) {
        case 'camera.takePicture':
          return await _takePicture(params);
        case 'camera.pickFromGallery':
          return await _pickFromGallery(params);
        case 'camera.pickMultiple':
          return await _pickMultiple(params);
        case 'camera.compressImage':
          return await _compressImage(params);
        case 'camera.checkPermission':
          return await _checkPermission();
        case 'camera.requestPermission':
          return await _requestPermission();
        default:
          return {'success': false, 'error': 'Unknown camera command: $command'};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Take a picture with the camera
  Future<Map<String, dynamic>> _takePicture(Map<String, dynamic> params) async {
    try {
      // Check permission
      final permission = await Permission.camera.status;
      if (!permission.isGranted) {
        final result = await Permission.camera.request();
        if (!result.isGranted) {
          return {
            'success': false,
            'error': 'Camera permission denied',
            'needsPermission': true,
          };
        }
      }

      // Get options
      final quality = params['quality'] as int? ?? 85;
      final maxWidth = params['maxWidth'] as double?;
      final maxHeight = params['maxHeight'] as double?;

      // Take picture
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: quality,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );

      if (photo == null) {
        return {
          'success': false,
          'error': 'User cancelled',
          'cancelled': true,
        };
      }

      // Read image as base64
      final bytes = await photo.readAsBytes();
      final base64Image = base64Encode(bytes);

      return {
        'success': true,
        'image': 'data:image/jpeg;base64,$base64Image',
        'path': photo.path,
        'name': photo.name,
        'size': bytes.length,
        'mimeType': photo.mimeType,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Pick image from gallery
  Future<Map<String, dynamic>> _pickFromGallery(Map<String, dynamic> params) async {
    try {
      // Check permission
      final permission = await Permission.photos.status;
      if (!permission.isGranted) {
        final result = await Permission.photos.request();
        if (!result.isGranted) {
          return {
            'success': false,
            'error': 'Photos permission denied',
            'needsPermission': true,
          };
        }
      }

      // Get options
      final quality = params['quality'] as int? ?? 85;
      final maxWidth = params['maxWidth'] as double?;
      final maxHeight = params['maxHeight'] as double?;

      // Pick image
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: quality,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );

      if (image == null) {
        return {
          'success': false,
          'error': 'User cancelled',
          'cancelled': true,
        };
      }

      // Read image as base64
      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);

      return {
        'success': true,
        'image': 'data:image/jpeg;base64,$base64Image',
        'path': image.path,
        'name': image.name,
        'size': bytes.length,
        'mimeType': image.mimeType,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Pick multiple images from gallery
  Future<Map<String, dynamic>> _pickMultiple(Map<String, dynamic> params) async {
    try {
      // Check permission
      final permission = await Permission.photos.status;
      if (!permission.isGranted) {
        final result = await Permission.photos.request();
        if (!result.isGranted) {
          return {
            'success': false,
            'error': 'Photos permission denied',
            'needsPermission': true,
          };
        }
      }

      // Get options
      final limit = params['limit'] as int? ?? 10;
      final quality = params['quality'] as int? ?? 85;

      // Pick images
      final List<XFile> images = await _picker.pickMultiImage(
        imageQuality: quality,
        limit: limit,
      );

      if (images.isEmpty) {
        return {
          'success': false,
          'error': 'User cancelled',
          'cancelled': true,
        };
      }

      // Convert all images to base64
      List<Map<String, dynamic>> imageData = [];
      
      for (var image in images) {
        final bytes = await image.readAsBytes();
        final base64Image = base64Encode(bytes);
        
        imageData.add({
          'image': 'data:image/jpeg;base64,$base64Image',
          'path': image.path,
          'name': image.name,
          'size': bytes.length,
          'mimeType': image.mimeType,
        });
      }

      return {
        'success': true,
        'images': imageData,
        'count': imageData.length,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Compress an image
  Future<Map<String, dynamic>> _compressImage(Map<String, dynamic> params) async {
    try {
      final imagePath = params['path'] as String?;
      final base64Data = params['image'] as String?;
      
      if (imagePath == null && base64Data == null) {
        return {
          'success': false,
          'error': 'Either path or image data is required',
        };
      }

      final quality = params['quality'] as int? ?? 85;
      final maxWidth = params['maxWidth'] as int?;
      final maxHeight = params['maxHeight'] as int?;

      File? sourceFile;
      
      if (imagePath != null) {
        sourceFile = File(imagePath);
      } else if (base64Data != null) {
        // Convert base64 to file
        final bytes = base64Decode(base64Data.split(',').last);
        final tempDir = await getTemporaryDirectory();
        sourceFile = File('${tempDir.path}/temp_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await sourceFile.writeAsBytes(bytes);
      }

      if (sourceFile == null || !await sourceFile.exists()) {
        return {
          'success': false,
          'error': 'Source file not found',
        };
      }

      // Create output path
      final targetPath = '${sourceFile.parent.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';

      // Compress
      final compressedFile = await FlutterImageCompress.compressAndGetFile(
        sourceFile.absolute.path,
        targetPath,
        quality: quality,
        minWidth: maxWidth ?? 1920,
        minHeight: maxHeight ?? 1080,
      );

      if (compressedFile == null) {
        return {
          'success': false,
          'error': 'Compression failed',
        };
      }

      // Read compressed image
      final bytes = await compressedFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      // Calculate compression ratio
      final originalSize = await sourceFile.length();
      final compressedSize = bytes.length;
      final ratio = ((1 - (compressedSize / originalSize)) * 100).toStringAsFixed(1);

      return {
        'success': true,
        'image': 'data:image/jpeg;base64,$base64Image',
        'path': compressedFile.path,
        'originalSize': originalSize,
        'compressedSize': compressedSize,
        'compressionRatio': '$ratio%',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Check camera permission status
  Future<Map<String, dynamic>> _checkPermission() async {
    try {
      final cameraStatus = await Permission.camera.status;
      final photosStatus = await Permission.photos.status;

      return {
        'success': true,
        'camera': {
          'granted': cameraStatus.isGranted,
          'denied': cameraStatus.isDenied,
          'permanentlyDenied': cameraStatus.isPermanentlyDenied,
        },
        'photos': {
          'granted': photosStatus.isGranted,
          'denied': photosStatus.isDenied,
          'permanentlyDenied': photosStatus.isPermanentlyDenied,
        },
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Request camera permissions
  Future<Map<String, dynamic>> _requestPermission() async {
    try {
      final cameraResult = await Permission.camera.request();
      final photosResult = await Permission.photos.request();

      return {
        'success': true,
        'camera': {
          'granted': cameraResult.isGranted,
          'denied': cameraResult.isDenied,
          'permanentlyDenied': cameraResult.isPermanentlyDenied,
        },
        'photos': {
          'granted': photosResult.isGranted,
          'denied': photosResult.isDenied,
          'permanentlyDenied': photosResult.isPermanentlyDenied,
        },
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
}
