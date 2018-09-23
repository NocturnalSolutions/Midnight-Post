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
            ("testNewPost", testNewPost),
            ("testFrontPage", testFrontPage),
            ("testPostEdit", testPostEdit),
        ]
    }

    let mp = MidnightPost()

    public override func setUp() {
        mp.config["test-mode"] = true as Any
        mp.start()
        try? mp.installDb()
        router = mp.generateRouter()
        requestOptions = ClientRequest.parse("http://localhost:8080/")
        continueAfterFailure = false
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

    func testNewPost() {
        testResponse("/admin/new", checker: checkString("<textarea"), checkString("<form"))
        let postFields: [String: [String]] = ["body": ["baz"], "subject": ["qux"]]
        try? testPostResponse("/admin/new", fields: postFields, enctype: .Multipart, checker: checkString("baz"))
        requestOptions.append(.maxRedirects(0))
        try? testPostResponse("/admin/new", fields: postFields, enctype: .Multipart, checker: checkStatus(.seeOther))
        print("testNewPost")
    }

    func testFrontPage() {
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
        print("testFrontPage")
    }

    func testPostEdit() {
        let newPostFields = ["body": ["foo"], "subject": ["bar"]]
        try? testPostResponse("/admin/new", fields: newPostFields, enctype: .Multipart, checker: checkString("Edit"), checkString("post/1/edit"))
        let editFields = ["body": ["baz"], "subject": ["qux"]]
        try? testPostResponse("/post/1/edit", fields: editFields, enctype: .Multipart, checker: checkString("qux"))
        requestOptions.append(.maxRedirects(0))
        try? testPostResponse("/post/1/edit", fields: editFields, enctype: .Multipart, checker: checkStatus(.seeOther))
        print("testPostEdit")
    }
}


