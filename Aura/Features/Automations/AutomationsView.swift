import SwiftUI

/// Las automatizaciones por horario y los temporizadores llegan en M6.
/// Por ahora la sección explica cómo van a funcionar.
struct AutomationsView: View {
    var body: some View {
        PageScroll(title: String(localized: "Automatizaciones"),
                   subtitle: String(localized: "Acciones por horario y temporizadores rápidos.")) {
            EmptyStateView(
                symbol: "clock.arrow.2.circlepath",
                title: String(localized: "Todavía no hay automatizaciones"),
                message: String(localized: "Las automatizaciones corren mientras Aura esté abierta, incluso solo en la barra de menú.")
            )
        }
    }
}
