import Foundation

public enum ItemKind: String, Codable, CaseIterable, Sendable, Equatable {
    case text, link, image, file, color
}

public struct Representation: Sendable, Equatable {
    public var uti: String
    public var data: Data
    public init(uti: String, data: Data) {
        self.uti = uti
        self.data = data
    }
}

public struct ClipItem: Sendable, Equatable {
    public var id: Int64
    public var kind: ItemKind
    public var preview: String
    public var contentHash: String
    public var sourceAppBundleID: String?
    public var sourceAppName: String?
    public var mcpHidden: Bool
    public var createdAt: Date
    public var lastUsedAt: Date
    public var useCount: Int

    public init(id: Int64, kind: ItemKind, preview: String, contentHash: String,
                sourceAppBundleID: String?, sourceAppName: String?, mcpHidden: Bool,
                createdAt: Date, lastUsedAt: Date, useCount: Int) {
        self.id = id
        self.kind = kind
        self.preview = preview
        self.contentHash = contentHash
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.mcpHidden = mcpHidden
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }
}

public struct NewClip: Sendable, Equatable {
    public var kind: ItemKind
    public var preview: String
    public var plainText: String?
    public var contentHash: String
    public var sourceAppBundleID: String?
    public var sourceAppName: String?
    public var mcpHidden: Bool
    public var representations: [Representation]

    public init(kind: ItemKind, preview: String, plainText: String?, contentHash: String,
                sourceAppBundleID: String?, sourceAppName: String?, mcpHidden: Bool,
                representations: [Representation]) {
        self.kind = kind
        self.preview = preview
        self.plainText = plainText
        self.contentHash = contentHash
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.mcpHidden = mcpHidden
        self.representations = representations
    }
}

public enum InsertResult: Sendable, Equatable {
    case inserted(Int64)
    case bumped(Int64)
}

public struct Pinboard: Sendable, Equatable {
    public var id: Int64
    public var name: String
    public var color: String?
    public var sort: Int
    public var itemCount: Int

    public init(id: Int64, name: String, color: String?, sort: Int, itemCount: Int) {
        self.id = id
        self.name = name
        self.color = color
        self.sort = sort
        self.itemCount = itemCount
    }
}

public struct SearchQuery: Sendable, Equatable {
    public var text: String
    public var kind: ItemKind?
    public var appBundleID: String?
    public var pinboardID: Int64?
    public var since: Date?
    public var limit: Int

    public init(text: String = "", kind: ItemKind? = nil, appBundleID: String? = nil,
                pinboardID: Int64? = nil, since: Date? = nil, limit: Int = 50) {
        self.text = text
        self.kind = kind
        self.appBundleID = appBundleID
        self.pinboardID = pinboardID
        self.since = since
        self.limit = limit
    }
}
