import SwiftUI

extension Color {
    /// Shared accent across the apps and their website: Claude's clay orange, a touch lighter.
    static let brand = Color(red: 227 / 255, green: 139 / 255, blue: 109 / 255) // #E38B6D
}

/// True while `--render-preview` draws marketing images; AppKit-backed controls are swapped for static
/// stand-ins because ImageRenderer can't draw them.
@MainActor var isRenderingPreview = false
