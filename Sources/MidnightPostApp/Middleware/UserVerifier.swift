import Foundation
import Kitura

/// Middleware to ensure the user is logged in. And, in this current version,
/// is an admin.
public class UserVerifier: RouterMiddleware {
    public func handle(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        guard let level = request.session?["userLevel"] as? Int,
            let levelEnum = MidnightPost.UserLevel.init(rawValue: level),
            levelEnum == .admin else {
            try response.send(status: .forbidden).end()
            next()
            return
        }
        next()
    }
}
