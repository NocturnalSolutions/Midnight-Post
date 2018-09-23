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

    lazy var dbLocation: Location = {
        let testMode = config["test-mode"] as? Bool ?? false
        // Can't cast directly to NSString on Linux, apparently
        guard let dbPath = testMode ? config["test-database-path"] as? String : config["database-path"] as? String else {
            print("Cannot determine database path")
            exit(1)
        }
        if dbPath == "" {
            print("WARNING! Using volatile in-memory database. Data loss is inevitable. If this is not intended, you probably need to set the \"database-path\" configuration value.")
            return .inMemory
        }
        else {
            let nsDbPath = NSString(string: dbPath)
            // Redundant type label below is required to avoid a segfault on compilation for
            // some effing reason.
            let expandedDbPath: String = String(nsDbPath.expandingTildeInPath)
            return .uri(expandedDbPath)
        }
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
            // Test database path. An empty string means use an in-memory DB.
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
        MidnightPost.dbCxn = SQLiteConnection(dbLocation)
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

    /// Destroy the database file. For resetting the DB when running tests.
    public func destroyDb() throws {
        if MidnightPost.dbCxn?.isConnected == true {
            MidnightPost.dbCxn?.closeConnection()
        }
        switch dbLocation {
        case .uri(let path):
            try FileManager().removeItem(atPath: path)
        default: break
        // If the database was .inMemory, it was destroyed when we closed the
        // connection.
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

        let postParser = PostParser()
        let postLoader = PostLoader()

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
        r.post("/admin/new", middleware: postParser)
        r.post("/admin/new") { request, response, next in
            guard let postedPost = request.userInfo["postedPost"] as? [String: String] else {
                try response.send(status: .unprocessableEntity).end()
                next()
                return
            }
            do {
                let post = try Post(subject: postedPost["subject"]!, body: postedPost["body"]!)
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
        r.get("/post/:post(\\d+)", middleware: postLoader)
        r.get("/post/:post(\\d+)") { request, response, next in
            guard let post = request.userInfo["loadedPost"] as? Post else {
                next()
                return
            }
            try response.render("view-post", context: post.prepareForView())
            next()
        }

        // MARK: Show form to edit a post
        r.get("/post/:post(\\d+)/edit") { request, response, next in
            guard let post = request.userInfo["loadedPost"] as? Post else {
                next()
                return
            }
            try response.render("admin-edit-post", context: ["post": post])
            next()
        }

        // MARK: Take and save a post revision
        r.post("/post/:post(\\d+)/edit", middleware: postLoader, postParser)
        r.post("/post/:post(\\d+)/edit") { request, response, next in
            guard let post = request.userInfo["loadedPost"] as? Post,
                let postedPost = request.userInfo["postedPost"] as? [String: String] else {
                    next()
                    return
            }
            do {
                try post.addNewRevision(subject: postedPost["subject"]!, body: postedPost["body"]!)
                try response.redirect("/post/\(post.id)", status: .seeOther)
            }
            catch {
                try response.send(status: .internalServerError).end()
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
