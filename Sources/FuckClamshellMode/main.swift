import Foundation

let monitor = ClamshellMonitor()
monitor.start()

// Keep the service running indefinitely so IOKit can deliver callbacks.
RunLoop.main.run()
