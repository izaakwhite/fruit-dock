import AppKit
import FruitDockUI

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Menu-bar-only: no icon in the system Dock, no app switcher entry.
// FR-5.1. Set in code rather than via Info.plist's LSUIElement so the
// executable behaves correctly before it is wrapped in a bundle.
app.setActivationPolicy(.accessory)

app.run()
