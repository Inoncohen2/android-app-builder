import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vibration/vibration.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';

// Import new bridges
import 'camera_bridge.dart';
import 'location_bridge.dart';
import 'scanner_bridge.dart';

class JavaScriptBridge {
  final WebViewController controller;
  final BuildContext context;
  
  // Bridge instances
  late final CameraBridge _cameraBridge;
  late final LocationBridge _locationBridge;
  late final ScannerBridge _scannerBridge;

  JavaScriptBridge(this.controller, this.context) {
    _cameraBridge = CameraBridge(controller, context);
    _locationBridge = LocationBridge(controller, context);
    _scannerBridge = ScannerBridge(controller, context);
  }

  /// Initialize the JavaScript bridge
  void initialize() {
    print('🌉 Initializing JavaScript Bridge...');
    
    // Add JavaScript channel for communication
    controller.addJavaScriptChannel(
      'web2app',
      onMessageReceived: (JavaScriptMessage message) {
        _handleMessage(message.message);
      },
    );

    // Inject bridge script when page loads
    _injectBridgeScript();
    
    print('✅ JavaScript Bridge initialized!');
  }

  /// Inject the complete Web2App JavaScript API
  Future<void> _injectBridgeScript() async {
    final script = '''
      (function() {
        if (typeof window.web2app !== 'undefined') {
          console.log('✅ Web2App bridge already initialized');
          return;
        }
        
        console.log('🌉 Initializing Web2App JavaScript Bridge...');
        
        window.web2app = {
          _callbacks: {},
          _callbackId: 0,
          _positionWatchers: {},
          
          _getCallbackId: function() {
            return 'cb_' + Date.now() + '_' + (++this._callbackId);
          },
          
          _send: function(command, data) {
            return new Promise((resolve, reject) => {
              const callbackId = this._getCallbackId();
              this._callbacks[callbackId] = { resolve, reject };
              
              setTimeout(() => {
                if (this._callbacks[callbackId]) {
                  this._callbacks[callbackId].reject(new Error('Timeout'));
                  delete this._callbacks[callbackId];
                }
              }, 30000);
              
              const message = JSON.stringify({
                command: command,
                data: data || {},
                callbackId: callbackId
              });
              
              try {
                web2app.postMessage(message);
              } catch (e) {
                reject(new Error('Failed to send message: ' + e.message));
                delete this._callbacks[callbackId];
              }
            });
          },
          
          _handleResponse: function(callbackId, result, error) {
            const callback = this._callbacks[callbackId];
            if (callback) {
              if (error) {
                callback.reject(new Error(error));
              } else {
                callback.resolve(result);
              }
              delete this._callbacks[callbackId];
            }
          },
          
          // ═══════════════════════════════════════════
          // BASIC APIs
          // ═══════════════════════════════════════════
          
          share: function(options) {
            if (!options || !options.text) {
              return Promise.reject(new Error('Text is required'));
            }
            return this._send('share', options);
          },
          
          vibrate: function(options) {
            return this._send('vibrate', options || { duration: 100 });
          },
          
          getDeviceInfo: function() {
            return this._send('getDeviceInfo', {});
          },
          
          getAppInfo: function() {
            return this._send('getAppInfo', {});
          },
          
          toast: function(message) {
            if (!message) {
              return Promise.reject(new Error('Message is required'));
            }
            return this._send('toast', { message: message });
          },
          
          openExternal: function(url) {
            if (!url) {
              return Promise.reject(new Error('URL is required'));
            }
            return this._send('openExternal', { url: url });
          },
          
          // ═══════════════════════════════════════════
          // CAMERA API
          // ═══════════════════════════════════════════
          
          camera: {
            takePicture: function(options) {
              return window.web2app._send('camera.takePicture', options || {});
            },
            
            pickFromGallery: function(options) {
              return window.web2app._send('camera.pickFromGallery', options || {});
            },
            
            pickMultiple: function(options) {
              return window.web2app._send('camera.pickMultiple', options || {});
            },
            
            compressImage: function(options) {
              if (!options || (!options.path && !options.image)) {
                return Promise.reject(new Error('path or image is required'));
              }
              return window.web2app._send('camera.compressImage', options);
            },
            
            checkPermission: function() {
              return window.web2app._send('camera.checkPermission', {});
            },
            
            requestPermission: function() {
              return window.web2app._send('camera.requestPermission', {});
            }
          },
          
          // ═══════════════════════════════════════════
          // LOCATION API
          // ═══════════════════════════════════════════
          
          location: {
            getCurrentPosition: function(options) {
              return window.web2app._send('location.getCurrentPosition', options || {});
            },
            
            watchPosition: function(callback, options) {
              const callbackId = window.web2app._getCallbackId();
              
              // Store the callback
              window.web2app._positionWatchers[callbackId] = callback;
              
              // Send command
              return window.web2app._send('location.watchPosition', {
                ...options,
                callbackId: callbackId
              }).then(() => callbackId);
            },
            
            clearWatch: function(watchId) {
              if (watchId && window.web2app._positionWatchers[watchId]) {
                delete window.web2app._positionWatchers[watchId];
              }
              return window.web2app._send('location.clearWatch', {});
            },
            
            distanceTo: function(coords) {
              if (!coords || coords.latitude === undefined || coords.longitude === undefined) {
                return Promise.reject(new Error('latitude and longitude are required'));
              }
              return window.web2app._send('location.distanceTo', coords);
            },
            
            checkPermission: function() {
              return window.web2app._send('location.checkPermission', {});
            },
            
            requestPermission: function() {
              return window.web2app._send('location.requestPermission', {});
            },
            
            isLocationServiceEnabled: function() {
              return window.web2app._send('location.isLocationServiceEnabled', {});
            },
            
            openSettings: function() {
              return window.web2app._send('location.openSettings', {});
            }
          },
          
          // Position update handler (called from native)
          _handlePositionUpdate: function(callbackId, position) {
            const callback = this._positionWatchers[callbackId];
            if (callback) {
              callback(position);
            }
          },
          
          _handlePositionError: function(callbackId, error) {
            console.error('Position error:', error);
          },
          
          // ═══════════════════════════════════════════
          // SCANNER API
          // ═══════════════════════════════════════════
          
          scanner: {
            scan: function(options) {
              return window.web2app._send('scanner.scan', options || {});
            },
            
            scanBarcode: function(options) {
              return window.web2app._send('scanner.scanBarcode', options || {});
            },
            
            scanQR: function(options) {
              return window.web2app._send('scanner.scanQR', options || {});
            },
            
            checkPermission: function() {
              return window.web2app._send('scanner.checkPermission', {});
            },
            
            requestPermission: function() {
              return window.web2app._send('scanner.requestPermission', {});
            }
          },
          
          // ═══════════════════════════════════════════
          // STATUS BAR API (placeholder)
          // ═══════════════════════════════════════════
          
          statusBar: {
            setColor: function(color) {
              return window.web2app._send('statusBarSetColor', { color: color });
            },
            hide: function() {
              return window.web2app._send('statusBarHide', {});
            },
            show: function() {
              return window.web2app._send('statusBarShow', {});
            }
          }
        };
        
        console.log('✅ Web2App JavaScript Bridge ready!');
        window.dispatchEvent(new Event('web2appReady'));
      })();
    ''';

    try {
      await controller.runJavaScript(script);
      print('✅ Bridge script injected');
    } catch (e) {
      print('❌ Failed to inject bridge script: $e');
    }
  }

