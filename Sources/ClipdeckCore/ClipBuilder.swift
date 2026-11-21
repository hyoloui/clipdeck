import AppKit
import CryptoKit
import Foundation
import ImageIO

public enum ClipBuilder {
    static let previewLimit = 300

    public static func make(representations: [Representation], sourceAppBundleID: String?,
                            sourceAppName: String?, policy: CapturePolicy) -> NewClip? {
        let plain = representations.first { $0.uti == PasteboardTypes.plainText }
            .flatMap { String(data: $0.data, encoding: .utf8) }
        guard let kind = KindClassifier.classify(utis: representations.map(\.uti), plainText: plain) else {
            return nil
        }

        let preview: String
        let plainText: String?
        let hashSource: Data

        switch kind {
        case .text, .link:
            guard let plain else { return nil }
            preview = textPreview(plain)
            plainText = plain
            hashSource = Data(plain.utf8)
        case .image:
            guard let r = representations.first(where: { $0.uti == PasteboardTypes.png })
                    ?? representations.first(where: { $0.uti == PasteboardTypes.tiff }) else { return nil }
            preview = imagePreview(r.data)
            plainText = nil
            hashSource = r.data
        case .file:
            let urls = representations.filter { $0.uti == PasteboardTypes.fileURL }
                .compactMap { String(data: $0.data, encoding: .utf8) }
            let names = urls.map { URL(string: $0)?.lastPathComponent ?? $0 }
            if urls.isEmpty { return nil }
            preview = String(names.joined(separator: ", ").prefix(previewLimit))
            plainText = names.joined(separator: "\n")
            hashSource = Data(urls.joined(separator: "\n").utf8)
        case .color:
            guard let r = representations.first(where: { $0.uti == PasteboardTypes.color }) else { return nil }
            preview = colorPreview(r.data)
            plainText = nil
            hashSource = r.data
        }

        let hash = SHA256.hash(data: hashSource).map { String(format: "%02x", $0) }.joined()
        let hidden = sourceAppBundleID.map { policy.mcpHiddenBundleIDs.contains($0) } ?? false
        return NewClip(kind: kind, preview: preview, plainText: plainText, contentHash: hash,
                       sourceAppBundleID: sourceAppBundleID, sourceAppName: sourceAppName,
                       mcpHidden: hidden, representations: representations)
    }

    /// 연속 공백을 한 칸으로 줄이고 앞뒤 공백을 없앤 뒤 300자에서 멈춘다(큰 텍스트도 앞부분만 훑는다)
    private static func textPreview(_ text: String) -> String {
        var out = ""
        var count = 0
        var pendingSpace = false
        for ch in text {
            if ch.isWhitespace {
                pendingSpace = count > 0
                continue
            }
            if pendingSpace {
                if count + 1 >= previewLimit { break }
                out.append(" ")
                count += 1
                pendingSpace = false
            }
            out.append(ch)
            count += 1
            if count >= previewLimit { break }
        }
        return out
    }

    private static func imagePreview(_ data: Data) -> String {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return "이미지" }
        return "이미지 \(w)×\(h)"
    }

    private static func colorPreview(_ data: Data) -> String {
        guard let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data),
              let rgb = color.usingColorSpace(.sRGB) else { return "색상" }
        func b(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", b(rgb.redComponent), b(rgb.greenComponent), b(rgb.blueComponent))
    }
}
