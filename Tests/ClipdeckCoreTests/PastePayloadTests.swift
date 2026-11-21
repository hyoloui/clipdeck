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
            #expect(out.last == Representation(uti: PasteboardTypes.selfMarker, data: Data()))
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