  /// Handle incoming messages from JavaScript
  void _handleMessage(String message) async {
    try {
      print('📩 Bridge received: $message');
      
      final data = jsonDecode(message);
      final command = data['command'] as String;
      final params = data['data'] as Map<String, dynamic>? ?? {};
      final callbackId = data['callbackId'] as String?;

      Map<String, dynamic>? result;
      String? error;
      
      try {
        // Route to appropriate handler
        if (command.startsWith('camera.')) {
          result = await _cameraBridge.handleCommand(command, params);
        } else if (command.startsWith('location.')) {
          result = await _locationBridge.handleCommand(command, params);
        } else if (command.startsWith('scanner.')) {
          result = await _scannerBridge.handleCommand(command, params);
        } else {
          // Handle basic commands
          switch (command) {
            case 'share':
              result = await _handleShare(params);
              break;
            case 'vibrate':
              result = await _handleVibrate(params);
              break;
            case 'getDeviceInfo':
              result = await _handleGetDeviceInfo();
              break;
            case 'getAppInfo':
              result = await _handleGetAppInfo();
              break;
            case 'openExternal':
              result = await _handleOpenExternal(params);
              break;
            case 'toast':
              result = await _handleToast(params);
              break;
            case 'statusBarSetColor':
            case 'statusBarHide':
            case 'statusBarShow':
              result = {'success': true, 'message': 'Not yet implemented'};
              break;
            default:
              error = 'Unknown command: $command';
          }
        }
      } catch (e) {
        error = e.toString();
        print('❌ Command error: $e');
      }

      // Send result back to JavaScript
      if (callbackId != null) {
        _sendResult(callbackId, result, error);
      }
    } catch (e) {
      print('❌ Bridge error: $e');
    }
  }

