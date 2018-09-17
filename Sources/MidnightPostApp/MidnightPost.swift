import Kitura
import KituraStencil
import Stencil
import SwiftKuery
import SwiftKuerySQLite
import Foundation
import Configuration_INIDeserializer
import Configuration
import KituraMarkdown

public class MidnightPost {

    static var dbCxn: SQLiteConnection?
    static var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    public let config: ConfigurationManager

    public enum MidnightPostError: Error{
        case databaseInstallationError
    }

    public init() {
        config = ConfigurationManager()
        config.use(INIDeserializer())

        config.load([
            // Config file location
            "config": "~/.midnight-post.conf",
            // Database file path
            "database-path": "~/Databases/midnight-post.sqlite",
            // Test database path
            "test-database-path": "~/Databases/midnight-post-test.sqlite",
            ])

        // Load CLI arguments first because an overriding config file path may have been
        // specified
        config.load(.commandLineArguments)
        if let configFileLoc = config["config"] as? String {
            config.load(file: configFileLoc)
            // Load CLI arguments again because we want those to override settings in the
            // config file
            config.load(.commandLineArguments)
        }
    }

    public func start() {
        connectDb()
    }

    public func connectDb() {
        let testMode = config["test-mode"] as? Bool ?? false
        // Can't cast directly to NSString on Linux, apparently
        guard let dbPath = testMode ? config["test-database-path"] as? String : config["database-path"] as? String else {
            print("Cannot determine database path")
            exit(1)
        }
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

    func getFrontPagePosts(response: RouterResponse, page: UInt = 0) throws {
        guard let postCount = try? Post.getPostCount() else {
            response.send(status: .internalServerError).send("Error occurred.")
            return
        }
        guard page <= postCount.pages else {
            try response.send(status: .notFound).end()
            return
        }
        let posts = Post.getNewPosts()
        let formattedPosts = posts.map { $0.prepareForView() }
        try response.render("front", context: [
            "posts": formattedPosts,
            "postCount": postCount.posts,
            "pageCount": postCount.pages,
            "curPage": page
            ])
    }

    public func generateRouter() -> Router {
        let r = Router()

        // Add some custom filters to Stencil
        let ext = Extension()
        ext.registerFilter("inc") { value in
            guard let int = value as? UInt else {
                return ""
            }
            return String(int + 1)
        }
        ext.registerFilter("dec") { value in
            guard let int = value as? UInt else {
                return ""
            }
            return String(int - 1)
        }
        r.setDefault(templateEngine: StencilTemplateEngine(extension: ext))

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
                try response.render("view-post", context: post.prepareForView())
            }
            catch {
                try response.send(status: .internalServerError).end()
                next()
                return
            }
            next()
        }

        // MARK: Page back from front page
        r.get("/front/:page(\\d+)") { request, response, next in
            guard let page = request.parameters["page"], let pageInt = UInt(page) else {
                try response.send(status: .notFound).end()
                next()
                return
            }
            if pageInt == 0 {
                try response.redirect("/").end()
            }
            else {
                try self.getFrontPagePosts(response: response, page: pageInt)
            }
            next()
        }

        // MARK: Front page
        r.get("/") { request, response, next in
            try self.getFrontPagePosts(response: response)
            next()
        }

        return r
    }
}
