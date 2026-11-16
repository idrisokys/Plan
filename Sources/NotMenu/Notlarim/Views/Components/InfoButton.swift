import SwiftUI
import AppKit

/// Araç çubuğunun en sağındaki bilgi (i) ikonu: gemi resmi, e-posta ve GitHub adresini gösteren küçük menü açar.
struct InfoButton: View {
    @EnvironmentObject var m: NotesModel
    @State private var shown = false

    var body: some View {
        // Dokun: bilgi menüsü. Basılı tut: Link klasöründeki her şey .onemsiz klasörüne taşınır.
        Image(systemName: "info.circle")
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .onTapGesture { shown.toggle() }
            .onLongPressGesture(minimumDuration: 0.8) { m.moveAllToOnemsiz() }
            .help(L("Bilgi (basılı tut: Link klasörünü .onemsiz'e taşı)", "Info (long-press: move the Link folder to .onemsiz)"))
            .popover(isPresented: $shown, arrowEdge: .bottom) {
                VStack(spacing: 4) {
                    if let img = NSImage(named: "releases_icon") {
                        Image(nsImage: img).resizable().scaledToFill()
                            .frame(width: 36, height: 36).clipShape(Circle())
                    }
                    Text(AppInfo.contactEmail).textSelection(.enabled)
                    Link(AppInfo.githubURL.absoluteString, destination: AppInfo.githubURL)
                }
                .font(.system(size: 11))
                .padding(8)
            }
    }
}
