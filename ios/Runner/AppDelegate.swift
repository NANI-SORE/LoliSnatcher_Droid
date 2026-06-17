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

    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LoliSnatcherServices")
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
      saveFileToGallery(path: path, mediaType: mediaType) { success, error in
        if let error = error {
          result(FlutterError(code: "photos_save_failed", message: error.localizedDescription, details: nil))
        } else {
          result(success)
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func saveFileToGallery(
    path: String,
    mediaType: String?,
    completion: @escaping (Bool, Error?) -> Void
  ) {
    let fileURL = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      completion(false, GallerySaveError.fileNotFound)
      return
    }

    requestPhotoLibraryAddAccess { authorized in
      guard authorized else {
        completion(false, GallerySaveError.permissionDenied)
        return
      }

      let resourceType = self.photoResourceType(for: fileURL, mediaType: mediaType)
      PHPhotoLibrary.shared().performChanges({
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: resourceType, fileURL: fileURL, options: nil)
      }) { success, error in
        DispatchQueue.main.async {
          completion(success, error)
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
