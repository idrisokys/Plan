import SwiftUI
import AppKit

/// Notlarım penceresi: menü çubuğundaki kalem düğmesiyle açılır (tek pencere, ekranın sağ kenarına tutturulur).
@MainActor
enum NotesWindow {
    static let id = "plan"

    /// Pencereyi kullanıcı mı açtı? `Window` sahnesi uygulama açılırken kendiliğinden görünürse
    /// `WindowDock` onu hemen kapatır; menü çubuğu uygulaması açılışta pencere göstermez.
    static var requested = false

    /// SwiftUI'nin pencere açma eylemi (sahne ya da menü görünümü ilk göründüğünde saklanır);
    /// AppDelegate gibi SwiftUI dışı yerlerden de pencere açabilmek için.
    static var opener: OpenWindowAction?

    /// Açık Notlarım penceresi (WindowDock doldurur); kalem düğmesi aç/kapat için.
    static weak var window: NSWindow?

    /// Kalem düğmesi: pencere açıksa kapatır, değilse açar.
    static func toggle() {
        if requested, let w = window, w.isVisible { w.close() } else { show() }
    }

    /// Pencereyi açar / öne getirir (SwiftUI dışından, örn. plan://search adresi için).
    static func show() {
        requested = true
        // Pencere açıkken Dock simgesi ve menü çubuğu (Notlarım menüsü, ⌘ kısayolları) görünsün.
        NSApp.setActivationPolicy(.regular)
        opener?(id: id)
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
    }

    /// Menü çubuğundaki kalem düğmesi.
    static func open(_ openWindow: OpenWindowAction) {
        opener = openWindow
        show()
    }

    /// Pencere kapanınca uygulama yeniden yalnızca menü çubuğunda kalır.
    static func didClose() {
        requested = false
        if !ImageEditorWindow.hasWindows { NSApp.setActivationPolicy(.accessory) }
    }
}
