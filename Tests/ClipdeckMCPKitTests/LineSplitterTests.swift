import Foundation
import Testing
@testable import ClipdeckMCPKit

@Suite struct LineSplitterTests {
    @Test func multipleLinesInOneChunk() {
        var s = LineSplitter()
        #expect(s.feed(Data("a\nb\nc".utf8)) == [.text("a"), .text("b")])
        #expect(s.finish() == .text("c"))
    }

    @Test func lineSplitAcrossChunks() {
        var s = LineSplitter()
        #expect(s.feed(Data("hel".utf8)).isEmpty)
        #expect(s.feed(Data("lo\n".utf8)) == [.text("hello")])
        #expect(s.finish() == nil)
    }

    @Test func multibyteCharacterSplitAtBoundary() {
        let bytes = Array("한글\n".utf8)
        var s = LineSplitter()
        #expect(s.feed(Data(bytes[0..<4])).isEmpty)
        #expect(s.feed(Data(bytes[4...])) == [.text("한글")])
    }

    @Test func crlfIsStripped() {
        var s = LineSplitter()
        #expect(s.feed(Data("a\r\nb\r\n".utf8)) == [.text("a"), .text("b")])
    }

    @Test func lastLineWithoutNewlineComesFromFinish() {
        var s = LineSplitter()
        #expect(s.feed(Data("x\ny".utf8)) == [.text("x")])
        #expect(s.finish() == .text("y"))
        #expect(s.finish() == nil)
    }

    @Test func tooLongLineIsDiscardedAndNextLineIsFine() {
        var s = LineSplitter(maxLineBytes: 8)
        #expect(s.feed(Data("123456".utf8)).isEmpty)
        #expect(s.feed(Data("789012".utf8)).isEmpty)
        #expect(s.feed(Data("34\nok\n".utf8)) == [.tooLong, .text("ok")])
    }

    @Test func tooLongLineWithoutNewlineAtEOF() {
        var s = LineSplitter(maxLineBytes: 4)
        #expect(s.feed(Data("123456".utf8)).isEmpty)
        #expect(s.finish() == .tooLong)
    }

    @Test func invalidUTF8() {
        var s = LineSplitter()
        #expect(s.feed(Data([0xff, 0xfe, 0x0a]) + Data("ok\n".utf8)) == [.invalidUTF8, .text("ok")])
    }
}
