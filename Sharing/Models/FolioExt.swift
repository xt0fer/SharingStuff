//
//  Contact.swift
//  (cloudkit-samples) Sharing
//

import Foundation
import CloudKit

//struct Contact: Identifiable {
//    let id: String
//    let name: String
//    let phoneNumber: String
//    let associatedRecord: CKRecord
//}

extension Folio {
    /// Initializes a `Folio` object from a CloudKit record.
    /// - Parameter record: CloudKit record to pull values from.
    convenience init?(record: CKRecord) {
        guard let title = record["title"] as? String,
              let desc = record["desc"] as? String else {
            return nil
        }

        //self.id = record.recordID.recordName
        self.title = title
        //self.phoneNumber = phoneNumber
        //self.associatedRecord = record
    }
}
