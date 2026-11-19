import AppKit
import SwiftUI

/// Dial circular de temperatura. Se arrastra, responde al scroll y a las flechas del teclado.
/// Mientras se arrastra solo cambia el valor local; el envío ocurre en `onCommit`.
struct Dial: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    /// Valores habilitados (p. ej. temperaturas grabadas). `nil` = todos.
    var available: Set<Int>?
    var style: Style = .cool
    var isOn: Bool = true
    var caption: String?
    var diameter: CGFloat = 280
    let onCommit: (Int) -> Void

    enum Style { case cool, heat, neutral }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var hovering = false
    @State private var dragging = false
    @State private var commitTask: Task<Void, Never>?
    @State private var scrollMonitor = ScrollWheelMonitor()

    private let startAngle = 135.0
    private let sweep = 270.0
    private var lineWidth: CGFloat { diameter * 0.075 }

    private var fraction: Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        return Double(value - range.lowerBound) / Double(range.upperBound - range.lowerBound)
    }

    private var gradient: AngularGradient {
        let colors: [Color] = switch style {
        case .cool: [Theme.Palette.primary, Theme.Palette.accent]
        case .heat: [Theme.Palette.warning, Color(rgb: 0xFF6B3D)]
        case .neutral: [Theme.Palette.textSecondary, Theme.Palette.textPrimary]
        }
        return AngularGradient(colors: colors, center: .center,
                               startAngle: .degrees(startAngle), endAngle: .degrees(startAngle + sweep))
    }

    private var tint: Color {
        switch style {
        case .cool: Theme.Palette.primary
        case .heat: Theme.Palette.warning
        case .neutral: Theme.Palette.textSecondary
        }
    }

    var body: some View {
        ZStack {
            // Halo
            Circle()
                .fill(RadialGradient(colors: [tint.opacity(isOn ? 0.22 : 0.05), .clear],
                                     center: .center, startRadius: diameter * 0.1, endRadius: diameter * 0.6))
                .frame(width: diameter * 1.2, height: diameter * 1.2)

            // Pista
            ArcShape(start: startAngle, sweep: sweep, fraction: 1)
                .stroke(Theme.Palette.surfaceElevated, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            ticks

            // Progreso
            ArcShape(start: startAngle, sweep: sweep, fraction: fraction)
                .stroke(isOn ? AnyShapeStyle(gradient) : AnyShapeStyle(Theme.Palette.textTertiary),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .shadow(color: isOn ? tint.opacity(0.5) : .clear, radius: 12)

            knob

            VStack(spacing: 2) {
                HStack(alignment: .top, spacing: 2) {
                    Text("\(value)")
                        .font(Typography.value(diameter * 0.25))
                        .contentTransition(.numericText(value: Double(value)))
                    Text("°C")
                        .font(.system(size: diameter * 0.07, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .padding(.top, diameter * 0.04)
                }
                .foregroundStyle(isOn ? Theme.Palette.textPrimary : Theme.Palette.textTertiary)
                if let caption {
                    Text(caption).font(Typography.label).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(dragGesture)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { step(+1); return .handled }
        .onKeyPress(.rightArrow) { step(+1); return .handled }
        .onKeyPress(.downArrow) { step(-1); return .handled }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onHover { inside in
            hovering = inside
            if inside {
                scrollMonitor.start { delta in step(delta > 0 ? +1 : -1) }
            } else {
                scrollMonitor.stop()
            }
        }
        .onDisappear { scrollMonitor.stop() }
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : Theme.Motion.quick, value: value)
        .accessibilityElement()
        .accessibilityLabel(Text("Temperatura"))
        .accessibilityValue(Text("\(value) grados"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(+1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
    }

    private var ticks: some View {
        let count = range.upperBound - range.lowerBound
        return ZStack {
            ForEach(0...max(count, 0), id: \.self) { index in
                let temp = range.lowerBound + index
                let enabled = available?.contains(temp) ?? true
                let angle = startAngle + sweep * Double(index) / Double(max(count, 1))
                Capsule()
                    .fill(enabled ? Theme.Palette.textSecondary.opacity(0.6) : Theme.Palette.textTertiary.opacity(0.25))
                    .frame(width: 2, height: enabled ? 8 : 5)
                    .offset(y: -(diameter / 2 - lineWidth * 1.9))
                    .rotationEffect(.degrees(angle + 90))
            }
        }
    }

    private var knob: some View {
        let angle = Angle.degrees(startAngle + sweep * fraction)
        let radius = diameter / 2 - lineWidth / 2
        return Circle()
            .fill(Color.white)
            .frame(width: lineWidth * 1.15, height: lineWidth * 1.15)
            .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
            .scaleEffect(dragging ? 1.2 : 1)
            .offset(x: cos(angle.radians) * radius, y: sin(angle.radians) * radius)
            .opacity(isOn ? 1 : 0.5)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                dragging = true
                focused = true
                let center = CGPoint(x: diameter / 2, y: diameter / 2)
                let dx = gesture.location.x - center.x
                let dy = gesture.location.y - center.y
                var degrees = Double(atan2(dy, dx)) * 180 / .pi
                if degrees < 0 { degrees += 360 }
                var relative = degrees - startAngle
                if relative < 0 { relative += 360 }
                // La zona muerta inferior (entre el fin y el inicio del arco) se pega al extremo más cercano.
                if relative > sweep { relative = relative - sweep < (360 - sweep) / 2 ? sweep : 0 }
                let raw = Double(range.lowerBound) + relative / sweep * Double(range.upperBound - range.lowerBound)
                setValue(snap(Int(raw.rounded())))
            }
            .onEnded { _ in
                dragging = false
                onCommit(value)
            }
    }

    private func step(_ delta: Int) {
        var candidate = value + delta
        if let available, !available.isEmpty {
            while range.contains(candidate), !available.contains(candidate) { candidate += delta }
        }
        guard range.contains(candidate) else { return }
        setValue(candidate)
        scheduleCommit()
    }

    private func setValue(_ newValue: Int) {
        guard newValue != value else { return }
        value = newValue
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// Ajusta al valor habilitado más cercano.
    private func snap(_ raw: Int) -> Int {
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        guard let available, !available.isEmpty else { return clamped }
        return available.min { abs($0 - clamped) < abs($1 - clamped) } ?? clamped
    }

    /// Teclado y scroll: agrupa cambios rápidos en un solo envío.
    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            onCommit(value)
        }
    }
}

/// Arco parcial de circunferencia.
struct ArcShape: Shape {
    var start: Double
    var sweep: Double
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius - 0.5,
                    startAngle: .degrees(start), endAngle: .degrees(start + sweep * max(fraction, 0.0001)),
                    clockwise: false)
        return path
    }
}

/// Escucha la rueda del mouse / trackpad solo mientras el puntero está sobre una vista.
@MainActor
final class ScrollWheelMonitor {
    private var monitor: Any?
    private var accumulated: CGFloat = 0

    func start(_ handler: @escaping @MainActor (CGFloat) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 12 : event.scrollingDeltaY
                self.accumulated += delta
                if abs(self.accumulated) >= 1 {
                    handler(self.accumulated)
                    self.accumulated = 0
                }
            }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        accumulated = 0
    }
}
