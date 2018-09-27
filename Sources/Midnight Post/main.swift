import Kitura
import MidnightPostApp

// MARK: Start the web app
let mp = MidnightPost()
mp.start()
let port = (mp.config["test-mode"] as? Bool ?? false) ? mp.config["test-port"] as! Int? : mp.config["port"] as! Int?
Kitura.addHTTPServer(onPort: port ?? 8080, with: mp.generateRouter())
Kitura.run()

