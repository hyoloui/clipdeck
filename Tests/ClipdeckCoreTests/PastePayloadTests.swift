import CoreGraphics
import Foundation
import Testing
@testable import ClipdeckCore

private func rep(_ uti: String, _ text: String) -> Representation {
    Representation(uti: uti, data: Data(text.utf8))
}

@Suite struct PastePayloadTests {
    @Test func plainTextStripsRichTypes() {
        let reps = [rep(PasteboardTypes.plainText, "hi"), rep(PasteboardTypes.rtf, "{rtf}"), rep(PasteboardTypes.html, "<b>hi</b>")]
        let out = PastePayload.build(reps, plainTextOnly: true)
        #expect(out.map(\.uti) == [PasteboardTypes.plainText, PasteboardTypes.selfMarker])
    }

    @Test func markerAlwaysAppended() {
        let reps = [rep(PasteboardTypes.plainText, "hi"), rep(PasteboardTypes.rtf, "{rtf}")]
        for plain in [true, false] {
            let out = PastePayload.build(reps, plainTextOnly: plain)
            #expect(out.last == Representation(uti: PasteboardTypes.selfMarker, data: PasteboardTypes.selfMarkerData))
            #expect(PasteboardTypes.selfMarkerData == Data([0]))
            #expect(out.filter { $0.uti == PasteboardTypes.selfMarker }.count == 1)
        }
        #expect(PastePayload.build(reps, plainTextOnly: false).count == 3)
    }

    @Test func imageOnlyUnchangedWhenPlainText() {
        let reps = [Representation(uti: PasteboardTypes.png, data: Data([1, 2, 3]))]
        let out = PastePayload.build(reps, plainTextOnly: true)
        #expect(Array(out.dropLast()) == reps)
        #expect(out.last?.uti == PasteboardTypes.selfMarker)
    }
}

@Suite struct PastePayloadKeepTests {
    @Test func fileURLKeptWhenPlainText() {
        let reps = [rep(PasteboardTypes.fileURL, "file:///a.txt"), rep(PasteboardTypes.plainText, "a.txt")]
        let out = PastePayload.build(reps, plainTextOnly: true)
        #expect(out.map(\.uti) == [PasteboardTypes.fileURL, PasteboardTypes.plainText, PasteboardTypes.selfMarker])
    }

    @Test func colorKeptWhenPlainText() {
        let reps = [Representation(uti: PasteboardTypes.color, data: Data([1])), rep(PasteboardTypes.plainText, "x"), rep(PasteboardTypes.rtf, "r")]
        #expect(PastePayload.build(reps, plainTextOnly: true).count == 4)
    }

    /// 텍스트와 이미지가 함께 있으면(스프레드시트 셀) 일반 텍스트 모드에서 텍스트만 남긴다
    @Test func imageWithTextFilteredWhenPlainText() {
        for t in [PasteboardTypes.png, PasteboardTypes.tiff] {
            let reps = [Representation(uti: t, data: Data([1])), rep(PasteboardTypes.plainText, "x"), rep(PasteboardTypes.rtf, "r")]
            let out = PastePayload.build(reps, plainTextOnly: true)
            #expect(out.map(\.uti) == [PasteboardTypes.plainText, PasteboardTypes.selfMarker])
        }
    }

    @Test func imageWithoutTextKeptWhenPlainText() {
        let reps = [Representation(uti: PasteboardTypes.tiff, data: Data([1])), rep(PasteboardTypes.rtf, "r")]
        #expect(Array(PastePayload.build(reps, plainTextOnly: true).dropLast()) == reps)
    }

    @Test func groupSplitsFileURLs() {
        let reps = [rep(PasteboardTypes.fileURL, "file:///a"), rep(PasteboardTypes.fileURL, "file:///b"),
                    rep(PasteboardTypes.plainText, "a\nb"), Representation(uti: PasteboardTypes.selfMarker, data: Data([0]))]
        let g = PastePayload.groupForPasteboard(reps)
        #expect(g.count == 2)
        #expect(g[0].map(\.uti) == [PasteboardTypes.fileURL, PasteboardTypes.plainText, PasteboardTypes.selfMarker])
        #expect(g[1] == [reps[1]])
    }

    @Test func groupSingleWhenOneOrNoFile() {
        let reps = [rep(PasteboardTypes.plainText, "a"), Representation(uti: PasteboardTypes.selfMarker, data: Data([0]))]
        #expect(PastePayload.groupForPasteboard(reps) == [reps])
        #expect(PastePayload.groupForPasteboard([]) == [[]])
    }
}

@Suite struct PasteGateTests {
    @Test func sendAfter50msWhenReady() {
        #expect(PasteGate.decide(frontmostMatches: true, modifiersDown: false, elapsedMs: 50) == .send)
        #expect(PasteGate.decide(frontmostMatches: true, modifiersDown: false, elapsedMs: 49) == .wait)
    }
    @Test func waitWhileModifiersDownOrWrongApp() {
        #expect(PasteGate.decide(frontmostMatches: true, modifiersDown: true, elapsedMs: 100) == .wait)
        #expect(PasteGate.decide(frontmostMatches: false, modifiersDown: false, elapsedMs: 100) == .wait)
    }
    /// ⌘는 기다리지 않는다(보내는 이벤트가 ⌘V라 ⌘1–9의 ⌘가 눌려 있어도 된다). ⇧·⌥·⌃만 기다린다.
    @Test func commandAloneDoesNotBlock() {
        #expect(!PasteGate.modifiersDown([.maskCommand]))
        #expect(!PasteGate.modifiersDown([]))
        #expect(!PasteGate.modifiersDown([.maskAlphaShift, .maskNumericPad]))
        #expect(PasteGate.modifiersDown([.maskShift]))
        #expect(PasteGate.modifiersDown([.maskCommand, .maskAlternate]))
        #expect(PasteGate.modifiersDown([.maskControl]))
    }

    @Test func giveUpAfter500ms() {
        #expect(PasteGate.decide(frontmostMatches: true, modifiersDown: true, elapsedMs: 501) == .giveUp)
        #expect(PasteGate.decide(frontmostMatches: false, modifiersDown: false, elapsedMs: 501) == .giveUp)
        #expect(PasteGate.decide(frontmostMatches: true, modifiersDown: true, elapsedMs: 500) == .wait)
    }
}
