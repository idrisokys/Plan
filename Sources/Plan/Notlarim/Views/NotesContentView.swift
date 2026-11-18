import SwiftUI
import AppKit

struct NotesContentView: View {
    @EnvironmentObject var m: NotesModel

    var body: some View {
        Group {
            if m.root == nil { WelcomeView() } else if m.txt != nil { TxtView() } else { MainView() }
        }
        .frame(minWidth: 280, minHeight: 360)
        .background(NT.bg)
        .preferredColorScheme(.dark)   // Android Notlarım ekranı gibi her zaman koyu
        .background(WindowDock())
        .onAppear { m.reload(); m.installReorderMonitors() }
        // Uygulamaya her dönüşte liste kendiliğinden yenilenir.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in m.reload() }
        .onExitCommand { m.goBack() }
    }
}

/// Pencerenin her zaman üstte kalıp kalmayacağını açıp kapatan raptiye (solda, diğer düğmelerin yanında).
struct PinButton: View {
    @EnvironmentObject var m: NotesModel
    var body: some View {
        IconBtn(MI.pin, tint: m.alwaysOnTop ? NT.primary : NT.onSurfaceVariant.opacity(0.7),
                help: m.alwaysOnTop
                    ? L("Her zaman üstte: açık (kapatmak için tıkla)", "Always on top: on (click to turn off)")
                    : L("Her zaman üstte: kapalı (açmak için tıkla)", "Always on top: off (click to turn on)")) {
            m.alwaysOnTop.toggle()
        }
    }
}
