import AppKit
import CryptoKit
import Foundation
import ImageIO

public enum ClipBuilder {
    static let previewLimit = 300

    public static func make(representations: [Representation], sourceAppBundleID: String?,
                            sourceAppName: String?, policy: CapturePolicy) -> NewClip? {
        make(representations: representations, recentBundleIDs: sourceAppBundleID.map { [$0] } ?? [],
             sourceAppName: sourceAppName, policy: policy)
    }

    /// `recentBundleIDs`는 직전 확인 이후 앞에 있던 앱들(먼저 앞에 있던 순). 하나라도 "MCP에서 숨길 앱"이면 숨긴다.
    /// 저장하는 출처 앱은 첫 앱(복사가 일어났을 가능성이 가장 높은 앱)이고, `sourceAppName`은 그 앱의 이름이다.
    public static func make(representations: [Representation], recentBundleIDs: [String],
                            sourceAppName: String?, policy: CapturePolicy) -> NewClip? {
        let sourceAppBundleID = recentBundleIDs.first
        let plain = representations.first { $0.uti == PasteboardTypes.plainText }
            .flatMap { String(data: $0.data, encoding: .utf8) }
        guard let kind = KindClassifier.classify(utis: representations.map(\.uti), plainText: plain) else {
            return nil
        }

        let preview: String
        /// 검사 전 원문(검사는 이 원문의 앞 `ClipLimits.scanBytes`에 한다)
        let plainText: String?
        let hashSource: Data

        switch kind {
        case .text, .link:
            guard let plain else { return nil }
            // 미리보기도 저장하는 잘린 텍스트에서만 만든다(공백을 건너뛰어 100KB 너머의 내용이 들어오지 않게)
            preview = textPreview(ClipLimits.prefix(plain))
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
        // MCP·FTS에 닿는 텍스트는 앞 100KB만 담는다. 붙여넣기는 표현을 쓰므로 전문이 간다.
        // 비밀값 검사는 원문의 앞 `scanBytes`(저장 범위 + 4KB)에 해서, 저장 경계에 걸친 키도 전체가 검사된다.
        let storedText = plainText.map { ClipLimits.prefix($0) }
        let hiddenApp = recentBundleIDs.contains(where: policy.mcpHiddenBundleIDs.contains)
        let hidden = hiddenApp || (policy.detectSecrets && plainText.map(SecretDetector.isSecret) == true)
        return NewClip(kind: kind, preview: preview, plainText: storedText, contentHash: hash,
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
