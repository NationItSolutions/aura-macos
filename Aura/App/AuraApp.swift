import AppKit
import SwiftUI

@main
struct AuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("Aura", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 640)
                .preferredColorScheme(.dark)
                .onAppear { appDelegate.model = model }
        }
        .defaultSize(width: 1200, height: 780)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra(isInserted: Bindable(model.settings).menuBarEnabled) {
            MenuBarContent()
                .environment(model)
        } label: {
            Image(systemName: "dot.radiowaves.left.and.right")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // Arranca isla, atajos y agenda aunque la ventana no se abra (modo solo barra de menús).
        let model = AppModel.shared
        self.model = model
        model.startServices()
        if model.settings.menuBarEnabled && model.settings.menuBarOnly {
            for window in NSApp.windows where window.canBecomeMain { window.close() }
        }
        Log.app.info("Aura iniciada")
    }

    /// Con la barra de menús activa, cerrar la ventana no cierra la app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(model?.settings.menuBarEnabled ?? true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil) }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.store.flush()
    }
}
