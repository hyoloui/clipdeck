import CoreGraphics
import Foundation

/// 클립보드에 쓸 표현 목록을 만든다.
public enum PastePayload {
    /// 일반 텍스트 필터를 적용하지 않고 원본을 유지하는 표현(Finder 파일은 파일명이 텍스트로 함께 들어오기 때문)
    private static let keepOriginal: Set<String> = [PasteboardTypes.fileURL, PasteboardTypes.color]

    /// 항상 `selfMarker`를 덧붙여 우리가 쓴 내용이 다시 캡처되지 않게 한다.
    /// `plainTextOnly`면 `public.utf8-plain-text`만 남긴다. 예외(원본 그대로): 파일 URL·색 표현이 있을 때,
    /// 이미지 표현이 있고 일반 텍스트가 없을 때. 텍스트와 이미지가 함께 있으면(스프레드시트 셀) 텍스트만 남긴다.
    public static func build(_ reps: [Representation], plainTextOnly: Bool) -> [Representation] {
        var out = reps
        let text = reps.filter { $0.uti == PasteboardTypes.plainText }
        let hasImage = reps.contains { $0.uti == PasteboardTypes.png || $0.uti == PasteboardTypes.tiff }
        let keep = reps.contains { keepOriginal.contains($0.uti) } || (hasImage && text.isEmpty)
        if plainTextOnly, !keep, !text.isEmpty { out = text }
        out.append(Representation(uti: PasteboardTypes.selfMarker, data: PasteboardTypes.selfMarkerData))
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

    /// ⌘V를 보내기 전에 놓이기를 기다릴 수정 키가 눌려 있는지. ⇧·⌥·⌃만 본다.
    /// ⌘는 보내는 이벤트(⌘V)에 어차피 들어가므로 기다리지 않는다(⌘1–9로 붙여넣을 때 ⌘를 누른 채여도 된다).
    public static func modifiersDown(_ flags: CGEventFlags) -> Bool {
        !flags.intersection([.maskShift, .maskAlternate, .maskControl]).isEmpty
    }

    public static func decide(frontmostMatches: Bool, modifiersDown: Bool, elapsedMs: Int) -> Decision {
        if elapsedMs >= minDelayMs, frontmostMatches, !modifiersDown { return .send }
        return elapsedMs > maxWaitMs ? .giveUp : .wait
    }
}
