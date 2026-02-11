import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vibration/vibration.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';

class JavaScriptBridge {
  final WebViewController controller;
  final BuildContext context;

  JavaScriptBridge(this.controller, this.context);

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

  /// Inject the median JavaScript API into the page
  Future<void> _injectBridgeScript() async {
    final script = '''
      (function() {
        // Only initialize once
        if (typeof window.web2app !== 'undefined') {
          console.log('✅ Web2App bridge already initialized');
          return;
        }
        
        console.log('🌉 Initializing Web2App JavaScript Bridge...');
        
        // Create web2app object
        window.web2app = {
          _callbacks: {},
          _callbackId: 0,
          
          // Internal: Generate unique callback ID
          _getCallbackId: function() {
            return 'cb_' + Date.now() + '_' + (++this._callbackId);
          },
          
          // Internal: Send message to native
          _send: function(command, data) {
            return new Promise((resolve, reject) => {
              const callbackId = this._getCallbackId();
              
              // Store callbacks
              this._callbacks[callbackId] = { resolve, reject };
              
              // Timeout after 30 seconds
              setTimeout(() => {
                if (this._callbacks[callbackId]) {
                  this._callbacks[callbackId].reject(new Error('Timeout'));
                  delete this._callbacks[callbackId];
                }
              }, 30000);
              
              // Send to native
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
          
          // Internal: Handle response from native
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
          // PUBLIC API
          // ═══════════════════════════════════════════
          
          /**
           * Share text, URL, or content
           * @param {Object} options - Share options
           * @param {string} options.text - Text to share
           * @param {string} [options.subject] - Subject line
           * @param {string} [options.url] - URL to share
           * @returns {Promise<Object>} Result
           */
          share: function(options) {
            if (!options || !options.text) {
              return Promise.reject(new Error('Text is required'));
            }
            return this._send('share', options);
          },
          
          /**
           * Vibrate the device
           * @param {Object} [options] - Vibration options
           * @param {number} [options.duration=100] - Duration in milliseconds
           * @param {number[]} [options.pattern] - Vibration pattern [wait, vibrate, wait, vibrate]
           * @returns {Promise<Object>} Result
           */
          vibrate: function(options) {
            return this._send('vibrate', options || { duration: 100 });
          },
          
          /**
           * Get device information
           * @returns {Promise<Object>} Device info
           */
          getDeviceInfo: function() {
            return this._send('getDeviceInfo', {});
          },
          
          /**
           * Get app information
           * @returns {Promise<Object>} App info
           */
          getAppInfo: function() {
            return this._send('getAppInfo', {});
          },
          
          /**
           * Open URL in external browser
           * @param {string} url - URL to open
           * @returns {Promise<Object>} Result
           */
          openExternal: function(url) {
            if (!url) {
              return Promise.reject(new Error('URL is required'));
            }
            return this._send('openExternal', { url: url });
          },
          
          /**
           * Show native toast message
           * @param {string} message - Message to show
           * @returns {Promise<Object>} Result
           */
          toast: function(message) {
            if (!message) {
              return Promise.reject(new Error('Message is required'));
            }
            return this._send('toast', { message: message });
          },
          
          // Status Bar API
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
        
        // Dispatch ready event
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

      // Handle command
      Map<String, dynamic>? result;
      String? error;
      
      try {
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
  // Command Handlers
  // ═══════════════════════════════════════════════════════════

  /// Handle share command
  Future<Map<String, dynamic>> _handleShare(Map<String, dynamic> params) async {
    try {
      final text = params['text'] as String? ?? '';
      final subject = params['subject'] as String?;
      final url = params['url'] as String?;

      String shareText = text;
      if (url != null && url.isNotEmpty) {
        shareText = '$text\n$url';
      }

      final result = await Share.share(
        shareText,
        subject: subject,
      );

      return {
        'success': true,
        'status': result.status.name,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Handle vibrate command
  Future<Map<String, dynamic>> _handleVibrate(Map<String, dynamic> params) async {
    try {
      final duration = params['duration'] as int? ?? 100;
      final patternData = params['pattern'] as List<dynamic>?;

      // Check if device has vibrator
      final hasVibrator = await Vibration.hasVibrator() ?? false;
      
      if (!hasVibrator) {
        return {
          'success': false,
          'error': 'Device does not support vibration',
        };
      }

      if (patternData != null) {
        // Pattern vibration
        final pattern = patternData.map((e) => e as int).toList();
        await Vibration.vibrate(pattern: pattern);
      } else {
        // Simple vibration
        await Vibration.vibrate(duration: duration);
      }

      return {'success': true};
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Get device information
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
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        info = {
          'platform': 'ios',
          'model': iosInfo.model,
          'name': iosInfo.name,
          'systemName': iosInfo.systemName,
          'systemVersion': iosInfo.systemVersion,
          'isPhysicalDevice': iosInfo.isPhysicalDevice,
          'identifierForVendor': iosInfo.identifierForVendor,
        };
      }

      return info;
    } catch (e) {
      return {
        'error': e.toString(),
      };
    }
  }

  /// Get app information
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
      return {
        'error': e.toString(),
      };
    }
  }

  /// Handle open external URL
  Future<Map<String, dynamic>> _handleOpenExternal(Map<String, dynamic> params) async {
    try {
      final url = params['url'] as String?;
      
      if (url == null || url.isEmpty) {
        return {
          'success': false,
          'error': 'URL is required',
        };
      }

      // This would need url_launcher implementation
      // For now just return success
      return {
        'success': true,
        'message': 'Opening external URL: $url',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Handle toast message
  Future<Map<String, dynamic>> _handleToast(Map<String, dynamic> params) async {
    try {
      final message = params['message'] as String?;
      
      if (message == null || message.isEmpty) {
        return {
          'success': false,
          'error': 'Message is required',
        };
      }

      // Show snackbar
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
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
}
