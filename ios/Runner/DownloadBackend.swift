import Flutter
import Foundation
import CryptoKit
import Photos
import UIKit
import UserNotifications
import BackgroundTasks

final class DownloadBackend: NSObject, URLSessionDownloadDelegate {
  static let shared = DownloadBackend()
  static let sessionIdentifier = "com.noaisu.loliSnatcher.downloads.v1"
  let queue = DispatchQueue(label: "downloads.ledger")
  let root: URL
  private var ledger: DownloadLedger?
  private var channel: FlutterMethodChannel?
  private var externalLeases = Set<String>()
  private var live = [String: URLSessionDownloadTask]()
  private var reconciling = true
  private var backgroundCompletion: (() -> Void)?
  private var publishing = Set<String>()
  private var timer: DispatchSourceTimer?
  private var continuation: AnyObject?
  private var continuationRegistered = false
  private var pendingOpen: [String: String]?
  func openNotification(_ info: [AnyHashable: Any]) {
    queue.async { self.pendingOpen = ["batchId": info["batchId"] as? String ?? ""] }
  }
  private var lastProgress = [String: Double]()
  private lazy var session: URLSession = {
    let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
    config.sessionSendsLaunchEvents = true
    config.isDiscretionary = false
    config.waitsForConnectivity = true
    config.timeoutIntervalForRequest = 60
    config.timeoutIntervalForResource = 7 * 24 * 60 * 60
    config.httpMaximumConnectionsPerHost = 1
    config.httpCookieStorage = .shared
    config.httpShouldSetCookies = true
    let delegates = OperationQueue()
    delegates.maxConcurrentOperationCount = 1
    return URLSession(configuration: config, delegate: self, delegateQueue: delegates)
  }()

  private override init() {
    root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("download_runtime", isDirectory: true)
    super.init()
    do {
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
        attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
      var excluded = root
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try excluded.setResourceValues(values)
      ledger = try DownloadLedger(url: root.appendingPathComponent("native.sqlite"))
    } catch { ledger = nil }
  }

  func launch() {
    registerContinuation()
    queue.sync { self.restoreCookies() }
    _ = session
    session.getAllTasks { tasks in
      self.queue.async {
        do {
          guard let ledger = self.ledger else { return }
          for task in tasks {
            guard let task = task as? URLSessionDownloadTask, let description = task.taskDescription,
              let row = try ledger.record(description), row["state"] as? String == "downloading" else {
              task.cancel(); continue
            }
            self.live[description] = task
            if task.state == .suspended { task.resume() }
          }
          // Give already queued delegate receipts priority before deciding an
          // intent has no system-owned task. Staged files win over resubmission.
          self.queue.asyncAfter(deadline: .now() + 2) {
            self.reconciling = false
            self.recover()
            self.pump()
          }
          let timer = DispatchSource.makeTimerSource(queue: self.queue)
          timer.schedule(deadline: .now(), repeating: 1)
          timer.setEventHandler { self.pump() }
          timer.resume()
          self.timer = timer
        } catch { self.attention("storage", batch: nil) }
      }
    }
  }

