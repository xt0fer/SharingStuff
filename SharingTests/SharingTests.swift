//
//  SharingTests.swift
//  SharingTests
//

import XCTest
import CloudKit
@testable import Sharing

class SharingTests: XCTestCase {

    let viewModel = ViewModel()
    var idsToDelete: [CKRecord.ID] = []

    // MARK: - Setup & Tear Down

    override func setUp() {
        let expectation = self.expectation(description: "Expect ViewModel initialization completed")

        Task {
            try await viewModel.initialize()
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)
    }

    override func tearDownWithError() throws {
        guard !idsToDelete.isEmpty else {
            return
        }

        let container = CKContainer(identifier: Config.containerIdentifier)
        let database = container.privateCloudDatabase
        let deleteExpectation = expectation(description: "Expect CloudKit to delete testing records")

        Task {
            _ = try await database.modifyRecords(saving: [], deleting: idsToDelete)
            idsToDelete = []
            deleteExpectation.fulfill()
        }

        waitForExpectations(timeout: 10, handler: nil)
    }

    // MARK: - CloudKit Readiness

    func test_CloudKitReadiness() async throws {
        // Fetch zones from the Private Database of the CKContainer for the current user to test for valid/ready state
        let container = CKContainer(identifier: Config.containerIdentifier)
        let database = container.privateCloudDatabase

        do {
            _ = try await database.allRecordZones()
        } catch let error as CKError {
            switch error.code {
            case .badContainer, .badDatabase:
                XCTFail("Create or select a CloudKit container in this app target's Signing & Capabilities in Xcode")

            case .permissionFailure, .notAuthenticated:
                XCTFail("Simulator or device running this app needs a signed-in iCloud account")

            default:
                XCTFail("CKError: \(error)")
            }
        }
    }

    // MARK: - CKShare Creation

    func testCreatingShare() async throws {
        // Create a temporary contact to create the share on.
        try await createTestFolio()
        // Fetch private contacts, which should now contain the temporary contact.
        let privateFolios = try await fetchPrivateFolios()

        guard let testFolio = privateFolios.first(where: { $0.title == self.testFolioName }) else {
            XCTFail("No matching test Folio found after fetching private contacts")
            return
        }

        idsToDelete.append(testFolio.associatedRecord.recordID)

        let (share, _) = try await viewModel.fetchOrCreateShare(contact: testFolio)

        idsToDelete.append(share.recordID)
    }

    // MARK: - Helpers

    /// For testing creating a `CKShare`, we need to create a `Folio` with a name we can reference later.
    private lazy var testFolioName: String = {
        "Test\(UUID().uuidString)"
    }()

    /// Simple function to create and save a new `Folio` to test with. Immediately fails on any error.
    private func createTestFolio() async throws {
        try await viewModel.addFolio(name: testFolioName, phoneNumber: "555-123-4567")
    }

    /// Uses the ViewModel to fetch only private contacts. Immediately fails on any error.
    /// - Parameter completion: Handler called on completion.
    private func fetchPrivateFolios() async throws -> [Folio] {
        try await viewModel.fetchPrivateAndSharedFolios().private
    }
}
