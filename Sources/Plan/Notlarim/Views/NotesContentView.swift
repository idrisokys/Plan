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
