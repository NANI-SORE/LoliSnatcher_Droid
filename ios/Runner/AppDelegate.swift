import Flutter
import Photos
import UIKit
import UserNotifications
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private var servicesChannel: FlutterMethodChannel?
  private var backupDirectoryResult: FlutterResult?
  private let backupDirectoryBookmarkKey = "backupDirectoryBookmark"

  override func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void) {
    if response.notification.request.content.userInfo["downloads"] as? Bool == true {
      DownloadBackend.shared.openNotification(response.notification.request.content.userInfo)
      completionHandler()
    } else {
      super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
    }
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    DownloadBackend.shared.launch()
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(_ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
    if identifier == DownloadBackend.sessionIdentifier {
      DownloadBackend.shared.handleEvents(completionHandler)
    } else {
      super.application(application, handleEventsForBackgroundURLSession: identifier, completionHandler: completionHandler)
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LoliSnatcherServices") else {
      return
    }

    servicesChannel = FlutterMethodChannel(
      name: "com.noaisu.loliSnatcher/services",
      binaryMessenger: registrar.messenger()
    )
    servicesChannel?.setMethodCallHandler(handleServicesCall)
    DownloadBackend.shared.attach(registrar.messenger())
  }

  private func handleServicesCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "chooseBackupDirectory":
      guard backupDirectoryResult == nil else {
        result(FlutterError(code: "picker_busy", message: "A backup folder picker is already open", details: nil))
        return
      }
      backupDirectoryResult = result
      let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
      picker.delegate = self
      picker.allowsMultipleSelection = false
      var presenter = UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow })?.rootViewController }
        .first
      while let presented = presenter?.presentedViewController { presenter = presented }
      guard let presenter = presenter else {
        backupDirectoryResult = nil
        result(FlutterError(code: "picker_unavailable", message: "Could not open the folder picker", details: nil))
        return
      }
      presenter.present(picker, animated: true)
    case "copyBackupToDirectory", "listBackupDirectory", "deleteBackupFromDirectory":
      guard
        let arguments = call.arguments as? [String: Any],
        let directory = arguments["directory"] as? String
      else {
        result(FlutterError(code: "bad_args", message: "Missing backup directory", details: nil))
        return
      }
      DispatchQueue.global(qos: .utility).async {
        do {
          let folder = try self.resolvedBackupDirectory(expectedPath: directory)
          let scoped = folder.startAccessingSecurityScopedResource()
          defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
          let value: Any?
          switch call.method {
          case "copyBackupToDirectory":
            guard
              let sourcePath = arguments["sourcePath"] as? String,
              let fileName = arguments["fileName"] as? String
            else { throw BackupDirectoryError.invalidArguments }
            try self.copyBackup(sourcePath: sourcePath, fileName: fileName, to: folder)
            value = nil
          case "listBackupDirectory":
            value = try FileManager.default.contentsOfDirectory(atPath: folder.path)
          default:
            guard let fileName = arguments["fileName"] as? String else {
              throw BackupDirectoryError.invalidArguments
            }
            try self.checkBackupFileName(fileName)
            try FileManager.default.removeItem(at: folder.appendingPathComponent(fileName))
            value = nil
          }
          DispatchQueue.main.async { result(value) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "backup_directory_error", message: error.localizedDescription, details: nil))
          }
        }
      }
    case "saveFileToGallery":
      guard
        let arguments = call.arguments as? [String: Any],
        let path = arguments["path"] as? String
      else {
        result(FlutterError(code: "bad_args", message: "Missing file path", details: nil))
        return
      }

      let mediaType = arguments["mediaType"] as? String
      saveFileToGallery(path: path, mediaType: mediaType) { identifier, error in
        if let error = error {
          result(FlutterError(code: "photos_save_failed", message: error.localizedDescription, details: nil))
        } else {
          result(identifier)
        }
      }
    case "shareText":
      guard let arguments = call.arguments as? [String: Any], let text = arguments["text"] as? String else {
        result(FlutterError(code: "bad_args", message: "Missing text", details: nil))
        return
      }
      presentShareSheet(items: [text], result: result)
    case "shareFile":
      guard let arguments = call.arguments as? [String: Any], let path = arguments["path"] as? String else {
        result(FlutterError(code: "bad_args", message: "Missing file path", details: nil))
        return
      }
      guard FileManager.default.fileExists(atPath: path) else {
        result(FlutterError(code: "file_missing", message: "File not found", details: nil))
        return
      }
      var items: [Any] = [URL(fileURLWithPath: path)]
      if let text = arguments["text"] as? String, !text.isEmpty { items.append(text) }
      presentShareSheet(items: items, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func presentShareSheet(items: [Any], result: @escaping FlutterResult) {
    guard var presenter = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .filter({ $0.activationState == .foregroundActive })
      .flatMap({ $0.windows })
      .first(where: { $0.isKeyWindow })?.rootViewController
    else {
      result(FlutterError(code: "no_presenter", message: "No active window", details: nil))
      return
    }
    while let presented = presenter.presentedViewController {
      presenter = presented
    }
    guard !(presenter is UIActivityViewController), !presenter.isBeingDismissed else {
      result(FlutterError(code: "share_busy", message: "A share sheet is already open", details: nil))
      return
    }
    let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
    controller.completionWithItemsHandler = { _, completed, _, error in
      if let error = error {
        result(FlutterError(code: "share_failed", message: error.localizedDescription, details: nil))
      } else {
        result(completed)
      }
    }
    // iPad requires an anchor; leave iPhone sheet presentation to UIKit.
    if UIDevice.current.userInterfaceIdiom == .pad, let popover = controller.popoverPresentationController {
      popover.sourceView = presenter.view
      popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
      popover.permittedArrowDirections = []
    }
    presenter.present(controller, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = backupDirectoryResult else { return }
    backupDirectoryResult = nil
    guard let folder = urls.first else {
      result(nil)
      return
    }
    let scoped = folder.startAccessingSecurityScopedResource()
    defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
    do {
      let bookmark = try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
      UserDefaults.standard.set(bookmark, forKey: backupDirectoryBookmarkKey)
      result(folder.path)
    } catch {
      result(FlutterError(code: "backup_directory_error", message: error.localizedDescription, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    backupDirectoryResult?(nil)
    backupDirectoryResult = nil
  }

  private func resolvedBackupDirectory(expectedPath: String) throws -> URL {
    guard let bookmark = UserDefaults.standard.data(forKey: backupDirectoryBookmarkKey) else {
      throw BackupDirectoryError.selectAgain
    }
    var stale = false
    let folder = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    guard !stale, folder.path == expectedPath else { throw BackupDirectoryError.selectAgain }
    return folder
  }

  private func checkBackupFileName(_ name: String) throws {
    guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\") else {
      throw BackupDirectoryError.invalidArguments
    }
  }

  private func copyBackup(sourcePath: String, fileName: String, to folder: URL) throws {
    try checkBackupFileName(fileName)
    let source = URL(fileURLWithPath: sourcePath)
    let destination = folder.appendingPathComponent(fileName)
    let temporary = folder.appendingPathComponent(".\(fileName).\(UUID().uuidString).tmp")
    let manager = FileManager.default
    do {
      try manager.copyItem(at: source, to: temporary)
      if manager.fileExists(atPath: destination.path) {
        _ = try manager.replaceItemAt(destination, withItemAt: temporary)
      } else {
        try manager.moveItem(at: temporary, to: destination)
      }
    } catch {
      try? manager.removeItem(at: temporary)
      throw error
    }
  }

  private enum BackupDirectoryError: LocalizedError {
    case invalidArguments, selectAgain

    var errorDescription: String? {
      switch self {
      case .invalidArguments: return "Invalid backup file name or path"
      case .selectAgain: return "Select the backup folder again to grant access."
      }
    }
  }

  private func saveFileToGallery(
    path: String,
    mediaType: String?,
    completion: @escaping (String?, Error?) -> Void
  ) {
    let fileURL = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      completion(nil, GallerySaveError.fileNotFound)
      return
    }

    requestPhotoLibraryAddAccess { authorized in
      guard authorized else {
        completion(nil, GallerySaveError.permissionDenied)
        return
      }

      let resourceType = self.photoResourceType(for: fileURL, mediaType: mediaType)
      var identifier: String?
      PHPhotoLibrary.shared().performChanges({
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: resourceType, fileURL: fileURL, options: nil)
        identifier = request.placeholderForCreatedAsset?.localIdentifier
      }) { success, error in
        DispatchQueue.main.async {
          completion(success ? identifier : nil, error)
        }
      }
    }
  }

  private func requestPhotoLibraryAddAccess(completion: @escaping (Bool) -> Void) {
    if #available(iOS 14, *) {
      let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
      if status == .authorized || status == .limited {
        completion(true)
        return
      }

      PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
        DispatchQueue.main.async {
          completion(newStatus == .authorized || newStatus == .limited)
        }
      }
    } else {
      let status = PHPhotoLibrary.authorizationStatus()
      if status == .authorized {
        completion(true)
        return
      }

      PHPhotoLibrary.requestAuthorization { newStatus in
        DispatchQueue.main.async {
          completion(newStatus == .authorized)
        }
      }
    }
  }

  private func photoResourceType(for fileURL: URL, mediaType: String?) -> PHAssetResourceType {
    let lowerMediaType = mediaType?.lowercased() ?? ""
    let lowerExtension = fileURL.pathExtension.lowercased()
    let videoExtensions = ["mp4", "mov", "m4v", "avi", "webm"]

    if lowerMediaType.contains("video") || videoExtensions.contains(lowerExtension) {
      return .video
    }

    return .photo
  }

  private enum GallerySaveError: LocalizedError {
    case fileNotFound
    case permissionDenied

    var errorDescription: String? {
      switch self {
      case .fileNotFound:
        return "File not found"
      case .permissionDenied:
        return "Photo library add permission was denied"
      }
    }
  }
}
