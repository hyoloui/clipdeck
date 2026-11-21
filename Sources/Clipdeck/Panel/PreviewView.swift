import AppKit
import ClipdeckCore
import SwiftUI

enum PreviewContent {
    case text(String, monospaced: Bool)
    case image(NSImage)
    case files([String])
    case color(NSColor?, hex: String)
    case empty
}

/// 선택 항목의 미리보기 내용을 읽는다. 마지막 한 건만 기억해 화면 갱신 때 다시 읽지 않는다.
@MainActor
final class PreviewLoader {
    static let textLimit = 2000
    private let store: ClipStore
    private var cached: (id: Int64, content: PreviewContent, bytes: Int)?

    init(store: ClipStore) { self.store = store }

    func load(_ item: ClipItem) -> (content: PreviewContent, bytes: Int) {
        if let c = cached, c.id == item.id { return (c.content, c.bytes) }
        let result = read(item)
        cached = (item.id, result.content, result.bytes)
        return result
    }

    private func read(_ item: ClipItem) -> (content: PreviewContent, bytes: Int) {
        switch item.kind {
        case .text, .link:
            let full = (try? store.plainText(itemID: item.id)) ?? item.preview
            let head = String(full.prefix(Self.textLimit))
            // 링크·일반 문장은 본문 글꼴, 코드처럼 보이는 여러 줄 텍스트만 고정폭
            let mono = item.kind == .text && Self.looksLikeCode(head)
            return (.text(head, monospaced: mono), full.utf8.count)
        case .image:
            let reps = (try? store.representations(itemID: item.id)) ?? []
            let rep = reps.first { $0.uti == "public.png" } ?? reps.first { $0.uti == "public.tiff" }
            guard let rep, let image = NSImage(data: rep.data) else { return (.empty, 0) }
            return (.image(image), rep.data.count)
        case .file:
            let names = ((try? store.plainText(itemID: item.id)) ?? item.preview)
                .split(separator: "\n").map(String.init)
            return (.files(names), 0)
        case .color:
            let reps = (try? store.representations(itemID: item.id)) ?? []
            let color = reps.first.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: $0.data) }
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
    let loader: PreviewLoader
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
        let loaded = loader.load(item)
        switch loaded.content {
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
        }
    }

    private func footer(for item: ClipItem) -> some View {
        let bytes = (item.mcpHidden && !isRevealed) ? 0 : loader.load(item).bytes
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
