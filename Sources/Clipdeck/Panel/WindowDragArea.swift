import AppKit
import SwiftUI

/// 빈 영역을 끌어 패널을 옮기는 투명 뷰. SwiftUI 뷰의 `.background`로 깔아 쓴다.
/// 위에 있는 컨트롤(검색창·메뉴·탭 등)이 먼저 이벤트를 받으므로 클릭을 가로채지 않는다.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            // 마우스를 놓을 때까지 창을 따라 움직인다(비활성 패널이라 앞 앱의 활성 상태는 그대로)
            window.performDrag(with: event)
            (window as? ClipPanel)?.onDragEnd?()
        }
    }
}
