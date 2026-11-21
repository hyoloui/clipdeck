import AppKit

/// 화면 하단 중앙에 잠깐 떴다 사라지는 작은 HUD. 포커스를 가져가지 않는다.
@MainActor
final class ToastWindow {
    static let shared = ToastWindow()

    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    /// `opensAccessibilitySettings`가 true면 클릭을 받아 손쉬운 사용 설정을 연다.
    func show(_ message: String, opensAccessibilitySettings: Bool = false) {
        hideTask?.cancel()
        panel?.orderOut(nil)

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.sizeToFit()

        let pad: CGFloat = 16
        let size = NSSize(width: label.frame.width + pad * 2, height: label.frame.height + pad)
        let effect = ClickableEffectView(frame: NSRect(origin: .zero, size: size))
        if opensAccessibilitySettings {
            effect.onClick = { [weak self] in
                AccessibilityPermission.openSettings()
                self?.dismiss()
            }
        }
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = size.height / 2
        effect.layer?.masksToBounds = true
        label.frame.origin = NSPoint(x: pad, y: (size.height - label.frame.height) / 2)
        effect.addSubview(label)

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = effect
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = !opensAccessibilitySettings
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.minY + 60))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func dismiss() {
        hideTask?.cancel()
        panel?.orderOut(nil)
        panel = nil
    }
}

/// 첫 클릭을 바로 받는 HUD 배경(권한 안내 토스트용)
private final class ClickableEffectView: NSVisualEffectView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
