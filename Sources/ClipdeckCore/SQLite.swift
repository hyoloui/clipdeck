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

/// SQLite 연결 래퍼. FULLMUTEX로 열어 여러 스레드에서 쓸 수 있다.
public final class Database: @unchecked Sendable {
    private var handle: OpaquePointer?

    public init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let error = SQLiteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)))
            sqlite3_close(handle)
            handle = nil // deinit에서 이중 해제되지 않게 한다.
            throw error
        }
        sqlite3_busy_timeout(handle, 2000)
        _ = try query("PRAGMA journal_mode=WAL")
        try execute("PRAGMA foreign_keys=ON")
    }

    deinit { sqlite3_close_v2(handle) }

    public var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }

    public func execute(_ sql: String, _ params: [SQLValue] = []) throws {
        _ = try query(sql, params)
    }

    public func query(_ sql: String, _ params: [SQLValue] = []) throws -> [[String: SQLValue]] {
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
            case .text(let v): rc = sqlite3_bind_text(stmt, idx, v, -1, transient)
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
                case SQLITE_TEXT: row[name] = .text(String(cString: sqlite3_column_text(stmt, c)))
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

    private func lastError() -> SQLiteError {
        SQLiteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)))
    }
}
