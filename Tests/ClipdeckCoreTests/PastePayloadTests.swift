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
            #expect(out.last == Representation(uti: PasteboardTypes.selfMarker, data: Data([0])))
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

    @Test func imageKeptWhenPlainText() {
        for t in [PasteboardTypes.png, PasteboardTypes.tiff, PasteboardTypes.color] {
            let reps = [Representation(uti: t, data: Data([1])), rep(PasteboardTypes.plainText, "x"), rep(PasteboardTypes.rtf, "r")]
            let out = PastePayload.build(reps, plainTextOnly: true)
            #expect(out.count == 4)
        }
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
    @Test func giveUpAfter500ms() {
        #expect(PasteGate.decide(frontmostMatches: true, modifiersDown: true, elapsedMs: 501) == .giveUp)
        #expect(PasteGate.decide(frontmostMatches: false, modifiersDown: false, elapsedMs: 501) == .giveUp)
        #expect(PasteGate.decide(frontmostMatches: true, modifiersDown: true, elapsedMs: 500) == .wait)
    }
}
