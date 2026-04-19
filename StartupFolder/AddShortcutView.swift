import Lowtech
import SwiftUI

struct AddShortcutView: View {
    @Binding var selectedShortcut: Shortcut?

    var body: some View {
        VStack {
            ShortcutsPicker(shortcut: $selectedShortcut)
                .padding()
            HStack {
                Button {
                    selectedShortcut = nil
                    dismiss()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                Button {
                    dismiss()
                } label: {
                    Label("Add", systemImage: "checkmark.circle")
                }
            }
        }
        .onExitCommand {
            selectedShortcut = nil
            dismiss()
        }

        .padding()
    }

    @Environment(\.dismiss) private var dismiss
}
