import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

class ScannerBridge {
  final WebViewController controller;
  final BuildContext context;

  ScannerBridge(this.controller, this.context);

  /// Handle incoming scanner commands
  Future<Map<String, dynamic>> handleCommand(String command, Map<String, dynamic> params) async {
    try {
      switch (command) {
        case 'scanner.scan':
          return await _scan(params);
        case 'scanner.scanBarcode':
          return await _scanBarcode(params);
        case 'scanner.scanQR':
          return await _scanQR(params);
        case 'scanner.checkPermission':
          return await _checkPermission();
        case 'scanner.requestPermission':
          return await _requestPermission();
        default:
          return {'success': false, 'error': 'Unknown scanner command: $command'};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Generic scan with options
  Future<Map<String, dynamic>> _scan(Map<String, dynamic> params) async {
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
      final formats = params['formats'] as List<dynamic>?;
      final title = params['title'] as String? ?? 'Scan Code';
      final message = params['message'] as String?;

      // Convert format strings to BarcodeFormat enum
      List<BarcodeFormat>? barcodeFormats;
      if (formats != null) {
        barcodeFormats = formats.map((f) => _stringToBarcodeFormat(f.toString())).toList();
      }

      // Show scanner
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ScannerScreen(
            formats: barcodeFormats,
            title: title,
            message: message,
          ),
        ),
      );

      if (result == null) {
        return {
          'success': false,
          'error': 'Scan cancelled',
          'cancelled': true,
        };
      }

      return {
        'success': true,
        'code': result['code'],
        'format': result['format'],
        'type': result['type'],
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Scan barcode (1D codes)
  Future<Map<String, dynamic>> _scanBarcode(Map<String, dynamic> params) async {
    return await _scan({
      ...params,
      'formats': ['ean13', 'ean8', 'upca', 'upce', 'code128', 'code39', 'code93', 'itf'],
      'title': params['title'] ?? 'Scan Barcode',
    });
  }

  /// Scan QR code only
  Future<Map<String, dynamic>> _scanQR(Map<String, dynamic> params) async {
    return await _scan({
      ...params,
      'formats': ['qr'],
      'title': params['title'] ?? 'Scan QR Code',
    });
  }

  /// Check camera permission
  Future<Map<String, dynamic>> _checkPermission() async {
    try {
      final status = await Permission.camera.status;
      
      return {
        'success': true,
        'granted': status.isGranted,
        'denied': status.isDenied,
        'permanentlyDenied': status.isPermanentlyDenied,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Request camera permission
  Future<Map<String, dynamic>> _requestPermission() async {
    try {
      final status = await Permission.camera.request();
      
      return {
        'success': true,
        'granted': status.isGranted,
        'denied': status.isDenied,
        'permanentlyDenied': status.isPermanentlyDenied,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Convert string to BarcodeFormat
  BarcodeFormat _stringToBarcodeFormat(String format) {
    switch (format.toLowerCase()) {
      case 'qr':
        return BarcodeFormat.qrCode;
      case 'ean13':
        return BarcodeFormat.ean13;
      case 'ean8':
        return BarcodeFormat.ean8;
      case 'upca':
        return BarcodeFormat.upcA;
      case 'upce':
        return BarcodeFormat.upcE;
      case 'code128':
        return BarcodeFormat.code128;
      case 'code39':
        return BarcodeFormat.code39;
      case 'code93':
        return BarcodeFormat.code93;
      case 'itf':
        return BarcodeFormat.itf;
      case 'datamatrix':
        return BarcodeFormat.dataMatrix;
      case 'pdf417':
        return BarcodeFormat.pdf417;
      case 'aztec':
        return BarcodeFormat.aztec;
      default:
        return BarcodeFormat.qrCode;
    }
  }
}

/// Scanner Screen Widget
class ScannerScreen extends StatefulWidget {
  final List<BarcodeFormat>? formats;
  final String title;
  final String? message;

  const ScannerScreen({
    Key? key,
    this.formats,
    required this.title,
    this.message,
  }) : super(key: key);

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
  );

  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _controller.start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    
    if (barcodes.isEmpty) return;

    final barcode = barcodes.first;
    
    if (barcode.rawValue == null) return;

    // Check if format matches requested formats
    if (widget.formats != null && !widget.formats!.contains(barcode.format)) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    // Return result
    Navigator.pop(context, {
      'code': barcode.rawValue,
      'format': barcode.format.name,
      'type': _getBarcodeType(barcode.format),
    });
  }

  String _getBarcodeType(BarcodeFormat format) {
    if (format == BarcodeFormat.qrCode) {
      return 'qr';
    } else if ([
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ].contains(format)) {
      return 'ean';
    } else {
      return 'barcode';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Scanner view
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          
          // Overlay
          CustomPaint(
            painter: ScannerOverlay(),
            child: Container(),
          ),
          
          // Instructions
          if (widget.message != null)
            Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.all(16),
                margin: EdgeInsets.symmetric(horizontal: 32),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.message!,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          
          // Cancel button
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: Text('Cancel'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Scanner Overlay Painter
class ScannerOverlay extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.5);
    
    final scanAreaSize = size.width * 0.7;
    final left = (size.width - scanAreaSize) / 2;
    final top = (size.height - scanAreaSize) / 2;
    
    // Draw overlay with cutout
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, scanAreaSize, scanAreaSize),
        Radius.circular(12),
      ))
      ..fillType = PathFillType.evenOdd;
    
    canvas.drawPath(path, paint);
    
    // Draw corner markers
    final cornerPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    
    final cornerLength = 30.0;
    
    // Top-left
    canvas.drawLine(Offset(left, top + cornerLength), Offset(left, top), cornerPaint);
    canvas.drawLine(Offset(left, top), Offset(left + cornerLength, top), cornerPaint);
    
    // Top-right
    canvas.drawLine(Offset(left + scanAreaSize - cornerLength, top), 
                    Offset(left + scanAreaSize, top), cornerPaint);
    canvas.drawLine(Offset(left + scanAreaSize, top), 
                    Offset(left + scanAreaSize, top + cornerLength), cornerPaint);
    
    // Bottom-left
    canvas.drawLine(Offset(left, top + scanAreaSize - cornerLength), 
                    Offset(left, top + scanAreaSize), cornerPaint);
    canvas.drawLine(Offset(left, top + scanAreaSize), 
                    Offset(left + cornerLength, top + scanAreaSize), cornerPaint);
    
    // Bottom-right
    canvas.drawLine(Offset(left + scanAreaSize - cornerLength, top + scanAreaSize), 
                    Offset(left + scanAreaSize, top + scanAreaSize), cornerPaint);
    canvas.drawLine(Offset(left + scanAreaSize, top + scanAreaSize - cornerLength), 
                    Offset(left + scanAreaSize, top + scanAreaSize), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
