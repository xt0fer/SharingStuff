//
//  AddFolioView.swift
//  (cloudkit-samples) Sharing
//

import Foundation
import SwiftUI

/// View for adding new contacts.
struct AddFolioView: View {
    @State private var titleInput: String = ""
    @State private var descInput: String = ""

    /// Callback after user selects to add contact with given name and phone number.
    let onAdd: ((String, String) async throws -> Void)?
    /// Callback after user cancels.
    let onCancel: (() -> Void)?

    var body: some View {
        NavigationView {
            VStack {
                TextField("Folio Name", text: $titleInput)
                TextField("Description", text: $descInput)
                Spacer()
            }
            .padding()
            .navigationTitle("Add Folio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: { onCancel?() })
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: { Task { try? await onAdd?(titleInput, descInput) } })
                        .disabled(titleInput.isEmpty || descInput.isEmpty)
                }
            }
        }
    }
}
