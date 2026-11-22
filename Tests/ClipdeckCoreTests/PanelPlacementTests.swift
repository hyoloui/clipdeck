import CoreGraphics
import Testing
@testable import ClipdeckCore

@Suite struct PanelPlacementTests {
    private let size = CGSize(width: 800, height: 500)
    private let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)

    @Test func noSavedCentersWithIntegerOrigin() {
        let o = PanelPlacement.origin(saved: nil, panelSize: CGSize(width: 801, height: 501), visibleFrame: screen)
        #expect(o == CGPoint(x: 320, y: 212)) // 719.5-400.5=319 -> midX 720-400.5=319.5 반올림 320, midY 462.5-250.5=212
    }

    @Test func savedInsideKeptAsIs() {
        let p = CGPoint(x: 100, y: 200)
        #expect(PanelPlacement.origin(saved: p, panelSize: size, visibleFrame: screen) == p)
    }

    @Test func overflowRightAndBottomPulledIn() {
        let o = PanelPlacement.origin(saved: CGPoint(x: 1300, y: -100), panelSize: size, visibleFrame: screen)
        #expect(o == CGPoint(x: 640, y: 25)) // maxX 1440-800, minY 25
    }

    @Test func overflowLeftAndTopPulledIn() {
        let o = PanelPlacement.origin(saved: CGPoint(x: -300, y: 2000), panelSize: size, visibleFrame: screen)
        #expect(o == CGPoint(x: 0, y: 400)) // maxY 900-500
    }

    @Test func largerThanScreenCenters() {
        let big = CGSize(width: 2000, height: 500)
        let o = PanelPlacement.origin(saved: CGPoint(x: 10, y: 10), panelSize: big, visibleFrame: screen)
        #expect(o == CGPoint(x: -280, y: 213))
    }
}
