import Foundation
import SQLite3

public enum SQLValue: Sendable, Equatable {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
    case blob(Data)
}

public struct SQLiteError: Error, CustomStringConvertible, Sendable {
    public let code: Int32
    public let message: String
    public var description: String { "SQLite 오류 \(code): \(message)" }
}

// SQLITE_TRANSIENT: 바인딩한 값을 SQLite가 즉시 복사하도록 한다.
private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite 연결 래퍼. FULLMUTEX로 열고, 재귀 락으로 한 인스턴스의 호출(트랜잭션 포함)을 직렬화한다.
public final class Database: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()

    public init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let error = SQLiteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)))
            sqlite3_close(handle)
            handle = nil // deinit에서 이중 해제되지 않게 한다.
            throw error
        }
        guard sqlite3_busy_timeout(handle, 2000) == SQLITE_OK else {
            let error = SQLiteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)))
            sqlite3_close(handle)
            handle = nil
            throw error
        }
        let mode = try query("PRAGMA journal_mode=WAL").first?["journal_mode"]
        guard case .text(let m)? = mode, m.lowercased() == "wal" else {
            sqlite3_close(handle)
            handle = nil
            throw SQLiteError(code: SQLITE_ERROR, message: "WAL 모드를 켜지 못했다: \(String(describing: mode))")
        }
        try execute("PRAGMA foreign_keys=ON")
    }

    deinit { sqlite3_close_v2(handle) }

    public var lastInsertRowID: Int64 {
        lock.lock(); defer { lock.unlock() }
        return sqlite3_last_insert_rowid(handle)
    }

    public func execute(_ sql: String, _ params: [SQLValue] = []) throws {
        _ = try query(sql, params)
    }

    public func query(_ sql: String, _ params: [SQLValue] = []) throws -> [[String: SQLValue]] {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { throw lastError() }
        defer { sqlite3_finalize(stmt) }

        for (i, value) in params.enumerated() {
            let idx = Int32(i + 1)
            let rc: Int32
            switch value {
            case .null: rc = sqlite3_bind_null(stmt, idx)
            case .int(let v): rc = sqlite3_bind_int64(stmt, idx, v)
            case .double(let v): rc = sqlite3_bind_double(stmt, idx, v)
            case .text(let v):
                // NUL이 들어간 텍스트가 잘리지 않도록 UTF-8 바이트 길이를 지정한다.
                let bytes = Array(v.utf8)
                rc = bytes.withUnsafeBufferPointer {
                    $0.withMemoryRebound(to: CChar.self) { sqlite3_bind_text(stmt, idx, $0.baseAddress, Int32($0.count), transient) }
                }
            case .blob(let v):
                rc = v.withUnsafeBytes { sqlite3_bind_blob(stmt, idx, $0.baseAddress, Int32($0.count), transient) }
            }
            guard rc == SQLITE_OK else { throw lastError() }
        }

        var rows: [[String: SQLValue]] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw lastError() }
            var row: [String: SQLValue] = [:]
            for c in 0..<sqlite3_column_count(stmt) {
                let name = String(cString: sqlite3_column_name(stmt, c))
                switch sqlite3_column_type(stmt, c) {
                case SQLITE_INTEGER: row[name] = .int(sqlite3_column_int64(stmt, c))
                case SQLITE_FLOAT: row[name] = .double(sqlite3_column_double(stmt, c))
                case SQLITE_TEXT: row[name] = .text(columnText(stmt, c))
                case SQLITE_BLOB:
                    let n = Int(sqlite3_column_bytes(stmt, c))
                    row[name] = .blob(n == 0 ? Data() : Data(bytes: sqlite3_column_blob(stmt, c), count: n))
                default: row[name] = .null
                }
            }
            rows.append(row)
        }
        return rows
    }

    /// BEGIN IMMEDIATE로 시작해 성공하면 커밋, 오류가 나면 롤백한다.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func columnText(_ stmt: OpaquePointer?, _ c: Int32) -> String {
        let n = Int(sqlite3_column_bytes(stmt, c))
        guard n > 0, let p = sqlite3_column_text(stmt, c) else { return "" }
        return String(decoding: UnsafeBufferPointer(start: p, count: n), as: UTF8.self)
    }

    private func lastError() -> SQLiteError {
        SQLiteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)))
    }
}
