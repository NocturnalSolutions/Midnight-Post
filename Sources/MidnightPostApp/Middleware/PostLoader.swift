import Foundation
import Kitura

/// Middleware to load requested single posts, or throw a 404 if it can't be
/// loaded.
public class PostLoader: RouterMiddleware {
    public func handle(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        guard let postIdStr = request.parameters["post"], let postId = UInt(postIdStr) else {
            try response.send(status: .notFound).end()
            next()
            return
        }
        do {
            request.userInfo["loadedPost"] = try Post(loadId: postId)
        }
        catch {
            try response.send(status: .notFound).end()
        }
        next()
    }
}
