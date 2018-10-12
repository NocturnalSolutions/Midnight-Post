import Foundation
import SwiftKuery

extension Connection {
    func insertAndGetId(_ i: Insert) throws -> UInt32? {
        var errorOnQuery: Error?
        var insertId: UInt32?
        execute(query: i) { queryResult in
            if let id = queryResult.asRows?.first?["id"],
                let insertedId = id {
                // The value will be an Any, but for some reason, with MySQL, it
                // casts to an Int64 but not an Int32, and SQLite is vice versa.
                // Not sure why.
                if let id64 = insertedId as? Int64 {
                    insertId = UInt32(id64)
                }
                else if let id32 = insertedId as? Int32 {
                    insertId = UInt32(id32)
                }
            }
            else if let error = queryResult.asError {
                errorOnQuery = error
            }
        }
        if let errorOnQuery = errorOnQuery {
            throw errorOnQuery
        }
        return insertId
    }
}
