import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
  let minContentSize: NSSize

  func makeNSView(context: Context) -> NSView {
    NSView(frame: .zero)
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async {
      guard let window = nsView.window else { return }

      // Keep the window vertically resizable even when the SwiftUI view tree changes.
      // Some view combinations can temporarily inflate the auto-computed minimum height.
      let min = self.minContentSize
      if window.contentMinSize != min {
        window.contentMinSize = min
      }

      // Also set frame-level minSize to match, so resizing behaves consistently.
      let titleBarHeight = window.frame.height - window.contentLayoutRect.height
      let frameMin = NSSize(width: min.width, height: min.height + max(0, titleBarHeight))
      if window.minSize != frameMin {
        window.minSize = frameMin
      }

      if !window.styleMask.contains(.resizable) {
        window.styleMask.insert(.resizable)
      }
    }
  }
}

