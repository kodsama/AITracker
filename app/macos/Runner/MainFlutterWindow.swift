import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = NSRect(x: 0, y: 0, width: 1280, height: 860)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.center()
    // The hours table needs room for its columns.
    self.minSize = NSSize(width: 980, height: 620)
    self.title = "AITracking"

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
