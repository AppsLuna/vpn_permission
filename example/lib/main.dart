import 'package:flutter/material.dart';
import 'package:vpn_permission/vpn_permission.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: ElevatedButton(
            onPressed: _manageVPNPermission(),
            child: const Text("Manage VPN Permission"),
          ),
        ),
      ),
    );
  }

  _manageVPNPermission() async {
    bool allowed = await VpnPermission.checkPermission();
    if (!allowed) {
      bool requested = await VpnPermission.requestPermission(
        providerBundleIdentifier: AppConstants.providerBundleIdentifier,
        groupIdentifier: AppConstants.groupIdentifier,
        localizedDescription: AppConstants.localizationDescription,
      );
      if (requested) {
        debugPrint("VPN permission granted");
      } else {
        debugPrint("VPN permission denied");
      }
    } else {
      debugPrint("VPN permission already granted");
    }
  }
}

class AppConstants {
  // package name
  static const String iOSPackageName = "com.example.vpn_permission";

  // iOS setup
  static const String providerBundleIdentifier = "$iOSPackageName.VPNExtension";
  static const String groupIdentifier = "group.$iOSPackageName";
  static const String localizationDescription = "Free VPN - Fast & Secure";
}
