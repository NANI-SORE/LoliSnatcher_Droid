import Flutter
import Photos
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var servicesChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
  }

  private func handleServicesCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
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
