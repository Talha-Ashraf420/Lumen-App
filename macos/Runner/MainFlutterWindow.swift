import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Lumen's UI is portrait/phone-shaped — open in a tall window and keep a
    // sensible minimum so layouts don't break.
    let initial = NSSize(width: 460, height: 900)
    self.setContentSize(initial)
    self.contentMinSize = NSSize(width: 380, height: 640)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