  /// Send result back to JavaScript callback
  Future<void> _sendResult(String callbackId, Map<String, dynamic>? result, String? error) async {
    try {
      final resultJson = result != null ? jsonEncode(result) : 'null';
      final errorJson = error != null ? jsonEncode(error) : 'null';
      
      final script = '''
        (function() {
          if (window.web2app && window.web2app._handleResponse) {
            window.web2app._handleResponse('$callbackId', $resultJson, $errorJson);
          }
        })();
      ''';
      
      await controller.runJavaScript(script);
    } catch (e) {
      print('❌ Failed to send result: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Basic Command Handlers (from original bridge)
  // ═══════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> _handleShare(Map<String, dynamic> params) async {
    try {
      final text = params['text'] as String? ?? '';
      final subject = params['subject'] as String?;
      final url = params['url'] as String?;

      String shareText = text;
      if (url != null && url.isNotEmpty) {
        shareText = '$text\n$url';
      }

      final result = await Share.shareWithResult(shareText, subject: subject);

      return {
        'success': true,
        'status': result.status.name,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _handleVibrate(Map<String, dynamic> params) async {
    try {
      final duration = params['duration'] as int? ?? 100;
      final patternData = params['pattern'] as List<dynamic>?;

      final hasVibrator = await Vibration.hasVibrator() ?? false;
      
      if (!hasVibrator) {
        return {'success': false, 'error': 'Device does not support vibration'};
      }

      if (patternData != null) {
        final pattern = patternData.map((e) => e as int).toList();
        await Vibration.vibrate(pattern: pattern);
      } else {
        await Vibration.vibrate(duration: duration);
      }

      return {'success': true};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _handleGetDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      Map<String, dynamic> info = {};

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        info = {
          'platform': 'android',
          'model': androidInfo.model,
          'manufacturer': androidInfo.manufacturer,
          'brand': androidInfo.brand,
          'device': androidInfo.device,
          'osVersion': androidInfo.version.release,
          'sdkVersion': androidInfo.version.sdkInt,
          'isPhysicalDevice': androidInfo.isPhysicalDevice,
          'androidId': androidInfo.id,
        };
      }

      return info;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _handleGetAppInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      
      return {
        'appName': packageInfo.appName,
        'packageName': packageInfo.packageName,
        'version': packageInfo.version,
        'buildNumber': packageInfo.buildNumber,
        'buildSignature': packageInfo.buildSignature,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _handleOpenExternal(Map<String, dynamic> params) async {
    try {
      final url = params['url'] as String?;
      
      if (url == null || url.isEmpty) {
        return {'success': false, 'error': 'URL is required'};
      }

      return {
        'success': true,
        'message': 'Opening external URL: $url',
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _handleToast(Map<String, dynamic> params) async {
    try {
      final message = params['message'] as String?;
      
      if (message == null || message.isEmpty) {
        return {'success': false, 'error': 'Message is required'};
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: Duration(seconds: 2),
          ),
        );
      }

      return {'success': true};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
  
  /// Cleanup
  void dispose() {
    _locationBridge.dispose();
  }
}
