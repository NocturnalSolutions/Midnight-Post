import Kitura
import MidnightPostApp

// MARK: Start the web app
let mp = MidnightPost()
mp.start()
Kitura.addHTTPServer(onPort: 8080, with: mp.generateRouter())
Kitura.run()

