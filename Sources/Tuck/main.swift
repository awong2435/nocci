import AppKit

// Synchronous on purpose: an `await` here makes all of startup one main-actor job that never ends
// (app.run() doesn't return), and every other main-actor task would wait behind it forever.
if SpikeCommands.runIfRequested(CommandLine.arguments) {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
