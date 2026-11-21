import AppKit
import ClipdeckCore
import SwiftUI
import os

@MainActor
private final class PinboardsState: ObservableObject {
    private static let log = Logger(subsystem: "local.hyoloui.clipdeck", category: "settings")
    @Published var boards: [Pinboard] = []
    @Published var newName = ""
    @Published var error: String?
    let store: ClipStore

    init(store: ClipStore) {
        self.store = store
        reload()
    }

    func reload() { boards = (try? store.pinboards()) ?? [] }

    func create() {
        perform { _ = try self.store.createPinboard(name: self.newName, color: nil); self.newName = "" }
    }

    func rename(_ board: Pinboard, to name: String) {
        guard name != board.name else { return }
        perform { try self.store.renamePinboard(id: board.id, name: name) }
    }

    func delete(_ board: Pinboard) {
        let alert = NSAlert()
        alert.messageText = "'\(board.name)' 보드를 삭제할까요?"
        alert.informativeText = "보드 안의 항목은 기록에 그대로 남습니다."
        alert.addButton(withTitle: "삭제")
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform { try self.store.deletePinboard(id: board.id) }
    }

    func promptRename(_ board: Pinboard) {
        let alert = NSAlert()
        alert.messageText = "Pinboard 이름 바꾸기"
        let field = NSTextField(string: board.name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        field.setAccessibilityLabel("보드 이름")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "바꾸기")
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        rename(board, to: field.stringValue)
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            error = nil
        } catch let e as PinboardError {
            error = e == .duplicateName ? "같은 이름의 보드가 이미 있습니다." : e == .emptyName ? "보드 이름이 비어 있습니다." : "보드를 찾을 수 없습니다."
        } catch {
            Self.log.error("보드 작업 실패: \(String(describing: error), privacy: .public)")
            self.error = "보드를 바꾸지 못했습니다."
        }
        reload()
    }
}

struct PinboardsTab: View {
    @StateObject private var state: PinboardsState

    init(store: ClipStore) { _state = StateObject(wrappedValue: PinboardsState(store: store)) }

    var body: some View {
        Form {
            Section {
                if state.boards.isEmpty {
                    Text("Pinboard가 없습니다.").foregroundStyle(.secondary)
                }
                ForEach(state.boards, id: \.id) { board in
                    LabeledContent {
                        HStack {
                            Button("이름 바꾸기…") { state.promptRename(board) }
                            Button("삭제…", role: .destructive) { state.delete(board) }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(board.name)
                            Text("\(board.itemCount)개 항목").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                if let error = state.error { Text(error).foregroundStyle(.red) }
            }
            Section("새 Pinboard") {
                HStack {
                    TextField("이름", text: $state.newName).onSubmit { state.create() }
                    Button("추가") { state.create() }.disabled(state.newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { state.reload() }
    }
}
