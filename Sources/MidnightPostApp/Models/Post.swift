import Foundation
import SwiftKuery
import KituraMarkdown

class PostTable_v0: Table {
    let tableName = "posts"
    let id = Column("post_id", Int32.self, autoIncrement: true, primaryKey: true)
//    let date = Column("date", Varchar.self, length: 19, notNull: true, defaultValue: QueryBuilder.QuerySubstitutionNames.now)
    let date = Column("post_date", Varchar.self, length: 19, notNull: true)
    let revId = Column("rev_id", Int32.self, notNull: true)
}

typealias PostTable = PostTable_v0

public struct Post {
    let id: UInt32
    let date: Date
    let latestRevision: PostRevision

    public static let postsPerPage: Int = 10

    enum PostError: Error {
        case FaultOnInitialInsert(queryError: Error)
        case FaultOnRevision(queryError: Error)
        case IdNotFound
        case FaultCreatingFromRow
        case FaultFetchingInsertId
        case FaultGettingCount
    }

    init(subject: String, body: String) throws {
        let pt = PostTable()
        date = Date()
        let now = MidnightPost.dateFormatter.string(from: date)
        let i = Insert(into: pt, columns: [pt.date, pt.revId], values: [now, 0], returnID: true)

        do {
            if let newId = try MidnightPost.dbCxn?.insertAndGetId(i) {
                id = newId
            }
            else {
                throw PostError.FaultFetchingInsertId
            }
            latestRevision = try PostRevision(forPost: id, subject: subject, body: body, date: date)
            try setCurrentRevision(revId: latestRevision.id)
        }
        catch {
            if error is QueryError {
                throw PostError.FaultOnRevision(queryError: error)
            }
            else {
                throw error
            }
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
            .naturalJoin(rt)
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
            try self.init(fromDbRow: goodRow)
        }
        else {
            throw PostError.IdNotFound
        }
    }

    init(fromDbRow: [String: Any]) throws {
        let pt = PostTable()
        guard let id = fromDbRow[pt.id.name] as? Int32,
            let dateStr = fromDbRow[pt.date.name] as? String,
            let date = MidnightPost.dateFormatter.date(from: dateStr) else {
                throw PostError.FaultCreatingFromRow
        }
        self.id = UInt32(id)
        self.date = date
        latestRevision = try PostRevision(fromDbRow: fromDbRow)
    }

    /// Add a new revision. Note we're not changing the actual latestRevision
    /// property.
    @discardableResult
    func addNewRevision(subject: String, body: String) throws -> PostRevision {
        do {
            let rev = try PostRevision(forPost: id, subject: subject, body: body)
            try setCurrentRevision(revId: rev.id)
            return rev
        }
        catch {
            throw PostError.FaultOnRevision(queryError: error)
        }
    }

    func setCurrentRevision(revId: UInt32) throws {
        let pt = PostTable()
        let u = Update(pt, set: [(pt.revId, revId)])
            .where(pt.id == Int(id))
        var error: Error? = nil
        MidnightPost.dbCxn?.execute(query: u) { queryResult in
            if let queryError = queryResult.asError {
                error = queryError
            }
        }
        if let error = error {
            throw error
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

    /// Get most recent posts
    static func getNewPosts(page: UInt = 0) -> [Post] {
        let pt = PostTable()
        let rt = PostRevisionTable()
        var cols = rt.columns
        cols.append(pt.id)
        cols.append(pt.date)

        let s = Select(fields: cols, from: [pt])
            .naturalJoin(rt)
            .order(by: .DESC(pt.id))
            .limit(to: Post.postsPerPage)
            .offset(Post.postsPerPage * Int(page))
        var posts: [Post]? = nil
        MidnightPost.dbCxn?.execute(query: s) { queryResult in
            if let rows = queryResult.asRows {
                posts = try? rows.map { row in
                    // This looks stupid, but it makes Xcode shut up.
                    try Post.init(fromDbRow: row as Any as! [String : Any])
                }
            }
        }
        return posts ?? [Post]()
    }

    /// Get count of all posts
    static func getPostCount() throws -> (posts: UInt, pages: UInt) {
        let pt = PostTable()
        let s = Select(count(pt.id).as("count"), from: pt)
        var postCount: Int? = nil
        MidnightPost.dbCxn?.execute(query: s) { queryResult in
            if let rows = queryResult.asRows, let value = rows.first?.first?.value as? Int32 {
                postCount = Int(value)
            }
        }
        if let postCount = postCount {
            if postCount == 0 {
                return (posts: 0, pages: 0)
            }
            else {
                return (posts: UInt(postCount), pages: UInt(ceil(Double(postCount) / Double(Post.postsPerPage))))
            }
        }
        else {
            throw PostError.FaultGettingCount
        }
    }
}
