import AppKit
import ClipdeckCore
import SwiftUI
import os

enum PreviewContent {
    case text(String, monospaced: Bool)
    case image(NSImage)
    case files([String])
    case color(NSColor?, hex: String)
    case empty
    /// 아직 읽지 않음(선택이 막 바뀐 직후 한 순간)
    case pending
}

/// 선택 항목의 미리보기 내용. 보여줄 항목이 바뀔 때 한 번 읽어 보관하고, 화면(`body`)은 보관한 값만 그린다.
@MainActor
final class PreviewLoader: ObservableObject {
    private static let log = Logger(subsystem: "local.hyoloui.clipdeck", category: "preview")
    static let textLimit = 2000
    /// 미리보기 이미지 긴 변의 상한(pt). 실제 픽셀 수는 화면 배율을 곱한다.
    static let imageMaxPoints: CGFloat = 800

    struct Loaded {
        let id: Int64
        let content: PreviewContent
        let bytes: Int
    }

    @Published private(set) var loaded: Loaded?
    private let store: ClipStore

    init(store: ClipStore) { self.store = store }

    /// 보여줄 항목이 바뀌었을 때 부른다. 가려진 항목(보기 전)은 nil을 넘겨 내용을 읽지 않는다.
    func show(_ item: ClipItem?) {
        guard let item else { loaded = nil; return }
        if loaded?.id == item.id { return }
        let result = read(item)
        loaded = Loaded(id: item.id, content: result.content, bytes: result.bytes)
    }

    /// 패널을 닫을 때 보관한 미리보기(큰 이미지 포함)를 놓는다
    func clear() { loaded = nil }

    /// 실패하면 로그를 남기고 nil(화면은 기존처럼 대체 내용을 보여준다)
    private func attempt<T>(_ what: String, _ id: Int64, _ body: () throws -> T?) -> T? {
        do { return try body() } catch {
            Self.log.error("미리보기 읽기 실패(\(what, privacy: .public), item \(id)): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func read(_ item: ClipItem) -> (content: PreviewContent, bytes: Int) {
        switch item.kind {
        case .text, .link:
            let full = attempt("텍스트", item.id) { try store.plainText(itemID: item.id) } ?? item.preview
            let head = String(full.prefix(Self.textLimit))
            // 링크·일반 문장은 본문 글꼴, 코드처럼 보이는 여러 줄 텍스트만 고정폭
            let mono = item.kind == .text && Self.looksLikeCode(head)
            return (.text(head, monospaced: mono), full.utf8.count)
        case .image:
            // png 또는 tiff 표현 하나만 읽고, 미리보기 영역에 맞춘 축소본만 보관한다
            let rep = attempt("이미지", item.id) {
                try store.representation(itemID: item.id, uti: PasteboardTypes.png)
                    ?? store.representation(itemID: item.id, uti: PasteboardTypes.tiff)
            }
            guard let rep else { return (.empty, 0) }
            let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
            let side = min(max(Layout.panelWidth - Layout.listWidth, Layout.panelHeight), Self.imageMaxPoints)
            guard let cg = ImageThumbnail.make(data: rep.data, maxPixel: Int(side * scale)) else { return (.empty, 0) }
            let image = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale))
            return (.image(image), rep.data.count)
        case .file:
            let names = (attempt("파일", item.id) { try store.plainText(itemID: item.id) } ?? item.preview)
                .split(separator: "\n").map(String.init)
            return (.files(names), 0)
        case .color:
            let reps = attempt("색", item.id) { try store.representations(itemID: item.id) } ?? []
            let color = reps.first.flatMap { r in
                attempt("색 해석", item.id) { try NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: r.data) }
            }
            return (.color(color, hex: item.preview), 0)
        }
    }

    static func looksLikeCode(_ s: String) -> Bool {
        guard s.contains("\n") else { return s.hasPrefix("$ ") }
        return ["{", "}", ";", "=>", "();", "</", "    "].contains { s.contains($0) }
    }
}

struct PreviewView: View {
    let item: ClipItem?
    /// 선택이 바뀔 때 미리 읽어 둔 내용. 아직 이 항목 것이 아니면 내용 칸을 비워 둔다.
    let loaded: PreviewLoader.Loaded?
    let isRevealed: Bool
    let onReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.s12) {
            if let item {
                if item.mcpHidden && !isRevealed {
                    hiddenPlaceholder
                } else {
                    content(for: item)
                }
                Spacer(minLength: 0)
                footer(for: item)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(Layout.s16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var hiddenPlaceholder: some View {
        VStack(spacing: Layout.s12) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("가려진 항목입니다")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("보기") { onReveal() }
                .accessibilityLabel("내용 보기")
                .accessibilityHint("가려진 내용을 미리보기에 표시합니다")
            Text("⌘R")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(for item: ClipItem) -> some View {
        switch loaded.flatMap({ $0.id == item.id ? $0.content : nil }) ?? .pending {
        case .text(let text, let mono):
            ScrollView {
                Text(text)
                    .font(mono ? .system(.callout, design: .monospaced) : .body)
                    .foregroundStyle(.primary)
                    .textSelection(.disabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("이미지 미리보기")
        case .files(let names):
            ScrollView {
                VStack(alignment: .leading, spacing: Layout.s8) {
                    ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                        Label(name, systemImage: "doc")
                            .font(.body)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        case .color(let color, let hex):
            VStack(spacing: Layout.s12) {
                RoundedRectangle(cornerRadius: Layout.rowCorner, style: .continuous)
                    .fill(color.map(Color.init(nsColor:)) ?? .clear)
                    .frame(width: Layout.swatchSize, height: Layout.swatchSize)
                    .overlay(RoundedRectangle(cornerRadius: Layout.rowCorner, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor)))
                Text(hex).font(.system(.body, design: .monospaced))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("색상 \(hex)")
        case .empty:
            Text("미리볼 수 없습니다").foregroundStyle(.secondary)
        case .pending:
            EmptyView()
        }
    }

    private func footer(for item: ClipItem) -> some View {
        let bytes = (item.mcpHidden && !isRevealed) ? 0 : (loaded?.id == item.id ? loaded?.bytes ?? 0 : 0)
        var parts: [String] = []
        if let app = item.sourceAppName { parts.append(app) }
        parts.append(RelativeTime.string(from: item.lastUsedAt))
        if bytes > 0 { parts.append(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) }
        return Text(parts.joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityLabel("출처 " + parts.joined(separator: ", "))
    }
}
