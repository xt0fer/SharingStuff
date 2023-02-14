//
//  ContentView.swift
//  (cloudkit-samples) Sharing
//

import SwiftUI
import CloudKit

struct ContentView: View {

    // MARK: - Properties & State

    @EnvironmentObject private var vm: ViewModel

    @State private var isAddingFolio = false
    @State private var isSharing = false
    @State private var isProcessingShare = false

    @State private var activeShare: CKShare?
    @State private var activeContainer: CKContainer?

    // MARK: - Views

    var body: some View {
        NavigationView {
            contentView
                .navigationTitle("Folios")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button { Task { try await vm.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        progressView
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { isAddingFolio = true }) { Image(systemName: "plus") }
                    }
                }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            Task {
                try await vm.initialize()
                try await vm.refresh()
            }
        }
        .sheet(isPresented: $isAddingFolio, content: {
            AddFolioView(onAdd: addFolio, onCancel: { isAddingFolio = false })
        })
    }

    /// This progress view will display when either the ViewModel is loading, or a share is processing.
    var progressView: some View {
        let showProgress: Bool = {
            if case .loading = vm.state {
                return true
            } else if isProcessingShare {
                return true
            }

            return false
        }()

        return Group {
            if showProgress {
                ProgressView()
            }
        }
    }

    /// Dynamic view built from ViewModel state.
    private var contentView: some View {
        Group {
            switch vm.state {
            case let .loaded(privateFolios, sharedFolios):
                List {
                    Section(header: Text("Private")) {
                        ForEach(privateFolios) { contactRowView(for: $0) }
                    }
                    Section(header: Text("Shared")) {
                        ForEach(sharedFolios) { contactRowView(for: $0, shareable: false) }
                    }
                }.listStyle(GroupedListStyle())

            case .error(let error):
                VStack {
                    Text("An error occurred: \(error.localizedDescription)").padding()
                    Spacer()
                }

            case .loading:
                VStack { EmptyView() }
            }
        }
    }

    /// Builds a `CloudSharingView` with state after processing a share.
    private func shareView() -> CloudSharingView? {
        guard let share = activeShare, let container = activeContainer else {
            return nil
        }

        return CloudSharingView(container: container, share: share)
    }

    /// Builds a Folio row view for display contact information in a List.
    private func contactRowView(for contact: Folio, shareable: Bool = true) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(contact.name)
                Text(contact.phoneNumber)
                    .textContentType(.telephoneNumber)
                    .font(.footnote)
            }
            if shareable {
                Spacer()
                Button(action: { Task { try? await shareFolio(contact) } }, label: { Image(systemName: "square.and.arrow.up") }).buttonStyle(BorderlessButtonStyle())
                    .sheet(isPresented: $isSharing, content: { shareView() })
            }
        }
    }

    // MARK: - Actions

    private func addFolio(name: String, phoneNumber: String) async throws {
        try await vm.addFolio(name: name, phoneNumber: phoneNumber)
        try await vm.refresh()
        isAddingFolio = false
    }

    private func shareFolio(_ contact: Folio) async throws {
        isProcessingShare = true

        do {
            let (share, container) = try await vm.fetchOrCreateShare(contact: contact)
            isProcessingShare = false
            activeShare = share
            activeContainer = container
            isSharing = true
        } catch {
            debugPrint("Error sharing contact record: \(error)")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    private static let previewFolios: [Folio] = [
        Folio(
            id: UUID().uuidString,
            name: "John Appleseed",
            phoneNumber: "(888) 555-5512",
            associatedRecord: CKRecord(recordType: "SharedFolio")
        )
    ]

    static var previews: some View {
        ContentView()
            .environmentObject(ViewModel(state: .loaded(private: previewFolios, shared: previewFolios)))
    }
}
