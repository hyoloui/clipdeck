import AppKit
import SwiftUI

private struct KeyEventBox: @unchecked Sendable { let event: NSEvent? }

/// 녹화 상태. (CLT 환경에서는 `@State` 매크로를 쓸 수 없어 `@StateObject`로 둔다.)
@MainActor
private final class RecorderState: ObservableObject {
    @Published var recording = false
    @Published var message: String?
    private var monitor: Any?

    func start(_ onRecord: @escaping (UInt16, UInt) -> String?) {
        message = nil
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let box = KeyEventBox(event: event)
            MainActor.assumeIsolated { self?.handle(box.event!, onRecord) }
            return nil // 녹화 중에는 모든 키를 먹는다
        }
    }

    func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent, _ onRecord: (UInt16, UInt) -> String?) {
        let mods = event.modifierFlags.intersection([.shift, .control, .option, .command]).rawValue
        stop()
        if mods == 0, event.keyCode == 53 || event.keyCode == 51 { return } // Esc 취소, ⌫ 변경 없음
        message = onRecord(event.keyCode, mods)
    }
}

/// 단축키 녹화기. 누르면 "키를 누르세요" 상태가 되고 다음 keyDown을 `onRecord`로 넘긴다.
/// Esc는 취소, ⌫는 변경 없음(삭제 기능 없음). `onRecord`가 문자열을 돌려주면 거부 사유로 보여 준다.
struct ShortcutRecorder: View {
    let display: String
    let onRecord: (_ keyCode: UInt16, _ eventModifiers: UInt) -> String?

    @StateObject private var state = RecorderState()

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(state.recording ? "키를 누르세요" : display) {
                state.recording ? state.stop() : state.start(onRecord)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("단축키 \(display)")
            .accessibilityHint("누른 뒤 새 키 조합을 입력합니다")
            if let message = state.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { state.stop() }
    }
}
