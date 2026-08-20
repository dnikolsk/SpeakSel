import SwiftUI
import AppKit

enum HUD {
    @MainActor
    private static var panel: NSPanel?
    @MainActor
    private static var hideWork: DispatchWorkItem?

    @MainActor
    static func show(_ text: String) {
        hideWork?.cancel()
        let panel = existingPanel()
        let host = NSHostingView(rootView: HUDView(text: text))
        host.frame = NSRect(origin: .zero, size: NSSize(width: 360, height: 56))
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        let size = host.fittingSize
        panel.setContentSize(NSSize(width: max(220, size.width + 8), height: max(44, size.height + 4)))
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - panel.frame.width / 2
            let y = screen.visibleFrame.minY + 96
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.orderFrontRegardless()

        let work = DispatchWorkItem {
            panel.orderOut(nil)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    @MainActor
    private static func existingPanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 48),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        self.panel = panel
        return panel
    }
}

private struct HUDView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.black.opacity(0.82), in: Capsule())
            .padding(8)
    }
}
