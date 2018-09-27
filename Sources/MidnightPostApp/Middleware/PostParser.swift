import Foundation
import Kitura

/// Middleware to parse and validate incoming post or post revisions.
public class PostParser: RouterMiddleware {
    public func handle(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
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

        request.userInfo["postedPost"] = ["subject": subjValue, "body": bodyValue, /*"id" = postedId ?? ""*/]
        next()
    }
}