  func attach(_ messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "lolisnatcher/downloads", binaryMessenger: messenger)
    channel?.setMethodCallHandler { call, result in
      if call.method == "requestPermissions" {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in DispatchQueue.main.async { result(nil) } }
        return
      }
      if call.method == "beginDiscovery" { self.beginDiscovery(); result(nil); return }
      if call.method == "endDiscovery" { self.endDiscovery(); result(nil); return }
      if call.method == "discoveryProgress" {
        let args = call.arguments as? [String: Any] ?? [:]
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), let task = self.continuation as? BGContinuedProcessingTask {
          task.progress.totalUnitCount = max(1, (args["requested"] as? NSNumber)?.int64Value ?? 1)
          task.progress.completedUnitCount = (args["selected"] as? NSNumber)?.int64Value ?? 0
        }
        #endif
        if args["done"] as? Bool == true { self.endDiscovery() }
        result(nil); return
      }
      self.queue.async {
        do {
          guard let ledger = self.ledger else { throw DownloadError.storage }
          let args = call.arguments as? [String: Any] ?? [:]
          var value: Any?
          switch call.method {
          case "runtimeDirectory": value = self.root.path
          case "consumeOpen": value = self.pendingOpen; self.pendingOpen = nil
          case "start", "refresh": self.recover(); self.pump(); value = "running"
          case "executionState": value = "running"
          case "submit": try self.submit(args)
          case "configure":
            try self.configureCookies(args)
            try ledger.save(["id": "configuration", "profiles": args["profiles"] ?? [:], "generation": args["generation"] ?? ""], kind: "configuration")
            self.pump()
          case "cookies":
            if let raw = call.arguments as? String, let url = URL(string: raw) {
              let cookies = (HTTPCookieStorage.shared.cookies(for: url) ?? []).sorted { $0.path.count > $1.path.count }
              value = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"] ?? ""
            } else { value = "" }
          case "setCookies":
            if args["generation"] as? String == (try ledger.record("configuration")?["generation"] as? String),
                let raw = args["url"] as? String, let url = URL(string: raw) {
              for header in args["cookies"] as? [String] ?? [] {
                let cookies = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": header], for: url)
                HTTPCookieStorage.shared.setCookies(cookies, for: url, mainDocumentURL: url)
                for cookie in cookies { try self.persistCookie(cookie) }
              }
              value = true
            } else { value = false }
          case "syncBatch":
            guard let id = args["id"] as? String else { throw DownloadError.invalidDescriptor }
            try ledger.save(["id": "batch:" + id, "batchId": id, "expected": args["expected"] ?? 0,
              "done": args["done"] ?? false, "notifications": args["notifications"] ?? true], kind: "batch")
            try self.checkCompletion(id)
          case "progress":
            var rows = try ledger.records("kind = 'transfer' AND state IN ('downloading','publishing')", limit: 4)
            rows += try ledger.records("kind = 'transfer' AND state = 'queued' AND due > 0", limit: 96)
            value = rows.map { row in
              ["taskId": row["taskId"] ?? "", "attemptId": row["attemptId"] ?? "", "state": row["state"] ?? "",
               "received": row["received"] ?? 0, "total": row["total"] ?? 0, "due": row["due"] ?? 0, "error": row["error"] ?? ""]
            }
          case "retryPhotos":
            guard let taskId = args["taskId"] as? String else { throw DownloadError.invalidDescriptor }
            var digest = args["digest"] as? String
            if digest == nil, let latest = try ledger.record("latest:" + taskId)?["attempt"] as? String,
                let row = try ledger.record(latest) { digest = row["digest"] as? String }
            guard let digest = digest, digest.count == 64, digest.allSatisfy({ $0.isHexDigit }) else { throw DownloadError.invalidDescriptor }
            let key = "photos:" + digest
            if try ledger.record(key)?["state"] as? String == "intent" { try ledger.remove(key) }
          case "receipts": value = try ledger.records("kind = 'receipt'")
          case "acknowledge":
            for id in call.arguments as? [String] ?? [] { try ledger.remove(id) }
          case "command": try self.command(args)
          case "forgetBatch":
            guard let batch = args["batchId"] as? String else { throw DownloadError.invalidDescriptor }
            let predicate = "kind = 'transfer' AND json_extract(payload,'$.batchId') = ?"
            if try ledger.count(predicate + " AND state IN ('publishing','downloading','submitting')", [batch]) > 0 {
              throw DownloadError.publicationAmbiguous
            }
            while true {
              let rows = try ledger.records(predicate, [batch])
              if rows.isEmpty { break }
              for row in rows {
                let id = row["id"] as! String
                try ledger.remove(id)
                if let task = row["taskId"] as? String { try ledger.remove("latest:" + task) }
                // Only internal staging files; published destinations and
                // Photos receipts are deliberately retained.
                for suffix in ["complete", "resume"] {
                  try? FileManager.default.removeItem(at: self.root.appendingPathComponent("\(id).\(suffix)"))
                }
              }
            }
            try ledger.remove("batch:" + batch)
          case "fence":
            for (key, value) in args {
              if key == "command" { continue }
              let id = "fence:" + key
              let previous = try ledger.record(id)?["generation"] as? Int ?? 0
              try ledger.save(["id": id, "generation": max(previous, value as? Int ?? 0),
                "state": args["command"] as? String == "cancel" ? "cancelled" : "paused", "pending": true], kind: "fence")
            }
          case "fences": value = try ledger.records("kind = 'fence' AND json_extract(payload,'$.pending') = 1")
          case "acknowledgeFences":
            for id in call.arguments as? [String] ?? [] {
              if var row = try ledger.record(id) { row["pending"] = false; try ledger.save(row, kind: "fence") }
            }
          case "acquireSite":
            let scopes = ["site:\(args["site"] ?? "")", "host:\(args["host"] ?? "")"]
            let occupied = try self.occupiedScopes()
            let deadline = try ledger.deadline(scopes + ["nativeGlobal"])
            let granted = self.live.isEmpty && self.externalLeases.count / 2 < 3 &&
              scopes.allSatisfy { !occupied.contains($0) && !self.externalLeases.contains($0) } &&
              deadline <= Date().timeIntervalSince1970
            if granted {
              self.externalLeases.formUnion(scopes)
              try ledger.deferUntil(scopes, Date().timeIntervalSince1970 + max(1, (args["delayMs"] as? Double ?? 1000) / 1000))
            }
            value = granted
          case "releaseSite":
            self.externalLeases.remove("site:\(args["site"] ?? "")")
            self.externalLeases.remove("host:\(args["host"] ?? "")")
            let floor = try ledger.record("nativeFloor")?["seconds"] as? Double ?? 1
            try ledger.deferUntil(["nativeGlobal"], Date().timeIntervalSince1970 + floor)
            self.pump()
          case "alert":
            try self.notifyOnce(id: args["id"] as? String ?? UUID().uuidString,
              complete: args["complete"] as? Bool == true, batch: args["batchId"] as? String)
          case "publishForeground":
            guard let path = args["path"] as? String else { throw DownloadError.invalidDescriptor }
            self.photos(args, file: URL(fileURLWithPath: path)) { error in
              DispatchQueue.main.async {
                if let error = error { result(FlutterError(code: String(describing: error), message: "Publication needs attention", details: nil)) }
                else { result(nil) }
              }
            }
            return
          default:
            DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
            return
          }
          DispatchQueue.main.async { result(value) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "download_storage", message: "Downloads need attention", details: nil)) }
        }
      }
    }
  }

  private func submit(_ intent: [String: Any]) throws {
    guard let ledger = ledger, let payload = intent["payload"] as? [String: Any],
      let taskId = payload["id"] as? String, let attempt = intent["attemptId"] as? String,
      let rawURL = payload["url"] as? String, let url = URL(string: rawURL),
      ["https", "http"].contains(url.scheme ?? ""), let host = url.host,
      let site = payload["sourceKey"] as? String else { throw DownloadError.invalidDescriptor }
    let id = taskId + ":" + attempt
    if try ledger.record(id) != nil { return }
    let taskFence = try ledger.record("fence:task:" + taskId)
    let batchFence = try ledger.record("fence:batch:" + (payload["batchId"] as? String ?? ""))
    let blockingFence = (intent["generation"] as? Int ?? 0) < (taskFence?["generation"] as? Int ?? 0) ? taskFence :
      (intent["batchGeneration"] as? Int ?? 0) < (batchFence?["generation"] as? Int ?? 0) ? batchFence : nil
    if let fence = blockingFence {
      try ledger.save(["id": "receipt:fenced:" + id, "taskId": taskId, "attemptId": attempt,
        "state": fence["state"] as? String ?? "paused"], kind: "receipt")
      return
    }
    if payload["foregroundOnly"] as? Bool == true { throw DownloadError.invalidDescriptor }
    var row: [String: Any] = ["id": id, "taskId": taskId, "attemptId": attempt,
      "batchId": payload["batchId"] ?? "", "site": site, "host": host, "state": "queued", "payload": payload,
      "generation": intent["generation"] ?? 0, "attempts": max(0, (intent["attempts"] as? Int ?? 1) - 1), "due": 0.0]
    let floor = try ledger.record("nativeFloor")?["seconds"] as? Double ?? 1
    try ledger.save(["id": "nativeFloor", "seconds": max(floor, (payload["cooldownMs"] as? Double ?? 1000) / 1000)], kind: "policy")
    // A retry of publication reuses durable bytes and receipts from the
    // preceding attempt; it does not create another URLSession transfer.
    let old = try ledger.records("kind = 'transfer' AND json_extract(payload,'$.taskId') = ?", [taskId])
    for previous in old {
      if ["publishing", "submitting", "downloading", "queued"].contains(previous["state"] as? String ?? "") { throw DownloadError.publicationAmbiguous }
      if ["needsAction", "staged"].contains(previous["state"] as? String ?? ""),
          intent["stage"] as? String != "", let stage = previous["staged"] as? String, FileManager.default.fileExists(atPath: stage) {
        row["staged"] = stage
        row["state"] = "staged"
        row["destination"] = previous["destination"]
      }
      if previous["state"] as? String == "paused", payload["overwrite"] as? Bool != true,
          let oldID = previous["id"] as? String {
        let oldResume = root.appendingPathComponent("\(oldID).resume")
        if FileManager.default.fileExists(atPath: oldResume.path) {
          try? FileManager.default.copyItem(at: oldResume, to: root.appendingPathComponent("\(id).resume"))
        }
      }
    }
    try ledger.transaction {
      try ledger.save(row)
      try ledger.save(["id": "latest:" + taskId, "attempt": id], kind: "latest")
    }
    pump()
  }

  private func occupiedScopes() throws -> Set<String> {
    guard let ledger = ledger else { throw DownloadError.storage }
    var scopes = externalLeases
    for id in live.keys {
      if let row = try ledger.record(id) {
        scopes.insert("site:\(row["site"] ?? "")"); scopes.insert("host:\(row["host"] ?? "")")
      }
    }
    return scopes
  }

  private func cookieID(_ cookie: HTTPCookie) -> String {
    let data = Data("\(cookie.domain)\n\(cookie.path)\n\(cookie.name)".utf8)
    return "cookie:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
  private func persistCookie(_ cookie: HTTPCookie) throws {
    guard let ledger = ledger else { throw DownloadError.storage }
    if let expiry = cookie.expiresDate, expiry <= Date() { try ledger.remove(cookieID(cookie)); return }
    try ledger.save(["id": cookieID(cookie), "name": cookie.name, "value": cookie.value,
      "domain": cookie.domain, "path": cookie.path, "secure": cookie.isSecure,
      "expires": (cookie.expiresDate?.timeIntervalSince1970 ?? 0) * 1000], kind: "cookie")
  }
  private func cookie(_ row: [String: Any]) -> HTTPCookie? {
    guard let name = row["name"] as? String, let value = row["value"] as? String,
      let domain = row["domain"] as? String else { return nil }
    let hostOnly = row["hostOnly"] as? Bool
    var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .path: row["path"] as? String ?? "/",
      .domain: hostOnly == false && !domain.hasPrefix(".") ? "." + domain : domain]
    if row["secure"] as? Bool == true { properties[.secure] = "TRUE" }
    if let expires = row["expires"] as? Double, expires > 0 {
      if expires / 1000 <= Date().timeIntervalSince1970 { return nil }
      properties[.expires] = Date(timeIntervalSince1970: expires / 1000)
    }
    return HTTPCookie(properties: properties)
  }
  private func restoreCookies() {
    guard let ledger = ledger else { return }
    do {
      var last = ""
      while true {
        let rows = try ledger.records("kind = 'cookie' AND id > ?", [last])
        for row in rows {
          if let cookie = cookie(row) { HTTPCookieStorage.shared.setCookie(cookie) }
          last = row["id"] as? String ?? last
        }
        if rows.count < 100 { break }
      }
    } catch { attention("authentication", batch: nil) }
  }
  private func configureCookies(_ args: [String: Any]) throws {
    guard let ledger = ledger else { throw DownloadError.storage }
    let values = args["cookies"] as? [[String: Any]] ?? []
    for host in args["cookieHosts"] as? [String] ?? [] {
      let scoped = values.filter { row in
        let domain = (row["domain"] as? String ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return domain == host || (!domain.isEmpty && host.hasSuffix("." + domain))
      }
      let data = try JSONSerialization.data(withJSONObject: scoped, options: [.sortedKeys])
      let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      let id = "cookieSeed:" + host
      if try ledger.record(id)?["fingerprint"] as? String == fingerprint { continue }
      for existing in HTTPCookieStorage.shared.cookies ?? [] {
        let domain = existing.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if domain == host || host.hasSuffix("." + domain) {
          HTTPCookieStorage.shared.deleteCookie(existing)
          try ledger.remove(cookieID(existing))
        }
      }
      for row in scoped {
        if let cookie = cookie(row) { HTTPCookieStorage.shared.setCookie(cookie); try persistCookie(cookie) }
      }
      try ledger.save(["id": id, "fingerprint": fingerprint], kind: "cookieSeed")
    }
  }

  private func recover() {
    guard !reconciling, let ledger = ledger else { return }
    do {
      for var row in try ledger.records("kind = 'transfer' AND state IN ('submitting','downloading','staged','publishing')") {
        let id = row["id"] as! String
        if live[id] != nil || publishing.contains(id) { continue }
        let staged = root.appendingPathComponent("\(id).complete")
        if FileManager.default.fileExists(atPath: staged.path) { row["staged"] = staged.path; row["state"] = "staged" }
        else if row["destination"] == nil { row["state"] = "queued" }
        try ledger.save(row)
        if row["state"] as? String == "staged" || row["state"] as? String == "publishing" { publish(row) }
      }
    } catch { attention("storage", batch: nil) }
  }

  private func pump() {
    guard !reconciling, let ledger = ledger else { return }
    do {
      for row in try ledger.records("kind = 'transfer' AND state = 'staged'") {
        if publishing.count >= 3 { break }
        publish(row)
      }
      var occupied = try occupiedScopes()
      let candidates = try ledger.records("kind = 'transfer' AND state = 'queued'", groupBySite: true).map { row -> ([String: Any], Double) in
        let scopes = ["site:\(row["site"] ?? "")", "host:\(row["host"] ?? "")", "nativeGlobal"]
        return (row, max(try ledger.deadline(scopes), row["due"] as? Double ?? 0))
      }.sorted { $0.1 < $1.1 }
      for candidate in candidates {
        var row = candidate.0
        if publishing.count >= 3 { break }
        // Background URLSession follows redirects without calling a redirect
        // delegate. Reserve the native lane globally, including foreground
        // discovery, so an unannounced CDN redirect cannot escape host pacing.
        if !live.isEmpty || !externalLeases.isEmpty { break }
        let id = row["id"] as! String
        let scopes = ["site:\(row["site"] ?? "")", "host:\(row["host"] ?? "")"]
        if scopes.contains(where: occupied.contains) { continue }
        let payload = row["payload"] as! [String: Any]
        let transport = payload["transport"] as? [String: Any] ?? [:]
        let profiles = try ledger.record("configuration")?["profiles"] as? [String: String] ?? [:]
        if let profile = transport["profile"] as? String, profiles[row["site"] as? String ?? ""] != profile {
          try finish(&row, state: "needsAction", error: "configurationChanged"); continue
        }
        guard let url = URL(string: payload["url"] as? String ?? "") else { throw DownloadError.invalidDescriptor }
        let deadline = candidate.1
        let destination = payload["destination"] as? [String: Any] ?? [:]
        if payload["overwrite"] as? Bool != true, let directory = destination["path"] as? String,
            let filename = payload["filename"] as? String {
          let existing = URL(fileURLWithPath: directory).appendingPathComponent(filename)
          if FileManager.default.fileExists(atPath: existing.path) {
            row["staged"] = existing.path; row["destination"] = existing.path
            row["existing"] = true; row["state"] = "staged"
            try ledger.save(row); publish(row); continue
          }
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in payload["headers"] as? [String: String] ?? [:] {
          // URLSession re-evaluates domain/path/secure cookie scope at redirects.
          // A manually supplied Cookie header would bypass that protection.
          if key.lowercased() != "cookie" { request.setValue(value, forHTTPHeaderField: key) }
        }
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        row["state"] = "submitting"
        row["attempts"] = (row["attempts"] as? Int ?? 0) + 1
        try ledger.save(row) // Submission intent precedes task creation.
        let resumeURL = root.appendingPathComponent("\(id).resume")
        let task: URLSessionDownloadTask
        if let data = try? Data(contentsOf: resumeURL) { task = session.downloadTask(withResumeData: data) }
        else { task = session.downloadTask(with: request) }
        task.taskDescription = id
        // One outstanding task per site/host makes a completion-based deadline
        // enforce spacing even when the OS delays actual network admission.
        task.earliestBeginDate = Date(timeIntervalSince1970: max(Date().timeIntervalSince1970, deadline))
        row["state"] = "downloading"
        row["nativeTaskId"] = task.taskIdentifier
        try ledger.save(row)
        live[id] = task
        occupied.formUnion(scopes)
        task.resume()
      }
    } catch { attention("storage", batch: nil) }
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    // The temporary URL expires when this delegate returns.
    queue.sync {
      guard let id = downloadTask.taskDescription, let ledger = ledger else { return }
      do {
        guard var row = try ledger.record(id) else { return }
        if row["nativeTaskId"] as? Int != downloadTask.taskIdentifier { return }
        if ["paused", "cancelled"].contains(row["state"] as? String ?? "") { return }
        let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 || code == 206 else {
          try failed(&row, status: code, response: downloadTask.response as? HTTPURLResponse, error: nil); return
        }
        let stage = root.appendingPathComponent("\(id).complete")
        if FileManager.default.fileExists(atPath: stage.path) { try FileManager.default.removeItem(at: stage) }
        try FileManager.default.moveItem(at: location, to: stage)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: stage.path)
        row["staged"] = stage.path
        row["state"] = "staged"
        try ledger.save(row)
        publish(row)
      } catch { attention("storage", batch: nil) }
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    queue.async {
      guard let id = task.taskDescription, let ledger = self.ledger else { return }
      if self.live[id]?.taskIdentifier == task.taskIdentifier { self.live.removeValue(forKey: id) }
      do {
        if var row = try ledger.record(id) {
          if row["nativeTaskId"] as? Int != task.taskIdentifier { return }
          if let url = task.response?.url {
            for cookie in HTTPCookieStorage.shared.cookies(for: url) ?? [] { try self.persistCookie(cookie) }
            // Expired cookies have already disappeared from the system jar.
            // Persist the response's deletion too, so relaunch cannot restore
            // a logged-out session from our durable ledger.
            if let response = task.response as? HTTPURLResponse {
              var headers = [String: String]()
              for (key, value) in response.allHeaderFields { headers[String(describing: key)] = String(describing: value) }
              for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) {
                try self.persistCookie(cookie)
              }
            }
          }
          let payload = row["payload"] as? [String: Any] ?? [:]
          let floor = try ledger.record("nativeFloor")?["seconds"] as? Double ?? 1
          try ledger.deferUntil(["site:\(row["site"] ?? "")", "host:\(row["host"] ?? "")", "nativeGlobal"],
            Date().timeIntervalSince1970 + max(floor, (payload["cooldownMs"] as? Double ?? 1000) / 1000))
          if let error = error, row["state"] as? String == "downloading" {
            if let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
              try data.write(to: self.root.appendingPathComponent("\(id).resume"), options: .atomic)
            }
            try self.failed(&row, status: nil, response: task.response as? HTTPURLResponse, error: error as NSError)
          } else if row["state"] as? String == "downloading" && error == nil {
            try self.finish(&row, state: "needsAction", error: "storage")
          }
        }
        self.pump()
      } catch { self.attention("storage", batch: nil) }
    }
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    queue.async {
      guard let id = downloadTask.taskDescription, let ledger = self.ledger else { return }
      let now = Date().timeIntervalSince1970
      if now - (self.lastProgress[id] ?? 0) < 0.5 { return }
      self.lastProgress[id] = now
      do {
        if var row = try ledger.record(id) {
          if row["nativeTaskId"] as? Int != downloadTask.taskIdentifier { return }
          row["received"] = totalBytesWritten; row["total"] = max(0, totalBytesExpectedToWrite)
          try ledger.save(row)
        }
      } catch { self.attention("storage", batch: nil) }
    }
  }

  private func failed(_ row: inout [String: Any], status: Int?, response: HTTPURLResponse?, error: NSError?) throws {
    guard let ledger = ledger else { throw DownloadError.storage }
    let offline = error?.domain == NSURLErrorDomain &&
      [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorCancelled].contains(error?.code ?? 0)
    var attempts = row["attempts"] as? Int ?? 1
    if offline { attempts = max(0, attempts - 1); row["attempts"] = attempts }
    let transient = offline || [429, 500, 502, 503, 504].contains(status ?? 0) || error?.code == NSURLErrorTimedOut
    let code = offline ? "network" : status != nil ? "http\(status!)" : "networkTransfer"
    if transient && attempts < 5 {
      let backoff = offline ? 30.0 : min(300, 5 * pow(2, Double(max(0, attempts - 1))) * Double.random(in: 1...1.2))
      var due = Date().timeIntervalSince1970 + backoff
      if let retry = response?.value(forHTTPHeaderField: "Retry-After") {
        if let seconds = Double(retry) { due = max(due, Date().timeIntervalSince1970 + max(0, seconds)) }
        else {
          let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX")
          format.timeZone = TimeZone(secondsFromGMT: 0); format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
          if let date = format.date(from: retry) { due = max(due, date.timeIntervalSince1970) }
        }
      }
      row["state"] = "queued"; row["due"] = due; row["error"] = code
      try ledger.save(row)
      if status == 429 || status == 503 {
        try ledger.deferUntil(["site:\(row["site"] ?? "")", "host:\(row["host"] ?? "")"], due)
      }
    } else { try finish(&row, state: transient ? "failed" : "needsAction", error: code) }
  }

  private func finish(_ row: inout [String: Any], state: String, error: String? = nil) throws {
    guard let ledger = ledger else { throw DownloadError.storage }
    let id = row["id"] as! String
    row["state"] = state
    var receipt: [String: Any] = ["id": "receipt:\(id):\(UUID().uuidString)", "taskId": row["taskId"]!,
      "attemptId": row["attemptId"]!, "state": state, "attempts": row["attempts"] ?? 0]
    receipt["destination"] = row["destination"]
    receipt["error"] = error
    receipt["stage"] = row["staged"] != nil ? "publishing" : ""
    receipt["filename"] = (row["payload"] as? [String: Any])?["filename"]
    try ledger.transaction { try ledger.save(row); try ledger.save(receipt, kind: "receipt") }
    if state == "completed" || state == "skipped" {
      for suffix in ["complete", "resume"] {
        let staged = root.appendingPathComponent("\(id).\(suffix)")
        if FileManager.default.fileExists(atPath: staged.path) { try? FileManager.default.removeItem(at: staged) }
      }
      lastProgress.removeValue(forKey: id)
    }
    if let error = error { attention(error, batch: row["batchId"] as? String) }
    if let batch = row["batchId"] as? String { try checkCompletion(batch) }
  }

  private func command(_ args: [String: Any]) throws {
    guard let ledger = ledger, let command = args["command"] as? String else { return }
    if command != "pause" && command != "cancel" { return }
    var predicate = "kind = 'transfer' AND state NOT IN ('completed','skipped','failed','needsAction','paused','cancelled','publishing')"
    var values = [Any]()
    if let task = args["taskId"] as? String { predicate += " AND json_extract(payload,'$.taskId') = ?"; values.append(task) }
    else if let batch = args["batchId"] as? String { predicate += " AND json_extract(payload,'$.batchId') = ?"; values.append(batch) }
    while true {
      let rows = try ledger.records(predicate, values)
      if rows.isEmpty { break }
      for var row in rows {
        row["state"] = command == "pause" ? "paused" : "cancelled"
        try ledger.save(row)
        if let id = row["id"] as? String, let task = live[id] {
          task.cancel(byProducingResumeData: { data in
            if let data = data { self.queue.async { try? data.write(to: self.root.appendingPathComponent("\(id).resume"), options: .atomic) } }
          })
        }
      }
    }
  }

  private func hash(_ file: URL) throws -> (sha: String, md5: String, size: Int) {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    var sha = SHA256(); var md5 = Insecure.MD5(); var size = 0
    while let data = try handle.read(upToCount: 65536), !data.isEmpty {
      if size == 0 {
        let prefix = String(decoding: data.prefix(512), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if prefix.hasPrefix("<html") || prefix.hasPrefix("<!doctype html") || prefix.hasPrefix("{\"error") { throw DownloadError.authentication }
      }
      size += data.count; sha.update(data: data); md5.update(data: data)
    }
    if size == 0 { throw DownloadError.invalidContent }
    return (sha.finalize().map { String(format: "%02x", $0) }.joined(),
      md5.finalize().map { String(format: "%02x", $0) }.joined(), size)
  }

  private func publish(_ original: [String: Any]) {
    guard let id = original["id"] as? String, !publishing.contains(id), let ledger = ledger else { return }
    publishing.insert(id)
    var row = original
    do {
      let payload = row["payload"] as! [String: Any]
      let destination = payload["destination"] as! [String: Any]
      guard let filename = payload["filename"] as? String, filename == (filename as NSString).lastPathComponent,
        let directory = destination["path"] as? String else { throw DownloadError.invalidDescriptor }
      let target = URL(fileURLWithPath: directory).appendingPathComponent(filename)
      let stage = URL(fileURLWithPath: row["staged"] as? String ?? target.path)
      let file = FileManager.default.fileExists(atPath: stage.path) ? stage : target
      let digest = try hash(file)
      if row["existing"] as? Bool != true {
        if let size = payload["expectedSize"] as? Int, size > 0, size != digest.size { throw DownloadError.invalidContent }
        if let expected = payload["checksum"] as? String, expected.lowercased() != digest.md5 { throw DownloadError.invalidContent }
      }
      // Authorization is durable before the first filesystem/Photos mutation.
      row["state"] = "publishing"; row["digest"] = digest.sha
      try ledger.save(row)
      try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      if row["destination"] == nil {
        if FileManager.default.fileExists(atPath: target.path) && payload["overwrite"] as? Bool != true {
          row["destination"] = target.path; row["existing"] = true
        } else if file != target {
          let temporary = target.appendingPathExtension("\(payload["id"] ?? "").part")
          if FileManager.default.fileExists(atPath: temporary.path) { try FileManager.default.removeItem(at: temporary) }
          try FileManager.default.copyItem(at: file, to: temporary)
          if FileManager.default.fileExists(atPath: target.path) { _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary) }
          else { try FileManager.default.moveItem(at: temporary, to: target) }
          row["destination"] = target.path
        }
        try ledger.save(row)
      }
      if payload["writeJson"] as? Bool == true {
        let sidecar = target.deletingPathExtension().appendingPathExtension("json")
        var metadata = payload["item"] as? [String: Any] ?? [:]
        metadata["savedFileName"] = target.lastPathComponent
        try JSONSerialization.data(withJSONObject: metadata).write(to: sidecar, options: .atomic)
      }
      if destination["photos"] as? Bool == true {
        var descriptor = payload; descriptor["digest"] = digest.sha
        photos(descriptor, file: target) { error in
          self.queue.async {
            defer { self.publishing.remove(id); self.finishBackgroundEventsIfPossible(); self.pump() }
            do {
              if let error = error { try self.finish(&row, state: "needsAction", error: error is DownloadError ? String(describing: error) : "photosAmbiguous") }
              else { try self.finish(&row, state: row["existing"] as? Bool == true ? "skipped" : "completed") }
            } catch { self.attention("storage", batch: row["batchId"] as? String) }
          }
        }
      } else {
        try finish(&row, state: row["existing"] as? Bool == true ? "skipped" : "completed")
        publishing.remove(id)
      }
    } catch {
      if let failure = error as? DownloadError, failure == .invalidContent {
        if let staged = row["staged"] as? String, staged == root.appendingPathComponent("\(id).complete").path {
          try? FileManager.default.removeItem(atPath: staged)
          row.removeValue(forKey: "staged")
        }
      }
      try? finish(&row, state: "needsAction", error: error is DownloadError ? String(describing: error) : "storage")
      publishing.remove(id)
    }
  }

  private func photos(_ descriptor: [String: Any], file: URL, completion: @escaping (Error?) -> Void) {
    do {
      guard let ledger = ledger else { throw DownloadError.storage }
      let digest = try hash(file).sha
      let id = "photos:\(digest)"
      if let receipt = try ledger.record(id) {
        if receipt["state"] as? String == "saved" { completion(nil); return }
        // Add-only authorization cannot look up an uncertain commit. Explicit
        // retry is required; never create a duplicate automatically.
        throw DownloadError.photosAmbiguous
      }
      let destination = descriptor["destination"] as? [String: Any] ?? [:]
      if let oldPath = destination["photosReceipts"] as? String {
        let old = URL(fileURLWithPath: oldPath).appendingPathComponent("\(digest).asset")
        if let identifier = try? String(contentsOf: old, encoding: .utf8), !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          try ledger.save(["id": id, "state": "saved", "identifier": identifier], kind: "photos"); completion(nil); return
        }
      }
      let permission = PHPhotoLibrary.authorizationStatus(for: .addOnly)
      guard permission == .authorized || permission == .limited else { throw DownloadError.photosPermission }
      try ledger.save(["id": id, "state": "intent"], kind: "photos")
      var identifier: String?
      PHPhotoLibrary.shared().performChanges({
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: (descriptor["mediaType"] as? String ?? "").lowercased().contains("video") ? .video : .photo,
          fileURL: file, options: nil)
        identifier = request.placeholderForCreatedAsset?.localIdentifier
      }) { success, error in
        self.queue.async {
          do {
            if success, let identifier = identifier {
              try ledger.save(["id": id, "state": "saved", "identifier": identifier], kind: "photos")
              completion(nil)
            } else {
              // Keep the intent on uncertain failures for explicit reconciliation.
              completion(error ?? DownloadError.photosAmbiguous)
            }
          } catch { completion(DownloadError.photosAmbiguous) }
        }
      }
    } catch { completion(error) }
  }

  private func attention(_ cause: String, batch: String?) {
    guard let ledger = ledger else { return }
    let id = "notice:\(batch ?? "all"):\(cause)"
    do {
      if let batch = batch, try ledger.record("batch:" + batch)?["notifications"] as? Bool == false { return }
      try notifyOnce(id: id, complete: false, batch: batch)
    } catch {}
  }
  private func notifyOnce(id: String, complete: Bool, batch: String?) throws {
    guard let ledger = ledger, try ledger.record(id) == nil else { return }
    try ledger.save(["id": id, "state": "shown"], kind: "notice")
    notify(id: id, complete: complete, batch: batch)
  }
  private func checkCompletion(_ batch: String) throws {
    guard let ledger = ledger, let spec = try ledger.record("batch:" + batch),
      spec["done"] as? Bool == true, spec["notifications"] as? Bool != false,
      let expected = spec["expected"] as? Int, expected > 0 else { return }
    let completed = try ledger.count("kind = 'transfer' AND state IN ('completed','skipped') AND json_extract(payload,'$.batchId') = ? AND id IN (SELECT json_extract(payload,'$.attempt') FROM records WHERE kind = 'latest')", [batch])
    if completed == expected { try notifyOnce(id: "notice:\(batch):complete", complete: true, batch: batch) }
  }
  private func notify(id: String, complete: Bool, batch: String?) {
    let content = UNMutableNotificationContent()
    content.title = complete ? "Downloads complete" : "Downloads need attention"
    content.body = "Open downloads to view results and available actions."
    content.threadIdentifier = "downloads"
    content.userInfo = ["downloads": true, "batchId": batch ?? ""]
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
  }
  func handleEvents(_ completion: @escaping () -> Void) {
    queue.async { self.backgroundCompletion = completion }
  }
  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    queue.async { self.finishBackgroundEventsIfPossible() }
  }
  private func finishBackgroundEventsIfPossible() {
    guard publishing.isEmpty, let completion = backgroundCompletion else { return }
    backgroundCompletion = nil
    DispatchQueue.main.async { completion() }
  }

  private func registerContinuation() {
    #if compiler(>=6.2)
    if #available(iOS 26.0, *) {
      if continuationRegistered { return }
      let identifier = (Bundle.main.bundleIdentifier ?? "com.noaisu.loliSnatcher") + ".downloads.discovery.active"
      continuationRegistered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
        guard let task = task as? BGContinuedProcessingTask else { return }
        self.continuation = task
        task.progress.totalUnitCount = 10000
        task.expirationHandler = {
          DispatchQueue.main.async { self.endDiscovery(success: false) }
        }
        self.channel?.invokeMethod("discoveryContinued", arguments: nil)
      }
    }
    #endif
  }
  func beginDiscovery() {
    registerContinuation()
    #if compiler(>=6.2)
    if #available(iOS 26.0, *), continuationRegistered, continuation == nil {
      let identifier = (Bundle.main.bundleIdentifier ?? "com.noaisu.loliSnatcher") + ".downloads.discovery.active"
      let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: "Finding files", subtitle: "Preparing downloads")
      request.strategy = .fail
      try? BGTaskScheduler.shared.submit(request)
    }
    #endif
  }
  func endDiscovery(success: Bool = true) {
    guard continuation != nil else { return }
    #if compiler(>=6.2)
    if #available(iOS 26.0, *), let task = continuation as? BGContinuedProcessingTask { task.setTaskCompleted(success: success) }
    #endif
    continuation = nil
    channel?.invokeMethod("discoveryExpired", arguments: nil)
  }
}
