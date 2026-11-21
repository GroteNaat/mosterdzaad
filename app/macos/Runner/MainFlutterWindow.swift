import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let storageQueue = DispatchQueue(label: "nl.mosterdzaad.storage")
  override func awakeFromNib() {
    let controller = FlutterViewController()
    let windowFrame = frame
    contentViewController = controller
    setFrame(windowFrame, display: true)
    title = "Mosterdzaad"
    RegisterGeneratedPlugins(registry: controller)
    let channel = FlutterMethodChannel(name: "nl.mosterdzaad/vault", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "pickFolder" {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Deze map gebruiken"
        panel.begin { response in
          guard response == .OK, let url = panel.url else { result(nil); return }
          let scoped = url.startAccessingSecurityScopedResource()
          defer { if scoped { url.stopAccessingSecurityScopedResource() } }
          do { result(try AppleVaultFiles.location(url)) }
          catch { result(FlutterError(code: "permission", message: error.localizedDescription, details: nil)) }
        }
      } else {
        self?.storageQueue.async {
          do {
            let value = try AppleVaultFiles.perform(call.method, call.arguments)
            DispatchQueue.main.async { result(value) }
          } catch { DispatchQueue.main.async { result(FlutterError(code: "storage", message: "De gekozen map is niet toegankelijk: \(error.localizedDescription)", details: nil)) } }
        }
      }
    }
    super.awakeFromNib()
  }
}

enum AppleVaultFiles {
  static func location(_ url: URL) throws -> [String: String] {
    let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    return ["kind": "apple", "token": data.base64EncodedString(), "label": url.lastPathComponent]
  }
  static func perform(_ method: String, _ arguments: Any?) throws -> Any? {
    guard let args = arguments as? [String: Any], let token = args["token"] as? String,
          let bookmark = Data(base64Encoded: token), let path = args["path"] as? String else { throw CocoaError(.fileReadInvalidFileName) }
    let parts = path.components(separatedBy: "/")
    guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.contains(":") }) else { throw CocoaError(.fileReadInvalidFileName) }
    var stale = false
    let root = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
    guard !stale, root.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
    defer { root.stopAccessingSecurityScopedResource() }

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
        case "remove":
          if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
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
