import SwiftUI
import AppKit

/// Bridges `NSVisualEffectView` so SwiftUI views can sit on the system's
/// translucent material. On macOS 26+ this renders with the Liquid Glass look;
/// on earlier systems it's the classic vibrancy material.
///
/// The material's layer is rounded so the whole panel (including the top
/// corners, which a full-size-content window leaves square) gets a uniform
/// rounded-rect shape.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var cornerRadius: CGFloat = 13

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.layer?.cornerRadius = cornerRadius
    }
}
