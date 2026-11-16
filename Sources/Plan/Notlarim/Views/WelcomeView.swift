import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var m: NotesModel
    var body: some View {
        VStack(spacing: 14) {
            Text(L("Notlarım", "My Notes")).font(.largeTitle)
            Text(L("Linkler ana dizindeki Link klasörüne kaydedilir, ancak bu klasör oluşturulamadı veya yazılamıyor.", "Links are saved to the Link folder in your home directory, but it could not be created or written to."))
            Button(L("Tekrar dene", "Try again")) { m.reload() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
