//
//  ViewModel.swift
//  (cloudkit-samples) Sharing
//

import Foundation
import CloudKit
import OSLog

@MainActor
final class ViewModel: ObservableObject {

    // MARK: - Error

    enum ViewModelError: Error {
        case invalidRemoteShare
    }

    // MARK: - State

    enum State {
        case loading
        case loaded(private: [Folio], shared: [Folio])
        case error(Error)
    }

    // MARK: - Properties

    /// State directly observable by our view.
    @Published private(set) var state: State = .loading
    /// Use the specified iCloud container ID, which should also be present in the entitlements file.
    lazy var container = CKContainer(identifier: Config.containerIdentifier)
    /// This project uses the user's private database.
    private lazy var database = container.privateCloudDatabase
    /// Sharing requires using a custom record zone.
    let recordZone = CKRecordZone(zoneName: "Folios")

    // MARK: - Init

    nonisolated init() {}

    /// Initializer to provide explicit state (e.g. for previews).
    init(state: State) {
        self.state = state
    }

    // MARK: - API

    /// Prepares container by creating custom zone if needed.
    func initialize() async throws {
        do {
            try await createZoneIfNeeded()
        } catch {
            state = .error(error)
        }
    }

    /// Fetches contacts from the remote databases and updates local state.
    func refresh() async throws {
        state = .loading
        do {
            let (privateFolios, sharedFolios) = try await fetchPrivateAndSharedFolios()
            state = .loaded(private: privateFolios, shared: sharedFolios)
        } catch {
            state = .error(error)
        }
    }

    /// Fetches both private and shared contacts in parallel.
    /// - Returns: A tuple containing separated private and shared contacts.
    func fetchPrivateAndSharedFolios() async throws -> (private: [Folio], shared: [Folio]) {
        // This will run each of these operations in parallel.
        async let privateFolios = fetchFolios(scope: .private, in: [recordZone])
        async let sharedFolios = fetchSharedFolios()

        return (private: try await privateFolios, shared: try await sharedFolios)
    }

    /// Adds a new Folio to the database.
    /// - Parameters:
    ///   - name: Name of the Folio.
    ///   - phoneNumber: Phone number of the contact.
    func addFolio(title: String, desc: String) async throws {
        let id = CKRecord.ID(zoneID: recordZone.zoneID)
        let folioRecord = CKRecord(recordType: "SharedFolio", recordID: id)
        folioRecord["title"] = title
        folioRecord["desc"] = desc

        do {
            try await database.save(folioRecord)
        } catch {
            debugPrint("ERROR: Failed to save new Folio: \(error)")
            throw error
        }
    }

    /// Fetches an existing `CKShare` on a Folio record, or creates a new one in preparation to share a Folio with another user.
    /// - Parameters:
    ///   - contact: Folio to share.
    ///   - completionHandler: Handler to process a `success` or `failure` result.
    func fetchOrCreateShare(folio: Folio) async throws -> (CKShare, CKContainer) {
        guard let existingShare = folio.associatedRecord.share else {
            let share = CKShare(rootRecord: folio.associatedRecord)
            share[CKShare.SystemFieldKey.title] = "Folio: \(folio.title)"
            _ = try await database.modifyRecords(saving: [folio.associatedRecord, share], deleting: [])
            return (share, container)
        }

        guard let share = try await database.record(for: existingShare.recordID) as? CKShare else {
            throw ViewModelError.invalidRemoteShare
        }

        return (share, container)
    }

    // MARK: - Private

    /// Fetches contacts for a given set of zones in a given database scope.
    /// - Parameters:
    ///   - scope: Database scope to fetch from.
    ///   - zones: Record zones to fetch contacts from.
    /// - Returns: Combined set of contacts across all given zones.
    private func fetchFolios(
        scope: CKDatabase.Scope,
        in zones: [CKRecordZone]
    ) async throws -> [Folio] {
        let database = container.database(with: scope)
        var allFolios: [Folio] = []

        // Inner function retrieving and converting all Folio records for a single zone.
        @Sendable func contactsInZone(_ zone: CKRecordZone) async throws -> [Folio] {
            var allFolios: [Folio] = []

            /// `recordZoneChanges` can return multiple consecutive changesets before completing, so
            /// we use a loop to process multiple results if needed, indicated by the `moreComing` flag.
            var awaitingChanges = true
            /// After each loop, if more changes are coming, they are retrieved by using the `changeToken` property.
            var nextChangeToken: CKServerChangeToken? = nil

            while awaitingChanges {
                let zoneChanges = try await database.recordZoneChanges(inZoneWith: zone.zoneID, since: nextChangeToken)
                let contacts = zoneChanges.modificationResultsByID.values
                    .compactMap { try? $0.get().record }
                    .compactMap { Folio(record: $0) }
                allFolios.append(contentsOf: contacts)

                awaitingChanges = zoneChanges.moreComing
                nextChangeToken = zoneChanges.changeToken
            }

            return allFolios
        }

        // Using this task group, fetch each zone's contacts in parallel.
        try await withThrowingTaskGroup(of: [Folio].self) { group in
            for zone in zones {
                group.addTask {
                    try await contactsInZone(zone)
                }
            }

            // As each result comes back, append it to a combined array to finally return.
            for try await contactsResult in group {
                allFolios.append(contentsOf: contactsResult)
            }
        }

        return allFolios
    }

    /// Fetches all shared Folios from all available record zones.
    private func fetchSharedFolios() async throws -> [Folio] {
        let sharedZones = try await container.sharedCloudDatabase.allRecordZones()
        guard !sharedZones.isEmpty else {
            return []
        }

        return try await fetchFolios(scope: .shared, in: sharedZones)
    }

    /// Creates the custom zone in use if needed.
    private func createZoneIfNeeded() async throws {
        // Avoid the operation if this has already been done.
        guard !UserDefaults.standard.bool(forKey: "isZoneCreated") else {
            return
        }

        do {
            _ = try await database.modifyRecordZones(saving: [recordZone], deleting: [])
        } catch {
            print("ERROR: Failed to create custom zone: \(error.localizedDescription)")
            throw error
        }

        UserDefaults.standard.setValue(true, forKey: "isZoneCreated")
    }
}
