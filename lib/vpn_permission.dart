import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class VpnPermission {
  static const MethodChannel _channel = MethodChannel('vpn_permission');

  // Request permission with dynamic iOS parameters
  static Future<bool> requestPermission({
    // Android doesn't need these, but iOS requires them
    String? providerBundleIdentifier,
    String? groupIdentifier,
    String? localizedDescription,
  }) async {
    try {
      if (Platform.isIOS) {
        // Validate required parameters for iOS
        assert(providerBundleIdentifier != null, "ProviderBundleIdentifier is required for iOS");
        assert(groupIdentifier != null, "GroupIdentifier is required for iOS");
        assert(localizedDescription != null, "LocalizedDescription is required for iOS");

        return await _channel.invokeMethod('requestVpnPermission', {
          'providerBundleIdentifier': providerBundleIdentifier,
          'groupIdentifier': groupIdentifier,
          'localizedDescription': localizedDescription,
        });
      } else {
        // Android: No parameters needed
        return await _channel.invokeMethod('requestVpnPermission');
      }
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print("Error: ${e.message}");
      }
      return false;
    }
  }

  // Check permission status
  static Future<bool> checkPermission() async {
    try {
      return await _channel.invokeMethod('checkVpnPermission');
    } on PlatformException {
      return false;
    }
  }
}
