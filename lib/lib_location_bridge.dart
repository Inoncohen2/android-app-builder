import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationBridge {
  final WebViewController controller;
  final BuildContext context;
  
  StreamSubscription<Position>? _positionStream;
  String? _watchCallbackId;

  LocationBridge(this.controller, this.context);

  /// Handle incoming location commands
  Future<Map<String, dynamic>> handleCommand(String command, Map<String, dynamic> params) async {
    try {
      switch (command) {
        case 'location.getCurrentPosition':
          return await _getCurrentPosition(params);
        case 'location.watchPosition':
          return await _watchPosition(params);
        case 'location.clearWatch':
          return await _clearWatch();
        case 'location.distanceTo':
          return await _distanceTo(params);
        case 'location.checkPermission':
          return await _checkPermission();
        case 'location.requestPermission':
          return await _requestPermission();
        case 'location.isLocationServiceEnabled':
          return await _isLocationServiceEnabled();
        case 'location.openSettings':
          return await _openSettings();
        default:
          return {'success': false, 'error': 'Unknown location command: $command'};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Get current position once
  Future<Map<String, dynamic>> _getCurrentPosition(Map<String, dynamic> params) async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return {
          'success': false,
          'error': 'Location services are disabled',
          'serviceDisabled': true,
        };
      }

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return {
            'success': false,
            'error': 'Location permission denied',
            'needsPermission': true,
          };
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return {
          'success': false,
          'error': 'Location permission permanently denied',
          'permanentlyDenied': true,
        };
      }

      // Get accuracy settings
      final highAccuracy = params['enableHighAccuracy'] as bool? ?? true;
      final timeout = params['timeout'] as int? ?? 30000;
      final maximumAge = params['maximumAge'] as int? ?? 0;

      // Set location settings
      final LocationSettings locationSettings = LocationSettings(
        accuracy: highAccuracy ? LocationAccuracy.best : LocationAccuracy.medium,
        distanceFilter: 0,
        timeLimit: Duration(milliseconds: timeout),
      );

      // Get position
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
      );

      return {
        'success': true,
        'position': _positionToMap(position),
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Watch position continuously
  Future<Map<String, dynamic>> _watchPosition(Map<String, dynamic> params) async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return {
          'success': false,
          'error': 'Location services are disabled',
          'serviceDisabled': true,
        };
      }

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return {
            'success': false,
            'error': 'Location permission denied',
            'needsPermission': true,
          };
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return {
          'success': false,
          'error': 'Location permission permanently denied',
          'permanentlyDenied': true,
        };
      }

      // Get options
      final highAccuracy = params['enableHighAccuracy'] as bool? ?? true;
      final distanceFilter = params['distanceFilter'] as int? ?? 10;
      final callbackId = params['callbackId'] as String?;

      if (callbackId == null) {
        return {
          'success': false,
          'error': 'callbackId is required',
        };
      }

      // Cancel existing watch if any
      await _positionStream?.cancel();

      // Store callback ID
      _watchCallbackId = callbackId;

      // Set location settings
      final LocationSettings locationSettings = LocationSettings(
        accuracy: highAccuracy ? LocationAccuracy.best : LocationAccuracy.medium,
        distanceFilter: distanceFilter,
      );

      // Start watching position
      _positionStream = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
          _sendPositionUpdate(position);
        },
        onError: (error) {
          _sendPositionError(error.toString());
        },
      );

      return {
        'success': true,
        'message': 'Started watching position',
        'watchId': callbackId,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Clear position watch
  Future<Map<String, dynamic>> _clearWatch() async {
    try {
      await _positionStream?.cancel();
      _positionStream = null;
      _watchCallbackId = null;

      return {
        'success': true,
        'message': 'Stopped watching position',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Calculate distance to coordinates
  Future<Map<String, dynamic>> _distanceTo(Map<String, dynamic> params) async {
    try {
      // Get current position first
      final currentResult = await _getCurrentPosition({});
      if (!currentResult['success']) {
        return currentResult;
      }

      final currentPos = currentResult['position'] as Map<String, dynamic>;
      final currentLat = currentPos['latitude'] as double;
      final currentLon = currentPos['longitude'] as double;

      // Get target coordinates
      final targetLat = params['latitude'] as double?;
      final targetLon = params['longitude'] as double?;

      if (targetLat == null || targetLon == null) {
        return {
          'success': false,
          'error': 'latitude and longitude are required',
        };
      }

      // Calculate distance in meters
      final distance = Geolocator.distanceBetween(
        currentLat,
        currentLon,
        targetLat,
        targetLon,
      );

      // Calculate bearing
      final bearing = Geolocator.bearingBetween(
        currentLat,
        currentLon,
        targetLat,
        targetLon,
      );

      return {
        'success': true,
        'distance': distance,
        'distanceKm': (distance / 1000).toStringAsFixed(2),
        'distanceMiles': (distance / 1609.34).toStringAsFixed(2),
        'bearing': bearing,
        'from': {
          'latitude': currentLat,
          'longitude': currentLon,
        },
        'to': {
          'latitude': targetLat,
          'longitude': targetLon,
        },
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Check location permission
  Future<Map<String, dynamic>> _checkPermission() async {
    try {
      final permission = await Geolocator.checkPermission();
      
      return {
        'success': true,
        'permission': permission.name,
        'granted': permission == LocationPermission.always || 
                   permission == LocationPermission.whileInUse,
        'denied': permission == LocationPermission.denied,
        'deniedForever': permission == LocationPermission.deniedForever,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Request location permission
  Future<Map<String, dynamic>> _requestPermission() async {
    try {
      final permission = await Geolocator.requestPermission();
      
      return {
        'success': true,
        'permission': permission.name,
        'granted': permission == LocationPermission.always || 
                   permission == LocationPermission.whileInUse,
        'denied': permission == LocationPermission.denied,
        'deniedForever': permission == LocationPermission.deniedForever,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Check if location services are enabled
  Future<Map<String, dynamic>> _isLocationServiceEnabled() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      
      return {
        'success': true,
        'enabled': enabled,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Open location settings
  Future<Map<String, dynamic>> _openSettings() async {
    try {
      final opened = await Geolocator.openLocationSettings();
      
      return {
        'success': true,
        'opened': opened,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Convert Position to Map
  Map<String, dynamic> _positionToMap(Position position) {
    return {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'altitude': position.altitude,
      'altitudeAccuracy': position.altitudeAccuracy,
      'heading': position.heading,
      'headingAccuracy': position.headingAccuracy,
      'speed': position.speed,
      'speedAccuracy': position.speedAccuracy,
      'timestamp': position.timestamp.millisecondsSinceEpoch,
    };
  }

  /// Send position update to JavaScript
  Future<void> _sendPositionUpdate(Position position) async {
    if (_watchCallbackId == null) return;

    try {
      final positionJson = jsonEncode(_positionToMap(position));
      
      final script = '''
        (function() {
          if (window.web2app && window.web2app._handlePositionUpdate) {
            window.web2app._handlePositionUpdate('$_watchCallbackId', $positionJson);
          }
        })();
      ''';
      
      await controller.runJavaScript(script);
    } catch (e) {
      print('❌ Failed to send position update: $e');
    }
  }

  /// Send position error to JavaScript
  Future<void> _sendPositionError(String error) async {
    if (_watchCallbackId == null) return;

    try {
      final errorJson = jsonEncode(error);
      
      final script = '''
        (function() {
          if (window.web2app && window.web2app._handlePositionError) {
            window.web2app._handlePositionError('$_watchCallbackId', $errorJson);
          }
        })();
      ''';
      
      await controller.runJavaScript(script);
    } catch (e) {
      print('❌ Failed to send position error: $e');
    }
  }

  /// Cleanup
  void dispose() {
    _positionStream?.cancel();
  }
}
