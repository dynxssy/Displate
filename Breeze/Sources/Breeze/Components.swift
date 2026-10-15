import AppKit
import SwiftUI

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct IconButton: View {
    let symbol: String
    var active = false
    var help = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? Color.white : Color.primary.opacity(0.75))
                .frame(width: 24, height: 24)
                .background(Circle().fill(active ? Color.brand : Color.primary.opacity(hovering ? 0.12 : 0.0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(help)
    }
}

struct CapsuleButton: View {
    let title: String
    var symbol: String?
    var tint: Color = .brand
    var prominent = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                }
                Text(title)
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Capsule().fill(prominent ? tint.opacity(hovering ? 0.85 : 1) : tint.opacity(hovering ? 0.2 : 0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// The app's mark: a sky gradient squircle with a fan.
struct AppBadge: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1.000, green: 0.584, blue: 0.635), Color(red: 1.000, green: 0.420, blue: 0.502), Color(red: 0.855, green: 0.271, blue: 0.369)],
                                     startPoint: .top, endPoint: .bottom))
            Image(systemName: "fan.fill")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

/// Green → yellow → red by temperature.
func temperatureColor(_ celsius: Double?) -> Color {
    guard let celsius else { return .secondary }
    if celsius < 60 { return .green }
    if celsius < 80 { return .yellow }
    if celsius < 92 { return .orange }
    return .red
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
