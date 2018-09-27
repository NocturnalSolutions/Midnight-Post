import Foundation
import Kitura
import KituraNet
import XCTest
import Kitura
import MidnightTest
@testable import MidnightPostApp

class PostTest: MidnightTestCase {

    static var allTests: [(String, (PostTest) -> () throws -> Void)] {
        return [
            ("testFrontPage", testFrontPage),
            ("testAuthAndAccess", testAuthAndAccess),
            ("testNewPost", testNewPost),
            ("testPostEdit", testPostEdit),
        ]
    }

    let mp = MidnightPost()
    let adminPassword = "swordfish"

    public override func setUp() {
        mp.config["test-mode"] = true as Any
        mp.config["admin-password"] = adminPassword as Any
        mp.start()
        try? mp.installDb()
        router = mp.generateRouter()
        requestOptions = ClientRequest.parse("http://localhost:8080/")
        continueAfterFailure = false
        useCookies = true
        super.setUp()
    }

    public override func tearDown() {
        do {
            try mp.destroyDb()
        }
        catch {
            fatalError("Could not destroy database after testing.")
        }
        super.tearDown()
    }

    func logIn() {
        let previousRequestModifier = requestModifier
        requestModifier = { request in
            if let reqMod = previousRequestModifier {
                reqMod(request)
            }
            request.set(.maxRedirects(0))
        }
        let loginFields = ["username": ["Admin"], "password": [adminPassword]]
        try? testPostResponse("/log-in", fields: loginFields, enctype: .Multipart)
        requestModifier = previousRequestModifier
    }

    func testAuthAndAccess() {
        // Log in
        testResponse("/log-in", checker: checkStatus(.OK))
        let loginFields = ["username": ["Admin"], "password": [adminPassword]]
        let invalidLoginFields = ["username": ["Admin"], "password": ["asdflol"]]
        // Test logging in with bad credentials
        try? testPostResponse("/log-in", fields: invalidLoginFields, enctype: .Multipart, checker: checkString("Invalid credentials"))
        // Test logging in with good credentials
        requestModifier = { request in request.set(.maxRedirects(0)) }
        try? testPostResponse("/log-in", fields: loginFields, enctype: .Multipart, checker: checkStatus(.seeOther))
        requestModifier = { request in request.set(.maxRedirects(10)) }
        // Log in form should have "You're already logged in" message
        testResponse("/log-in", checker: checkString("already"))
        // Access to the new post form
        testResponse("/admin/new", checker: checkStatus(.OK))
        // Access to posting a new post
        let postFields: [String: [String]] = ["body": ["baz"], "subject": ["qux"]]
        try? testPostResponse("/admin/new", fields: postFields, enctype: .Multipart, checker: checkStatus(.OK))
        // Access to edit form
        testResponse("/post/1/edit", checker: checkStatus(.OK))
        // Access to editing a post
        try? testPostResponse("/post/1/edit", fields: postFields, enctype: .Multipart, checker: checkStatus(.OK))
        // Access to log out handler (also, log out)
        testResponse("/log-out", checker: checkStatus(.OK))
        // No longer have access to new post form
        testResponse("/admin/new", checker: checkStatus(.forbidden))
        // No longer have access to post edit form
        testResponse("/post/1/edit", checker: checkStatus(.forbidden))
    }

    func testNewPost() {
        logIn()

        testResponse("/admin/new", checker: checkString("<textarea"), checkString("<form"))
        let postFields: [String: [String]] = ["body": ["baz"], "subject": ["qux"]]
        try? testPostResponse("/admin/new", fields: postFields, enctype: .Multipart, checker: checkString("baz"))
        requestOptions.append(.maxRedirects(0))
        try? testPostResponse("/admin/new", fields: postFields, enctype: .Multipart, checker: checkStatus(.seeOther))
    }

    func testFrontPage() {
        logIn()

        let postFields = ["body": ["baz"], "subject": ["qux"]]
        try? testPostResponse("/admin/new", fields: postFields, enctype: .Multipart)
        // Check new post appears on front page
        testResponse("/", checker: checkString("baz"), checkString("qux"))

        let newPostFields = ["body": ["foo"], "subject": ["bar"]]
        for _ in 0...Post.postsPerPage {
            try? testPostResponse("/admin/new", fields: newPostFields, enctype: .Multipart)
        }

        // Check we now have a link to the next page
        testResponse("/", checker: checkString("/front/1"))
        // Check that the first post is now on the "second" page
        testResponse("/front/1", checker: checkString("baz"))
    }

    func testPostEdit() {
        logIn()

        let newPostFields = ["body": ["foo"], "subject": ["bar"]]
        try? testPostResponse("/admin/new", fields: newPostFields, enctype: .Multipart, checker: checkString("Edit"), checkString("post/1/edit"))
        let editFields = ["body": ["baz"], "subject": ["qux"]]
        try? testPostResponse("/post/1/edit", fields: editFields, enctype: .Multipart, checker: checkString("qux"))
        requestOptions.append(.maxRedirects(0))
        try? testPostResponse("/post/1/edit", fields: editFields, enctype: .Multipart, checker: checkStatus(.seeOther))
    }
}


