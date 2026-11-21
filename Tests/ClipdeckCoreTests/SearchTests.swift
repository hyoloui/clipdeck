import Testing
import Foundation
@testable import ClipdeckCore

@Suite struct SearchTests {
    @Test func koreanTrigram() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try store.insert(textClip("클립보드 기록 정리"))
        _ = try store.insert(textClip("전혀 다른 내용"))
        #expect(try store.search(SearchQuery(text: "클립보")).count == 1)
    }

    @Test func shortQueryFallsBackToLike() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try store.insert(textClip("클립보드 기록 정리"))
        _ = try store.insert(textClip("abc def"))
        #expect(try store.search(SearchQuery(text: "클립")).count == 1)
        #expect(try store.search(SearchQuery(text: "a")).count == 1)
        // LIKE 와일드카드는 글자 그대로 취급한다.
        #expect(try store.search(SearchQuery(text: "%")).isEmpty)
    }

    @Test func specialCharactersDoNotThrow() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try store.insert(textClip("it's a \"quoted\" -dash- *star* NEAR(x)"))
        for text in ["\"", "*", "-", "NEAR(", "'", "\"quoted\"", "NEAR(x)", "-dash-", "AND OR NOT"] {
            _ = try store.search(SearchQuery(text: text))
        }
        for text in ["\"quoted\"", "-dash-", "NEAR(x)"] {
            #expect(try store.search(SearchQuery(text: text)).count == 1, "\(text)")
        }
    }

    @Test func multiWordMatchesAllTerms() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try store.insert(textClip("클립보드 기록 정리"))
        #expect(try store.search(SearchQuery(text: "클립보드 정리")).count == 1)
        #expect(try store.search(SearchQuery(text: "클립보드 없는단어")).isEmpty)
        #expect(try store.search(SearchQuery(text: "정리 기록")).count == 1)
        #expect(try store.search(SearchQuery(text: "정리 a")).isEmpty)
        #expect(try store.search(SearchQuery(text: "정리 기")).count == 1)
    }

    @Test func filtersCombine() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        func link(_ s: String, app: String) -> NewClip {
            var c = textClip(s, app: app)
            c.kind = .link
            return c
        }
        _ = try store.insert(link("https://old.example", app: "com.apple.Safari"), now: t0)
        _ = try store.insert(link("https://new.example", app: "com.apple.Safari"), now: t0 + 1000)
        _ = try store.insert(link("https://other.example", app: "com.google.Chrome"), now: t0 + 1000)
        _ = try store.insert(textClip("plain", app: "com.apple.Safari"), now: t0 + 1000)
        let r = try store.search(SearchQuery(kind: .link, appBundleID: "com.apple.Safari", since: t0 + 500))
        #expect(r.map(\.preview) == ["https://new.example"])
    }

    @Test func pinboardFilter() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        guard case .inserted(let a) = try store.insert(textClip("alpha")) else { Issue.record("inserted 아님"); return }
        _ = try store.insert(textClip("beta"))
        try store.db.execute("INSERT INTO pinboards(id, name, sort) VALUES (1, 'b', 0)")
        try store.db.execute("INSERT INTO pinboard_items(pinboard_id, item_id) VALUES (1, ?)", [.int(a)])
        let r = try store.search(SearchQuery(pinboardID: 1))
        #expect(r.map(\.id) == [a])
    }

    @Test func orderByLastUsed() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        guard case .inserted(let a) = try store.insert(textClip("first"), now: t0) else { Issue.record("inserted 아님"); return }
        _ = try store.insert(textClip("second"), now: t0 + 10)
        #expect(try store.search(SearchQuery()).first?.id != a)
        try store.markUsed(id: a, now: t0 + 20)
        #expect(try store.search(SearchQuery()).first?.id == a)
        #expect(try store.search(SearchQuery(limit: 1)).count == 1)
    }

    @Test func extraWhereIsAnded() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try store.insert(textClip("visible"))
        _ = try store.insert(textClip("secret", hidden: true))
        let (sql, params) = store.searchSQL(SearchQuery(), extraWhere: "items.mcp_hidden = 0")
        let rows = try store.db.query(sql, params).compactMap(ClipStore.clipItem)
        #expect(rows.map(\.preview) == ["visible"])
    }

    @Test func sourceAppsRecentFirst() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try store.insert(textClip("a", app: "com.old"), now: Date(timeIntervalSince1970: 1))
        _ = try store.insert(textClip("b", app: "com.new"), now: Date(timeIntervalSince1970: 3))
        _ = try store.insert(textClip("c", app: "com.old"), now: Date(timeIntervalSince1970: 2))
        _ = try store.insert(textClip("d"), now: Date(timeIntervalSince1970: 4)) // 출처 없음은 제외
        let apps = try store.sourceApps()
        #expect(apps.map(\.bundleID) == ["com.new", "com.old"])
        #expect(try store.sourceApps(limit: 1).count == 1)
    }

    @Test func sourceAppsUsesLatestNameAndStableTies() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        func clip(_ t: String, bid: String, name: String) -> NewClip {
            NewClip(kind: .text, preview: t, plainText: t, contentHash: "h-" + t, sourceAppBundleID: bid,
                    sourceAppName: name, mcpHidden: false,
                    representations: [Representation(uti: "public.utf8-plain-text", data: Data(t.utf8))])
        }
        // 이름이 바뀐 앱: 사전순으로는 "Alpha"가 앞이지만 최근 이름은 "Zed"
        _ = try store.insert(clip("a", bid: "com.x", name: "Alpha"), now: Date(timeIntervalSince1970: 1))
        _ = try store.insert(clip("b", bid: "com.x", name: "Zed"), now: Date(timeIntervalSince1970: 5))
        // 시각이 같은 두 앱은 번들 ID 오름차순
        _ = try store.insert(clip("c", bid: "com.b", name: "B"), now: Date(timeIntervalSince1970: 3))
        _ = try store.insert(clip("d", bid: "com.a", name: "A"), now: Date(timeIntervalSince1970: 3))
        let apps = try store.sourceApps()
        #expect(apps.map(\.bundleID) == ["com.x", "com.a", "com.b"])
        #expect(apps.first?.name == "Zed")
    }
}
