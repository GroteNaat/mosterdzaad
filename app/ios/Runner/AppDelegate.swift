import Flutter
import UIKit
import UniformTypeIdentifiers
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var vaultBridge: VaultBridge?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    WorkmanagerPlugin.registerLaunchHandlers()
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerBGProcessingTask(withIdentifier: "nl.mosterdzaad.sync")
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MosterdzaadVault") {
      let bridge = VaultBridge()
      vaultBridge = bridge
      let channel = FlutterMethodChannel(name: "nl.mosterdzaad/vault", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler(bridge.handle)
    }
  }
}

final class VaultBridge: NSObject, UIDocumentPickerDelegate {
  private var pending: FlutterResult?
  private let queue = DispatchQueue(label: "nl.mosterdzaad.storage")
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "pickFolder" {
      guard pending == nil else { result(FlutterError(code: "busy", message: "Er staat al een mapkiezer open.", details: nil)); return }
      guard var host = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
        result(FlutterError(code: "picker", message: "Geen venster beschikbaar.", details: nil)); return
      }
      while let presented = host.presentedViewController { host = presented }
      pending = result
      let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
      picker.delegate = self
      picker.allowsMultipleSelection = false
      picker.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
      host.present(picker, animated: true)
      return
    }
    queue.async {
      do {
        let value = try AppleVaultFiles.perform(call.method, call.arguments)
        DispatchQueue.main.async { result(value) }
      } catch { DispatchQueue.main.async { result(FlutterError(code: "storage", message: "De gekozen map is niet toegankelijk: \(error.localizedDescription)", details: nil)) } }
    }
  }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { pending?(nil); pending = nil }
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = pending else { return }
    pending = nil
    do {
      guard let url = urls.first else { throw CocoaError(.fileReadNoPermission) }
      let scoped = url.startAccessingSecurityScopedResource()
      guard scoped || AppleVaultFiles.isInsideContainer(url) else { throw CocoaError(.fileReadNoPermission) }
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      result(try AppleVaultFiles.location(url))
    } catch { result(FlutterError(code: "permission", message: error.localizedDescription, details: nil)) }
  }
}

enum AppleVaultFiles {
  // A user-selected location within our own Documents folder needs no sandbox extension.
  static func isInsideContainer(_ url: URL) -> Bool {
    let container = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path
    return url.resolvingSymlinksInPath().path.hasPrefix(container + "/")
  }
  static func location(_ url: URL) throws -> [String: String] {
    let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    return ["kind": "apple", "token": data.base64EncodedString(), "label": url.lastPathComponent]
  }
  static func perform(_ method: String, _ arguments: Any?) throws -> Any? {
    guard let args = arguments as? [String: Any], let token = args["token"] as? String,
          let bookmark = Data(base64Encoded: token), let path = args["path"] as? String else { throw CocoaError(.fileReadInvalidFileName) }
    let parts = path.components(separatedBy: "/")
    guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.contains(":") }) else { throw CocoaError(.fileReadInvalidFileName) }
    var stale = false
    let root = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    guard !stale else { throw CocoaError(.fileReadNoPermission) }
    let scoped = root.startAccessingSecurityScopedResource()
    guard scoped || isInsideContainer(root) else { throw CocoaError(.fileReadNoPermission) }
    defer { if scoped { root.stopAccessingSecurityScopedResource() } }

    var coordinationError: NSError?
    var operationError: Error?
    var output: Any?
    let operation: (URL) -> Void = { coordinatedRoot in
      let url = parts.reduce(coordinatedRoot) { $0.appendingPathComponent($1) }
      do {
        let fm = FileManager.default
        switch method {
        case "createChild", "makeDirectory":
          if method == "createChild" && fm.fileExists(atPath: url.path) { throw CocoaError(.fileWriteFileExists) }
          try fm.createDirectory(at: url, withIntermediateDirectories: false)
          output = method == "createChild" ? try location(url) : nil
        case "list":
          output = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).map { $0.lastPathComponent }
        case "read":
          if fm.fileExists(atPath: url.path) {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true, (values.fileSize ?? 0) <= 8 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
            output = try String(contentsOf: url, encoding: .utf8)
          }
        case "writeNew":
          guard let text = args["contents"] as? String else { throw CocoaError(.fileWriteUnknown) }
          try Data(text.utf8).write(to: url, options: .withoutOverwriting)
        default: throw CocoaError(.featureUnsupported)
        }
      } catch { operationError = error }
    }
    let coordinator = NSFileCoordinator()
    if method == "read" || method == "list" {
      coordinator.coordinate(readingItemAt: root, options: [], error: &coordinationError, byAccessor: operation)
    } else {
      coordinator.coordinate(writingItemAt: root, options: .forMerging, error: &coordinationError, byAccessor: operation)
    }
    if let error = coordinationError { throw error }
    if let error = operationError { throw error }
    return output
  }
}
