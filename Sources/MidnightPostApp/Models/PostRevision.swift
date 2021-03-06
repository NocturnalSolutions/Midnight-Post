import Foundation
import SwiftKuery

class PostRevisionTable_v0: Table {
    let tableName = "post_revisions"
    let id = Column("rev_id", Int32.self, autoIncrement: true, primaryKey: true)
    let date = Column("rev_date", Varchar.self, length: 19, notNull: true)
    let postId = Column("post_id", Int32.self, notNull: true)
    let subject = Column("subject", String.self, notNull: true)
    let body = Column("body", String.self, notNull: true)
    let slug = Column("slug", Varchar.self, length: 255)

    func getIndexes() -> [Column] {
        return [id, postId]
    }
}

typealias PostRevisionTable = PostRevisionTable_v0

struct PostRevision {
    let id: UInt32
    let post: UInt32
    let subject: String
    let body: String
    let date: Date
    let slug: String?

    enum PostRevisionError: Error {
        case FaultCreatingFromRow
        case FaultFetchingNewId
    }

    init(forPost postId: UInt32, subject: String, body: String, date: Date = Date(), slug: String?) throws {
        post = postId
        self.subject = subject
        self.body = body
        self.date = date
        self.slug = slug

        let pr = PostRevisionTable()
        var columns = [pr.postId, pr.subject, pr.body, pr.date]
        var values = [post, subject, body, MidnightPost.dateFormatter.string(from: date)] as [Any]
        if let slug = slug {
            columns.append(pr.slug)
            values.append(slug)
        }
        let i = Insert(into: pr, columns: columns, values: values, returnID: true)

        if let newId = try MidnightPost.dbCxn?.insertAndGetId(i) {
            id = newId
        }
        else {
            throw PostRevisionError.FaultFetchingNewId
        }
    }

    init(fromDbRow dbRow: [String: Any?]) throws {
        let pr = PostRevisionTable()
        // WTMF, why are they double-wrapped again?
        let fixedRow = dbRow.mapValues { value in value! }
        guard let id = fixedRow[pr.id.name] as? Int32,
            let postId = fixedRow[pr.postId.name] as? Int32,
            let subject = fixedRow[pr.subject.name] as? String,
            let body = fixedRow[pr.body.name] as? String,
            let dateStr = fixedRow[pr.date.name] as? String,
            let date = MidnightPost.dateFormatter.date(from: dateStr) else {
            throw PostRevisionError.FaultCreatingFromRow
        }
        self.id = UInt32(id)
        self.post = UInt32(postId)
        self.subject = subject
        self.body = body
        self.date = date
        self.slug = fixedRow[pr.slug.name] as? String
    }
}
