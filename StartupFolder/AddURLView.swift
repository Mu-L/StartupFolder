import SwiftUI

struct AddURLView: View {
    @Binding var url: String
    @Binding var name: String

    var body: some View {
        VStack {
            VStack {
                TextField("URL", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { dismiss() }
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { dismiss() }
            }.padding()
            HStack {
                Button {
                    url = ""
                    name = ""
                    dismiss()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                Button {
                    dismiss()
                } label: {
                    Label("Save", systemImage: "checkmark.circle")
                }
            }
        }
        .onExitCommand {
            url = ""
            name = ""
            dismiss()
        }
        .padding()
    }

    @Environment(\.dismiss) private var dismiss
}
