import Foundation
import SwiftKuery
import KituraMarkdown

class PostTable_v0: Table {
    let tableName = "posts"
    let id = Column("post_id", Int32.self, autoIncrement: true, primaryKey: true)
//    let date = Column("date", Varchar.self, length: 19, notNull: true, defaultValue: QueryBuilder.QuerySubstitutionNames.now)
    let date = Column("post_date", Varchar.self, length: 19, notNull: true)
}

typealias PostTable = PostTable_v0

struct Post {
    let id: UInt
    let date: Date
    let latestRevision: PostRevision

    enum PostError: Error {
        case FaultOnInitialInsert(queryError: Error)
        case FaultOnInitialRevision(queryError: Error)
        case IdNotFound
        case FaultCreatingFromRow
        case FaultFetchingInsertId
    }

    init(subject: String, body: String) throws {
        let pt = PostTable()
        date = Date()
        let now = MidnightPost.dateFormatter.string(from: date)
        let i = Insert(into: pt, columns: [pt.date], values: [now], returnID: true)
        var insertId: UInt?
        var errorOnQuery: PostError?
        MidnightPost.dbCxn?.execute(query: i) { queryResult in
            if let id = queryResult.asRows?.first?["id"],
                let insertedId = id {
                // The value will be an Any, but for some reason, with MySQL, it
                // casts to an Int64 but not an Int32, and SQLite is vice versa.
                // Not sure why.
                if let id64 = insertedId as? Int64 {
                    insertId = UInt(id64)
                }
                else if let id32 = insertedId as? Int32 {
                    insertId = UInt(id32)
                }
                else {
                    errorOnQuery = PostError.FaultFetchingInsertId
                }
            }
            else if let error = queryResult.asError {
                errorOnQuery = PostError.FaultOnInitialInsert(queryError: error )
            }
        }
        if let errorOnQuery = errorOnQuery {
            throw errorOnQuery
        }
        id = insertId!

        do {
            latestRevision = try PostRevision(forNewPost: id, subject: subject, body: body, date: date)
        }
        catch {
            throw PostError.FaultOnInitialRevision(queryError: error)
        }
    }

    init(loadId: UInt) throws {
        let pt = PostTable()
        let rt = PostRevisionTable()
        var cols = rt.columns
        cols.append(pt.id)
        cols.append(pt.date)
        let s = Select(fields: cols, from: [pt])
            .where(pt.id == Int(loadId))
            .join(rt).on(pt.id == rt.postId)
            .order(by: .DESC(rt.date))
            .limit(to: 1)
        var possibleRow: [String: Any?]?
        MidnightPost.dbCxn?.execute(query: s) { queryResult in
            if let rows = queryResult.asRows, let row = rows.first {
                possibleRow = row
            }
        }
        if let row = possibleRow {
            // I don't understand why all the values are double-wrapped
            let goodRow = row.mapValues { value in value! }
            guard let id = goodRow[pt.id.name] as? Int32,
                let dateStr = goodRow[pt.date.name] as? String,
                let date = MidnightPost.dateFormatter.date(from: dateStr) else {
                throw PostError.FaultCreatingFromRow
            }
            self.id = UInt(id)
            self.date = date
            latestRevision = try PostRevision(fromDbRow: goodRow)
        }
        else {
            throw PostError.IdNotFound
        }
    }

    /// Prepare properties for viewing via Stencil
    func prepareForView() -> [String: Any] {
        return [
            "subject": latestRevision.subject.webSanitize(),
            "body": KituraMarkdown.render(from: latestRevision.body.webSanitize()),
            "creationDate": MidnightPost.dateFormatter.string(from: date).webSanitize(),
            "editDate": MidnightPost.dateFormatter.string(from: latestRevision.date).webSanitize(),
            "id": String(id),
            "revisionId": String(latestRevision.id)
        ] as [String: Any]

    }
}
