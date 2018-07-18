import Foundation
import SwiftKuery

class PostRevisionTable_v0: Table {
    let tableName = "post_revisions"
    let id = Column("rev_id", Int16.self, notNull: true)
//    let date = Column("date", Varchar.self, length: 19, notNull: true, defaultValue: QueryBuilder.QuerySubstitutionNames.now)
    let date = Column("rev_date", Varchar.self, length: 19, notNull: true)
    let postId = Column("post_id", Int32.self, notNull: true)
    let subject = Column("subject", String.self, notNull: true)
    let body = Column("body", String.self, notNull: true)

    func getIndexes() -> [Column] {
        return [id, postId]
    }
}

typealias PostRevisionTable = PostRevisionTable_v0

struct PostRevision {
    let id: UInt
    let post: UInt
    let subject: String
    let body: String
    let date: Date

    enum PostRevisionError: Error {
        case FaultCreatingFromRow
    }

    init(forNewPost postId: UInt, subject: String, body: String, date: Date) throws {
        id = 0
        post = postId
        self.subject = subject
        self.body = body
        self.date = date

        let pr = PostRevisionTable()
        let i = Insert(into: pr, columns: [pr.id, pr.postId, pr.subject, pr.body, pr.date], values: [id, post, subject, body, MidnightPost.dateFormatter.string(from: date)])
        var qe: Error? = nil
        MidnightPost.dbCxn?.execute(query: i) { queryResult in
            if let error = queryResult.asError {
                qe = error
            }
        }
        if let qe = qe {
            throw qe
        }
    }

    init(fromDbRow dbRow: [String: Any?]) throws {
        let pr = PostRevisionTable()
        guard let id = dbRow[pr.id.name] as? UInt,
            let postId = dbRow[pr.postId.name] as? UInt,
            let subject = dbRow[pr.subject.name] as? String,
            let body = dbRow[pr.body.name] as? String,
            let dateStr = dbRow[pr.date.name] as? String,
            let date = MidnightPost.dateFormatter.date(from: dateStr) else {
            throw PostRevisionError.FaultCreatingFromRow
        }
        self.id = id
        self.post = postId
        self.subject = subject
        self.body = body
        self.date = date
    }
}
