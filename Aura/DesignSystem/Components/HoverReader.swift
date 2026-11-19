import SwiftUI

/// Expone el estado de hover y de habilitado a un closure.
/// Se usa dentro de los `ButtonStyle` para no guardar `@State` en el estilo.
struct HoverReader<Content: View>: View {
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @ViewBuilder let content: (_ hovering: Bool, _ isEnabled: Bool) -> Content

    var body: some View {
        content(hovering, isEnabled)
            .onHover { hovering = $0 }
    }
}
