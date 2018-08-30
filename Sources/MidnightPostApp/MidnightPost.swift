import Kitura
import KituraStencil
import SwiftKuery
import SwiftKuerySQLite
import Foundation

public class MidnightPost {

    static var dbCxn: SQLiteConnection?
    static var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    public enum MidnightPostError: Error{
        case databaseInstallationError
    }

    public init() {
        connectDb()
    }

    public init(testMode: Bool = false) {
        connectDb(testMode: testMode)
    }

    public func connectDb(testMode: Bool = false) {
        // Can't cast directly to NSString on Linux, apparently
        let dbPath = testMode ? FileManager.default.temporaryDirectory.absoluteString + UUID().uuidString + ".sqlite" : "~/Databases/midnight-post.sqlite"
        let nsDbPath = NSString(string: dbPath)
        // Redundant type label below is required to avoid a segfault on compilation for
        // some effing reason.
        let expandedDbPath: String = String(nsDbPath.expandingTildeInPath)
        MidnightPost.dbCxn = SQLiteConnection(filename: expandedDbPath)
        MidnightPost.dbCxn?.connect() { error in
            if let error = error {
                print("Failure opening database: \(error.description)")
                exit(1)
            }
        }
    }

    public func installDb() throws {
        let pt = PostTable()
        let rt = PostRevisionTable()

        _ = rt.foreignKey(rt.postId, references: pt.id)
        _ = rt.primaryKey(rt.postId, rt.id)

        var errorOccurred = false
        pt.create(connection: MidnightPost.dbCxn!) { result in
            guard result.success else {
                errorOccurred = true
//                throw MidnightPostError.tableCreationFailed
//                let buildSql = try! pt.description(connection: MidnightPost.dbCxn!)
//                try? response.send(status: .internalServerError)
//                    .send("Cannot create post table: \(result.asError.debugDescription)\n\(buildSql)")
//                    .end()
                return
            }
            rt.create(connection: MidnightPost.dbCxn!) { result in
                guard result.success else {
                    errorOccurred = true
//                    let buildSql = try! rt.description(connection: MidnightPost.dbCxn!)
//                    try? response.send(status: .internalServerError)
//                        .send("Cannot create post revision table: \(result.asError.debugDescription)\n\(buildSql)")
//                        .end()
                    return
                }
            }
        }
        if errorOccurred {
            throw MidnightPostError.databaseInstallationError
        }
    }

    public func generateRouter() -> Router {
        let r = Router()
        r.setDefault(templateEngine: StencilTemplateEngine())

        r.post(middleware: BodyParserMultiValue())

        r.get("/install") { request, response, next in
            do {
                try self.installDb()
                response.send("Apparent success")
            }
            catch {
                response.send(status: .internalServerError).send("Error occurred.")
            }
        }

        // MARK: New post creation page
        r.get("/admin/new") { request, response, next in
            try response.render("admin-edit-post", context: [:])
            next()
        }

        // MARK: New post submit handler
        r.post("/admin/new") { request, response, next in
            guard let postBody = request.body?.asMultiPart else {
                try response.send(status: .unprocessableEntity).end()
                next()
                return
            }
            var postedSubject: String?
            var postedBody: String?
            for part in postBody {
                if part.name == "body" {
                    postedBody = part.body.asText
                }
                else if part.name == "subject" {
                    postedSubject = part.body.asText
                }
            }

            guard let bodyValue = postedBody, let subjValue = postedSubject else {
                try response.send(status: .unprocessableEntity).end()
                next()
                return
            }
            do {
                let post = try Post(subject: subjValue, body: bodyValue)
                try response.redirect("/post/\(post.id)", status: .seeOther)
            }
            catch  {
                try response.send(status: .internalServerError).end()
                next()
                return
            }
            next()
        }

        // MARK: Show a post
        r.get("/post/:post(\\d+)") { request, response, next in
            guard let postIdStr = request.parameters["post"], let postId = UInt(postIdStr) else {
                try response.send(status: .notFound).end()
                next()
                return
            }
            do {
                let post = try Post(loadId: postId)
                try response.render("view-post", context: ["post": post])
            }
            catch {
                try response.send(status: .internalServerError).end()
                next()
                return
            }
            next()
        }

        return r
    }
}
