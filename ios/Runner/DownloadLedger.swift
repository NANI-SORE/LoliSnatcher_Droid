import Foundation
import SQLite3

// Access only from DownloadBackend.queue. The native execution ledger is
// independent of Flutter's queue and excluded from backup.
final class DownloadLedger {
  private var db: OpaquePointer?
  private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  init(url: URL) throws {
    guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
      throw DownloadError.storage
    }
    try execute("PRAGMA journal_mode = WAL")
    try execute("PRAGMA synchronous = FULL")
    try execute("CREATE TABLE IF NOT EXISTS records (id TEXT PRIMARY KEY, kind TEXT NOT NULL, state TEXT NOT NULL, site TEXT NOT NULL, host TEXT NOT NULL, due REAL NOT NULL, payload TEXT NOT NULL)")
    try execute("CREATE INDEX IF NOT EXISTS records_ready ON records(kind,state,due)")
    try execute("CREATE TABLE IF NOT EXISTS rates (scope TEXT PRIMARY KEY, deadline REAL NOT NULL)")
  }
  deinit { sqlite3_close(db) }
  func execute(_ sql: String, _ args: [Any] = []) throws {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw DownloadError.storage }
    defer { sqlite3_finalize(statement) }
    try bind(args, to: statement)
    var status = sqlite3_step(statement)
    while status == SQLITE_ROW { status = sqlite3_step(statement) }
    guard status == SQLITE_DONE else { throw DownloadError.storage }
  }
  private func bind(_ args: [Any], to statement: OpaquePointer?) throws {
    for (index, value) in args.enumerated() {
      let column = Int32(index + 1)
      let status: Int32
      if let number = value as? NSNumber { status = sqlite3_bind_double(statement, column, number.doubleValue) }
      else { status = sqlite3_bind_text(statement, column, String(describing: value), -1, transient) }
      if status != SQLITE_OK { throw DownloadError.storage }
    }
  }
  func records(_ predicate: String, _ args: [Any] = [], limit: Int = 100, groupBySite: Bool = false) throws -> [[String: Any]] {
    var statement: OpaquePointer?
    let ordering = groupBySite ? "GROUP BY site ORDER BY MIN(due),id" : "ORDER BY due,id"
    guard sqlite3_prepare_v2(db, "SELECT payload FROM records WHERE \(predicate) \(ordering) LIMIT ?", -1, &statement, nil) == SQLITE_OK else {
      throw DownloadError.storage
    }
    defer { sqlite3_finalize(statement) }
    try bind(args + [max(1, min(100, limit))], to: statement)
    var rows = [[String: Any]]()
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { break }
      guard status == SQLITE_ROW, let bytes = sqlite3_column_text(statement, 0),
        let data = String(cString: bytes).data(using: .utf8),
        let row = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DownloadError.storage }
      rows.append(row)
    }
    return rows
  }
  func record(_ id: String) throws -> [String: Any]? { try records("id = ?", [id], limit: 1).first }
  func count(_ predicate: String, _ args: [Any] = []) throws -> Int {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM records WHERE \(predicate)", -1, &statement, nil) == SQLITE_OK else { throw DownloadError.storage }
    defer { sqlite3_finalize(statement) }
    try bind(args, to: statement)
    guard sqlite3_step(statement) == SQLITE_ROW else { throw DownloadError.storage }
    return Int(sqlite3_column_int64(statement, 0))
  }
  func save(_ row: [String: Any], kind: String = "transfer") throws {
    guard let id = row["id"] as? String else { throw DownloadError.invalidDescriptor }
    let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
    try execute("INSERT OR REPLACE INTO records(id,kind,state,site,host,due,payload) VALUES(?,?,?,?,?,?,?)",
      [id, kind, row["state"] as? String ?? "", row["site"] as? String ?? "", row["host"] as? String ?? "",
       row["due"] as? Double ?? 0, String(decoding: data, as: UTF8.self)])
  }
  func remove(_ id: String) throws { try execute("DELETE FROM records WHERE id = ?", [id]) }
  func transaction(_ action: () throws -> Void) throws {
    try execute("BEGIN IMMEDIATE")
    do { try action(); try execute("COMMIT") }
    catch { try? execute("ROLLBACK"); throw error }
  }
  func deadline(_ scopes: [String]) throws -> Double {
    var maximum = 0.0
    for scope in scopes {
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(db, "SELECT deadline FROM rates WHERE scope = ?", -1, &statement, nil) == SQLITE_OK else { throw DownloadError.storage }
      defer { sqlite3_finalize(statement) }
      try bind([scope], to: statement)
      if sqlite3_step(statement) == SQLITE_ROW { maximum = max(maximum, sqlite3_column_double(statement, 0)) }
    }
    return maximum
  }
  func deferUntil(_ scopes: [String], _ deadline: Double) throws {
    for scope in scopes {
      try execute("INSERT INTO rates(scope,deadline) VALUES(?,?) ON CONFLICT(scope) DO UPDATE SET deadline = MAX(deadline,excluded.deadline)", [scope, deadline])
    }
  }
}

enum DownloadError: Error, Equatable {
  case storage, invalidDescriptor, authentication, invalidContent, publicationAmbiguous, photosPermission, photosAmbiguous
}
