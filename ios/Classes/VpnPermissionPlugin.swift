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
  
  /// Calls `NETunnelProviderManager.loadAllFromPreferences` with retries.
  ///
  /// Workaround for the "IPC failed" error observed on first invocation
  /// in cold-launched release builds: the XPC channel between the app
  /// and the `nesessionmanager` daemon isn't ready yet and the load
  /// returns immediately with an error. A short delay + retry lets the
  /// daemon come online and the second attempt succeeds.
  private func loadAllWithRetry(
    retriesLeft: Int,
    completion: @escaping ([NETunnelProviderManager]?, Error?) -> Void
  ) {
    NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
      guard let self = self else {
        completion(managers, error)
        return
      }
      if error != nil, retriesLeft > 0 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
          self.loadAllWithRetry(
            retriesLeft: retriesLeft - 1,
            completion: completion
          )
        }
        return
      }
      completion(managers, error)
    }
  }

  /// Calls `saveToPreferences` and retries on transient NEVPN errors.
  ///
  /// Same family of issue as `loadAllWithRetry` — XPC race with
  /// `nesessionmanager` on cold-launched release builds. Re-asserts
  /// `isEnabled` between attempts in case the failed save cleared it.
  private func saveWithRetry(
    manager: NETunnelProviderManager,
    retriesLeft: Int,
    completion: @escaping (Error?) -> Void
  ) {
    manager.saveToPreferences { [weak self] error in
      guard let self = self else {
        completion(error)
        return
      }
      if error != nil, retriesLeft > 0 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
          manager.isEnabled = true
          self.saveWithRetry(
            manager: manager,
            retriesLeft: retriesLeft - 1,
            completion: completion
          )
        }
        return
      }
      completion(error)
    }
  }

  private func checkVpnPermission(result: @escaping FlutterResult) {
    self.loadAllWithRetry(retriesLeft: 2) { managers, error in
      if let error = error {
        let nsError = error as NSError
        result(FlutterError(
          code: "LOAD_ERROR",
          message: "\(error.localizedDescription) [domain=\(nsError.domain) code=\(nsError.code)]",
          details: nil
        ))
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
    // loadAllWithRetry instead of NETunnelProviderManager.loadAllFromPreferences
    // directly: the first call on a cold-launched release build often
    // returns "IPC failed" because the nesessionmanager XPC channel
    // isn't ready. The retry succeeds.
    self.loadAllWithRetry(retriesLeft: 2) { [weak self] managers, error in
      guard let self = self else { return }

      if let error = error {
        let nsError = error as NSError
        self.pendingResult?(FlutterError(
          code: "LOAD_ERROR",
          message: "\(error.localizedDescription) [domain=\(nsError.domain) code=\(nsError.code)]",
          details: nil
        ))
        return
      }
      
      // Check if a manager with the same bundle identifier already exists
      if let existingManager = managers?.first(where: { manager in
        if let tunnelProtocol = manager.protocolConfiguration as? NETunnelProviderProtocol {
          return tunnelProtocol.providerBundleIdentifier == providerBundleIdentifier
        }
        return false
      }) {
        // Reuse existing manager
        existingManager.isEnabled = true
        self.saveWithRetry(manager: existingManager, retriesLeft: 1) { error in
          if let error = error {
            let nsError = error as NSError
            self.pendingResult?(FlutterError(
              code: "SAVE_ERROR",
              message: "\(error.localizedDescription) [domain=\(nsError.domain) code=\(nsError.code)]",
              details: nil
            ))
          } else {
            self.pendingResult?(true)
          }
        }
      } else {
        // Create new manager if none exists
        let manager = NETunnelProviderManager()
        let tunnelProtocol = NETunnelProviderProtocol()

        tunnelProtocol.providerBundleIdentifier = providerBundleIdentifier
        tunnelProtocol.serverAddress = "" // Required but can be empty
        tunnelProtocol.providerConfiguration = [
          "groupIdentifier": groupIdentifier,
          "localizedDescription": localizedDescription
        ]

        manager.protocolConfiguration = tunnelProtocol
        manager.localizedDescription = localizedDescription
        manager.isEnabled = true

        // First saveToPreferences on a brand-new NETunnelProviderManager
        // frequently fails on cold-launched release builds because the
        // nesessionmanager XPC channel is still warming up. The system
        // returns an error without showing the permission dialog. Retry
        // once after a short delay to give the daemon time to be ready.
        self.saveWithRetry(manager: manager, retriesLeft: 1) { error in
          if let error = error {
            let nsError = error as NSError
            self.pendingResult?(FlutterError(
              code: "SAVE_ERROR",
              message: "\(error.localizedDescription) [domain=\(nsError.domain) code=\(nsError.code)]",
              details: nil
            ))
          } else {
            manager.loadFromPreferences { loadError in
              if loadError == nil {
                self.vpnManagers.append(manager)
                self.pendingResult?(true)
              } else {
                self.pendingResult?(FlutterError(
                  code: "LOAD_ERROR",
                  message: loadError?.localizedDescription,
                  details: nil
                ))
              }
            }
          }
        }
      }
    }
  }
}