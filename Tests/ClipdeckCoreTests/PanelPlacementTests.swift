import CoreGraphics
import Testing
@testable import ClipdeckCore

@Suite struct PanelPlacementTests {
    private let size = CGSize(width: 800, height: 500)
    private let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)

    @Test func noSavedCentersWithIntegerOrigin() {
        let o = PanelPlacement.origin(saved: nil, panelSize: CGSize(width: 801, height: 501), visibleFrame: screen)
        // x: 720 - 400.5 = 319.5 -> 반올림 320, y: 462.5 - 250.5 = 212
        #expect(o == CGPoint(x: 320, y: 212))
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

    @Test func tallerThanScreenOnlyCenters() {
        let tall = CGSize(width: 800, height: 900) // 높이만 visibleFrame(875)보다 큼
        let o = PanelPlacement.origin(saved: CGPoint(x: 100, y: 100), panelSize: tall, visibleFrame: screen)
        #expect(o == CGPoint(x: 320, y: 13)) // y: 462.5 - 450 = 12.5 -> 13
    }

    @Test func exactlyScreenSizeFitsAtFrameOrigin() {
        let o = PanelPlacement.origin(saved: CGPoint(x: 50, y: 50), panelSize: screen.size, visibleFrame: screen)
        #expect(o == CGPoint(x: 0, y: 25))
    }

    @Test func savedExactlyOnBoundaryKept() {
        #expect(PanelPlacement.origin(saved: CGPoint(x: 0, y: 25), panelSize: size, visibleFrame: screen) == CGPoint(x: 0, y: 25))
        #expect(PanelPlacement.origin(saved: CGPoint(x: 640, y: 400), panelSize: size, visibleFrame: screen) == CGPoint(x: 640, y: 400))
    }

    @Test func nonFiniteSavedCenters() {
        let expected = PanelPlacement.origin(saved: nil, panelSize: size, visibleFrame: screen)
        #expect(PanelPlacement.origin(saved: CGPoint(x: CGFloat(Double.nan), y: 10), panelSize: size, visibleFrame: screen) == expected)
        #expect(PanelPlacement.origin(saved: CGPoint(x: 10, y: CGFloat(Double.infinity)), panelSize: size, visibleFrame: screen) == expected)
    }
}
