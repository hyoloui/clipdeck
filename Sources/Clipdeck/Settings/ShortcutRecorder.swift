import SwiftUI

/// 단축키 녹화기. 누르면 "키를 누르세요" 상태가 되고 다음 keyDown을 `onRecord`로 넘긴다.
/// Esc는 취소, ⌫는 변경 없음(삭제 기능 없음). `onRecord`가 문자열을 돌려주면 거부 사유로 보여 준다.
struct ShortcutRecorder: View {
    let id: String
    let display: String
    @ObservedObject var session: ShortcutRecordingSession
    let onRecord: (_ keyCode: UInt16, _ eventModifiers: UInt) -> String?

    var body: some View {
        let recording = session.activeID == id
        VStack(alignment: .trailing, spacing: Layout.s4) {
            Button(recording ? "키를 누르세요" : display) { session.toggle(id: id, onRecord: onRecord) }
                .buttonStyle(.bordered)
                .accessibilityLabel("단축키 \(display)")
                .accessibilityHint("누른 뒤 새 키 조합을 입력합니다")
            if let message = session.messages[id] {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
