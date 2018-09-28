import Kitura
import MidnightPostApp

// MARK: Start the web app
let mp = MidnightPost()
mp.start()
let port = (mp.config["test-mode"] as? Bool ?? false) ? mp.config["test-port"] as! Int? : mp.config["port"] as! Int?
let router = mp.generateRouter()
if let path = mp.config["static-path"] as? String, path != "" {
    router.get("/static", middleware: StaticFileServer(path: path))
}
Kitura.addHTTPServer(onPort: port ?? 8080, with: router)
Kitura.run()

