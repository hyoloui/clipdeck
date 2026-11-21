import Foundation

/// 클립보드에 쓸 표현 목록을 만든다.
public enum PastePayload {
    /// 자체 쓰기 표시의 데이터. 빈 Data는 NSPasteboard에서 타입이 누락될 수 있어 1바이트로 둔다(MCP와 같은 값).
    public static let markerData = Data([0])

    /// 일반 텍스트 필터를 적용하지 않고 원본을 유지하는 표현(Finder 파일은 파일명이 텍스트로 함께 들어오기 때문)
    private static let keepOriginal: Set<String> = [
        PasteboardTypes.fileURL, PasteboardTypes.png, PasteboardTypes.tiff, PasteboardTypes.color,
    ]

    /// 항상 `selfMarker`를 덧붙여 우리가 쓴 내용이 다시 캡처되지 않게 한다.
    /// `plainTextOnly`면 `public.utf8-plain-text`만 남긴다. 텍스트가 없거나 파일·이미지·색 표현이 있으면 원본 그대로다.
    public static func build(_ reps: [Representation], plainTextOnly: Bool) -> [Representation] {
        var out = reps
        if plainTextOnly, !reps.contains(where: { keepOriginal.contains($0.uti) }) {
            let text = reps.filter { $0.uti == PasteboardTypes.plainText }
            if !text.isEmpty { out = text }
        }
        out.append(Representation(uti: PasteboardTypes.selfMarker, data: markerData))
        return out
    }

    /// NSPasteboardItem 묶음으로 나눈다. 파일 URL 표현마다 한 묶음, 나머지 표현(selfMarker 포함)은 첫 묶음.
    /// 파일 URL이 1개 이하면 전체가 한 묶음이다.
    public static func groupForPasteboard(_ reps: [Representation]) -> [[Representation]] {
        let files = reps.filter { $0.uti == PasteboardTypes.fileURL }
        guard files.count > 1 else { return [reps] }
        var first = reps.filter { $0.uti != PasteboardTypes.fileURL }
        first.insert(files[0], at: 0)
        return [first] + files.dropFirst().map { [$0] }
    }
}

/// ⌘V를 보낼지, 더 기다릴지, 포기할지 정한다(앞 앱 복귀 + 수정 키 해제 대기).
public enum PasteGate {
    public enum Decision: Equatable, Sendable { case send, wait, giveUp }

    public static let minDelayMs = 50
    public static let maxWaitMs = 500

    public static func decide(frontmostMatches: Bool, modifiersDown: Bool, elapsedMs: Int) -> Decision {
        if elapsedMs >= minDelayMs, frontmostMatches, !modifiersDown { return .send }
        return elapsedMs > maxWaitMs ? .giveUp : .wait
    }
}
