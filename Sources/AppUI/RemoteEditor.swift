import Domain
import SFTPCore
import SwiftUI

struct RemoteEdit: Identifiable {
    var id: String { path }
    let path: String
    let original: RemoteText
}

struct RemoteEditor: View {
    let edit: RemoteEdit
    let client: SFTPClient
    let host: SSHHost
    let onSave: () async -> Void
    @State private var text = ""
    @State private var failure = ""
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(edit.path).font(.headline).textSelection(.enabled)
            TextEditor(text: $text).font(.system(.body, design: .monospaced)).disabled(saving)
            if !failure.isEmpty { Text(failure).foregroundStyle(.red) }
            HStack {
                Button("关闭") { dismiss() }.disabled(saving)
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button("保存到远端") {
                    saving = true
                    Task {
                        defer { saving = false }
                        do {
                            try await client.writeText(text, basedOn: edit.original, at: edit.path, on: host)
                            await onSave()
                            dismiss()
                        } catch { failure = error.localizedDescription }
                    }
                }.keyboardShortcut(.defaultAction).disabled(saving || text == edit.original.text)
            }
        }.padding().frame(minWidth: 620, minHeight: 440)
            .onAppear { text = edit.original.text }
            .interactiveDismissDisabled(saving)
    }
}
