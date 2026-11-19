import AppKit
import Observation
import SwiftUI

/// Panel sin bordes que no activa la app al hacer clic.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Maneja el panel de la isla: posición junto al notch, hover, atajo, Esc, clic afuera y actividad.
@MainActor
final class IslandController {
    private let model: AppModel
    let island = IslandModel()

    private var panel: IslandPanel?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var hoverTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var activityTask: Task<Void, Never>?
    private var feedbackWatch: Task<Void, Never>?
    private var lastFeedbackID: UUID?

    /// Tamaño fijo del panel: entra la isla expandida más la sombra.
    private static let panelSize = CGSize(width: IslandModel.Geometry.expandedSize.width + 80,
                                          height: IslandModel.Geometry.expandedSize.height + 120)

    init(model: AppModel) {
        self.model = model
    }

    var isRunning: Bool { panel != nil }

    // MARK: - Ciclo de vida

    func start() {
        guard panel == nil else { return }
        let panel = IslandPanel(contentRect: CGRect(origin: .zero, size: Self.panelSize),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = true
        let root = IslandView(island: island).environment(model)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: Self.panelSize)
        panel.contentView = hosting
        self.panel = panel

        reposition()
        panel.orderFrontRegardless()
        installMonitors()
        watchFeedback()
        Log.island.info("Isla iniciada")
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        feedbackWatch?.cancel()
        hoverTask?.cancel()
        collapseTask?.cancel()
        activityTask?.cancel()
        panel?.orderOut(nil)
        panel = nil
        island.phase = .compact
    }

    /// Aplica cambios de ajustes (pantalla, pantalla completa).
    func refresh() {
        reposition()
        updateVisibility()
    }

    // MARK: - Geometría

    private var screen: NSScreen? {
        switch model.settings.islandScreen {
        case .notch: NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        case .main: NSScreen.main
        }
    }

    private func reposition() {
        guard let panel, let screen else { return }
        island.geometry = Self.geometry(for: screen)
        let frame = screen.frame
        let origin = CGPoint(x: frame.midX - Self.panelSize.width / 2, y: frame.maxY - Self.panelSize.height)
        panel.setFrame(CGRect(origin: origin, size: Self.panelSize), display: true)
    }

    static func geometry(for screen: NSScreen) -> IslandModel.Geometry {
        let top = screen.safeAreaInsets.top
        guard top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return .none }
        let notchWidth = screen.frame.width - left.width - right.width
        return IslandModel.Geometry(notchWidth: max(notchWidth, 0), notchHeight: top)
    }

    /// Rectángulo visible de la isla en coordenadas de pantalla.
    private func islandRect(for phase: IslandModel.Phase) -> CGRect {
        guard let panel else { return .zero }
        let size = island.geometry.size(for: phase)
        let frame = panel.frame
        return CGRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
    }

    // MARK: - Estados

    func toggle() {
        if island.phase == .expanded { collapse() } else { expand(focus: true) }
    }

    func expand(focus: Bool = false) {
        guard let panel, panel.isVisible else { return }
        hoverTask?.cancel()
        collapseTask?.cancel()
        activityTask?.cancel()
        if island.selectedDeviceID == nil { island.selectedDeviceID = model.quickDevices.first?.id }
        island.phase = .expanded
        panel.ignoresMouseEvents = false
        if focus { panel.makeKey() }
        if model.settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    func collapse() {
        collapseTask?.cancel()
        island.phase = .compact
        panel?.ignoresMouseEvents = true
        if panel?.isKeyWindow == true { panel?.resignKey() }
    }

    private func showActivity(_ feedback: CommandFeedback) {
        guard island.phase != .expanded else { return }
        activityTask?.cancel()
        island.phase = .activity(feedback)
        activityTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled, let self, case .activity = self.island.phase else { return }
            self.island.phase = .compact
        }
    }

    // MARK: - Eventos

    private func installMonitors() {
        let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moveMask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moveMask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.mouseMoved() }
            return event
        }) { monitors.append(local) }
        // Clic afuera: cierra.
        if let click = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.island.phase == .expanded else { return }
                if !self.islandRect(for: .expanded).contains(NSEvent.mouseLocation) { self.collapse() }
            }
        }) { monitors.append(click) }
        // Esc con la isla enfocada.
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.panel, event.keyCode == 53 else { return event }
                self.collapse()
                return nil
            }
        }) { monitors.append(keys) }

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateVisibility() }
        })
    }

    private func mouseMoved() {
        let point = NSEvent.mouseLocation
        switch island.phase {
        case .compact, .activity:
            let hotArea = islandRect(for: .compact).insetBy(dx: -6, dy: -4)
            if hotArea.contains(point) {
                guard hoverTask == nil else { return }
                hoverTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled, let self else { return }
                    self.hoverTask = nil
                    if self.islandRect(for: .compact).insetBy(dx: -6, dy: -4).contains(NSEvent.mouseLocation) {
                        self.expand()
                    }
                }
            } else {
                hoverTask?.cancel()
                hoverTask = nil
            }
        case .expanded:
            if islandRect(for: .expanded).insetBy(dx: -8, dy: -8).contains(point) {
                collapseTask?.cancel()
                collapseTask = nil
            } else if collapseTask == nil {
                collapseTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(600))
                    guard !Task.isCancelled, let self else { return }
                    self.collapseTask = nil
                    // No cerrar si el foco está en la isla por el atajo de teclado.
                    if self.panel?.isKeyWindow != true { self.collapse() }
                }
            }
        }
    }

    /// Oculta la isla cuando hay una app en pantalla completa (sin barra de menús).
    private func updateVisibility() {
        guard let panel else { return }
        let hide = model.settings.islandHideInFullscreen && !NSMenu.menuBarVisible()
        if hide, panel.isVisible {
            collapse()
            panel.orderOut(nil)
        } else if !hide, !panel.isVisible {
            reposition()
            panel.orderFrontRegardless()
        }
    }

    /// Muestra cada feedback nuevo del bus como actividad.
    private func watchFeedback() {
        feedbackWatch = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let feedback = await self.nextFeedback()
                guard !Task.isCancelled else { return }
                if let feedback, feedback.id != self.lastFeedbackID {
                    self.lastFeedbackID = feedback.id
                    self.showActivity(feedback)
                }
            }
        }
    }

    private func nextFeedback() async -> CommandFeedback? {
        await withCheckedContinuation { continuation in
            withObservationTracking {
                _ = model.bus.lastFeedback
            } onChange: {
                continuation.resume()
            }
        }
        return model.bus.lastFeedback
    }
}
