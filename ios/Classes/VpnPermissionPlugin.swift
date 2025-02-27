import Flutter
import NetworkExtension
import Security

public class VpnPermissionPlugin: NSObject, FlutterPlugin {
  private var vpnManagers: [NETunnelProviderManager] = []
  private var pendingResult: FlutterResult?
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "vpn_permission", binaryMessenger: registrar.messenger())
    let instance = VpnPermissionPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "checkVpnPermission":
      checkVpnPermission(result: result)
      
    case "requestVpnPermission":
      guard let args = call.arguments as? [String: Any],
            let providerBundleIdentifier = args["providerBundleIdentifier"] as? String,
            let localizedDescription = args["localizedDescription"] as? String,
            let groupIdentifier = args["groupIdentifier"] as? String else {
        result(FlutterError(
          code: "INVALID_ARGUMENTS", 
          message: "Missing required parameters", 
          details: ["Required": "providerBundleIdentifier, localizedDescription, groupIdentifier"]
        ))
        return
      }
      pendingResult = result
      requestVpnPermission(
        providerBundleIdentifier: providerBundleIdentifier,
        localizedDescription: localizedDescription,
        groupIdentifier: groupIdentifier
      )
      
    default:
      result(FlutterMethodNotImplemented)
    }
  }
  
  private func checkVpnPermission(result: @escaping FlutterResult) {
    NETunnelProviderManager.loadAllFromPreferences { [weak self] (managers, error) in
      guard error == nil else {
        result(FlutterError(code: "LOAD_ERROR", message: error?.localizedDescription, details: nil))
        return
      }
      
      let isConnected = managers?.contains(where: { $0.connection.status == .connected }) ?? false
      result(isConnected)
    }
  }
  
  private func requestVpnPermission(
    providerBundleIdentifier: String,
    localizedDescription: String,
    groupIdentifier: String
  ) {
    let manager = NETunnelProviderManager()
    let tunnelProtocol = NETunnelProviderProtocol()
    
    // Configure tunnel protocol
    tunnelProtocol.providerBundleIdentifier = providerBundleIdentifier
    tunnelProtocol.serverAddress = "" // Required but can be empty
    tunnelProtocol.providerConfiguration = [
      "groupIdentifier": groupIdentifier,
      "localizedDescription": localizedDescription
    ]
    
    manager.protocolConfiguration = tunnelProtocol
    manager.localizedDescription = localizedDescription
    manager.isEnabled = true
    
    // Save configuration to trigger system dialog
    manager.saveToPreferences { [weak self] error in
      guard let self = self else { return }
      
      if let error = error {
        self.pendingResult?(FlutterError(
          code: "SAVE_ERROR", 
          message: error.localizedDescription, 
          details: nil
        ))
      } else {
        // Load configuration to ensure it's persisted
        manager.loadFromPreferences { error in
          if error == nil {
            self.vpnManagers.append(manager)
            self.pendingResult?(true)
          } else {
            self.pendingResult?(FlutterError(
              code: "LOAD_ERROR", 
              message: error?.localizedDescription, 
              details: nil
            ))
          }
        }
      }
    }
  }
}